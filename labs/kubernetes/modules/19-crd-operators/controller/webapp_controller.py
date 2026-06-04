"""
WebApp operator (controller) for the lab.example.com/v1 WebApp CRD.

Назначение
----------
Следит за ресурсами WebApp в namespace ``lab`` и приводит состояние кластера
к их ``spec``: создаёт/обновляет Deployment и Service, а в ``status`` пишет
``availableReplicas`` из Deployment.

Архитектура (simplest operator pattern)
---------------------------------------
* **Informers + workqueue** на ресурс WebApp: watch API отдаёт события
  (ADDED / MODIFIED / DELETED), мы кладём key ``<ns>/<name>`` в очередь.
* **Reconcile loop** берёт ключ из очереди и приводит «фактическое» к
  «желаемому» — это и есть reconcile одного объекта (idempotent).
* Отдельный resync-таймер (--resync-period) раз в N секунд добавляет в очередь
  все известные WebApp — это даёт нам обновление ``status.availableReplicas``
  по факту Deployment, даже если сам CR не менялся.
* Deployment и Service владеются WebApp через ownerReference с
  ``controller=True`` — удаление WebApp уносит дочерние ресурсы самой
  garbage collection Kubernetes.

CRD-схема (см. manifests/crd.yaml)
----------------------------------
    spec.image    string   required
    spec.replicas integer  required, 1..10
    spec.host     string   optional
    status.availableReplicas integer
"""
from __future__ import annotations

import logging
import os
import signal
import sys
import time
from typing import Any

from kubernetes import client, config, watch
from kubernetes.client import ApiException
from kubernetes.client.rest import RESTResponse
from kubernetes.dynamic import DynamicClient

# ----------------------------------------------------------------------------
# Конфигурация контроллера. Значения по умолчанию рассчитаны на лабу, но
# позволяют переопределение через ENV (полезно в манифесте Deployment).
# ----------------------------------------------------------------------------
NAMESPACE = os.environ.get("WATCH_NAMESPACE", "lab")
GROUP = "lab.example.com"
VERSION = "v1"
PLURAL = "webapps"
KIND = "WebApp"
APP_LABEL = "app.kubernetes.io/name"
APP_INSTANCE_LABEL = "app.kubernetes.io/instance"
APP_MANAGED_BY_LABEL = "app.kubernetes.io/managed-by"
APP_MANAGED_BY_VALUE = "webapp-operator"
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
RESYNC_PERIOD = int(os.environ.get("RESYNC_PERIOD", "15"))  # секунд

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("webapp-operator")


# ----------------------------------------------------------------------------
# Хелперы: load incluster/kubeconfig.
# ----------------------------------------------------------------------------
def load_kube_config() -> None:
    """In-cluster приоритетнее, fallback на KUBECONFIG/домашний ~/.kube/config."""
    try:
        config.load_incluster_config()
        log.info("kube config: in-cluster")
    except config.ConfigException:
        config.load_kube_config()
        log.info("kube config: kubeconfig file")


# ----------------------------------------------------------------------------
# Маппинг CRD в Python dicts, удобные для использования в логике.
# ----------------------------------------------------------------------------
def webapp_spec(webapp: dict[str, Any]) -> dict[str, Any]:
    return webapp.get("spec") or {}


def webapp_name(webapp: dict[str, Any]) -> str:
    return webapp["metadata"]["name"]


def webapp_uid(webapp: dict[str, Any]) -> str:
    return webapp["metadata"]["uid"]


def webapp_resource_version(webapp: dict[str, Any]) -> str:
    return webapp["metadata"].get("resourceVersion", "")


# ----------------------------------------------------------------------------
# OwnerReference: связываем Deployment/Service с WebApp, чтобы GC
# автоматически убрал их при удалении CR.
# ----------------------------------------------------------------------------
def make_owner_ref(webapp: dict[str, Any]) -> dict[str, Any]:
    return {
        "apiVersion": f"{GROUP}/{VERSION}",
        "kind": KIND,
        "name": webapp_name(webapp),
        "uid": webapp_uid(webapp),
        "controller": True,
        "blockOwnerDeletion": True,
    }


def make_labels(name: str) -> dict[str, str]:
    return {
        APP_LABEL: KIND.lower(),
        APP_INSTANCE_LABEL: name,
        APP_MANAGED_BY_LABEL: APP_MANAGED_BY_VALUE,
    }


# ----------------------------------------------------------------------------
# Конструирование желаемых Deployment/Service.
# ----------------------------------------------------------------------------
def deployment_manifest(webapp: dict[str, Any]) -> dict[str, Any]:
    spec = webapp_spec(webapp)
    image = spec["image"]
    replicas = int(spec["replicas"])
    name = webapp_name(webapp)
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": name,
            "namespace": NAMESPACE,
            "labels": make_labels(name),
        },
        "spec": {
            "replicas": replicas,
            "selector": {"matchLabels": make_labels(name)},
            "template": {
                "metadata": {"labels": make_labels(name)},
                "spec": {
                    "containers": [
                        {
                            "name": "app",
                            "image": image,
                            "ports": [{"containerPort": 80, "name": "http"}],
                            "readinessProbe": {
                                "httpGet": {"path": "/", "port": 80},
                                "initialDelaySeconds": 2,
                                "periodSeconds": 5,
                            },
                        }
                    ]
                },
            },
        },
    }


def service_manifest(webapp: dict[str, Any]) -> dict[str, Any]:
    name = webapp_name(webapp)
    return {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": name,
            "namespace": NAMESPACE,
            "labels": make_labels(name),
        },
        "spec": {
            "type": "ClusterIP",
            "selector": make_labels(name),
            "ports": [
                {
                    "name": "http",
                    "port": 80,
                    "targetPort": 80,
                    "protocol": "TCP",
                }
            ],
        },
    }


# ----------------------------------------------------------------------------
# Низкоуровневые операции: get/create/update с обработкой конфликтов.
# Конфликт (HTTP 409) — нормальная ситуация при параллельных обновлениях:
# retry с свежим resourceVersion.
# ----------------------------------------------------------------------------
def _retry_after_conflict(fn, *args, **kwargs):
    """Выполняет ``fn``; при 409 Conflict повторяет до ``max_attempts`` раз."""
    for attempt in range(5):
        try:
            return fn(*args, **kwargs)
        except ApiException as exc:
            if exc.status == 409 and attempt < 4:
                log.debug("conflict, retry %s", attempt + 1)
                time.sleep(0.2 * (attempt + 1))
                continue
            raise
    raise RuntimeError("unreachable")


def ensure_deployment(
    apps_api: client.AppsV1Api, webapp: dict[str, Any]
) -> dict[str, Any]:
    name = webapp_name(webapp)
    desired = deployment_manifest(webapp)
    desired["metadata"]["ownerReferences"] = [make_owner_ref(webapp)]

    def _do():
        try:
            current = apps_api.read_namespaced_deployment(name, NAMESPACE)
            current_spec = current.spec.to_dict() if current.spec else {}
            current_replicas = current_spec.get("replicas")
            current_image = (
                current_spec.get("template", {})
                .get("spec", {})
                .get("containers", [{}])[0]
                .get("image")
            )
            desired_replicas = desired["spec"]["replicas"]
            desired_image = desired["spec"]["template"]["spec"]["containers"][0]["image"]

            if current_replicas != desired_replicas or current_image != desired_image:
                current.spec.replicas = desired_replicas
                current.spec.template.spec.containers[0].image = desired_image
                log.info(
                    "deployment %s/%s update replicas=%s image=%s",
                    NAMESPACE,
                    name,
                    desired_replicas,
                    desired_image,
                )
                return apps_api.patch_namespaced_deployment(
                    name, NAMESPACE, current
                )
            return current
        except ApiException as exc:
            if exc.status == 404:
                log.info(
                    "deployment %s/%s create image=%s replicas=%s",
                    NAMESPACE,
                    name,
                    desired["spec"]["template"]["spec"]["containers"][0]["image"],
                    desired["spec"]["replicas"],
                )
                return apps_api.create_namespaced_deployment(
                    namespace=NAMESPACE, body=desired
                )
            raise

    return _retry_after_conflict(_do)


def ensure_service(
    core_api: client.CoreV1Api, webapp: dict[str, Any]
) -> None:
    name = webapp_name(webapp)
    desired = service_manifest(webapp)
    desired["metadata"]["ownerReferences"] = [make_owner_ref(webapp)]

    def _do():
        try:
            core_api.read_namespaced_service(name, NAMESPACE)
            log.debug("service %s/%s already exists", NAMESPACE, name)
        except ApiException as exc:
            if exc.status == 404:
                log.info("service %s/%s create", NAMESPACE, name)
                return core_api.create_namespaced_service(
                    namespace=NAMESPACE, body=desired
                )
            raise

    _retry_after_conflict(_do)


def update_status(
    dyn: DynamicClient, webapp: dict[str, Any], available: int
) -> None:
    """Пишет status.availableReplicas через /status subresource (best-effort)."""
    name = webapp_name(webapp)
    res = dyn.resources.get(api_version=f"{GROUP}/{VERSION}", kind=KIND)
    try:
        res.status.patch(
            {"status": {"availableReplicas": int(available)}},
            namespace=NAMESPACE,
            name=name,
        )
    except Exception as exc:  # noqa: BLE001 — статус best-effort
        log.debug("status patch failed for %s/%s: %s", NAMESPACE, name, exc)


# ----------------------------------------------------------------------------
# Reconcile для одного WebApp — главная бизнес-логика оператора.
# ----------------------------------------------------------------------------
def reconcile(
    webapp: dict[str, Any],
    apps_api: client.AppsV1Api,
    core_api: client.CoreV1Api,
    dyn: DynamicClient,
) -> None:
    name = webapp_name(webapp)
    spec = webapp_spec(webapp)
    if not spec.get("image") or spec.get("replicas") is None:
        log.warning("webapp %s/%s has no spec, skip", NAMESPACE, name)
        return

    ensure_service(core_api, webapp)
    deploy = ensure_deployment(apps_api, webapp)

    available = 0
    try:
        status = deploy.status
        if status and status.available_replicas is not None:
            available = int(status.available_replicas)
    except Exception:  # noqa: BLE001
        pass

    update_status(dyn, webapp, available)
    log.info(
        "reconcile %s/%s ok: image=%s replicas=%s available=%s",
        NAMESPACE,
        name,
        spec.get("image"),
        spec.get("replicas"),
        available,
    )


# ----------------------------------------------------------------------------
# Главный цикл: watch WebApp + периодический resync.
# ----------------------------------------------------------------------------
def list_webapps(dyn: DynamicClient) -> list[dict[str, Any]]:
    res = dyn.resources.get(api_version=f"{GROUP}/{VERSION}", kind=KIND)
    return [
        obj.to_dict()
        for obj in res.get(namespace=NAMESPACE).items
    ]


def main() -> int:
    load_kube_config()
    apps_api = client.AppsV1Api()
    core_api = client.CoreV1Api()
    dyn = DynamicClient(client.ApiClient())

    log.info(
        "webapp-operator starting (ns=%s, group=%s, resync=%ss)",
        NAMESPACE,
        GROUP,
        RESYNC_PERIOD,
    )

    stop = {"flag": False}

    def _sigterm(signum, frame):  # noqa: ARG001
        log.info("signal %s received, shutting down", signum)
        stop["flag"] = True

    signal.signal(signal.SIGTERM, _sigterm)
    signal.signal(signal.SIGINT, _sigterm)

    # 1) Стартовый resync: подобрать уже существующие CR.
    try:
        for wa in list_webapps(dyn):
            reconcile(wa, apps_api, core_api, dyn)
    except ApiException as exc:
        log.error("initial list failed: %s", exc)

    last_resync = time.monotonic()

    # 2) Watch + resync.
    w = watch.Watch()
    while not stop["flag"]:
        try:
            stream = w.stream(
                dyn.resources.get(api_version=f"{GROUP}/{VERSION}", kind=KIND).get,
                namespace=NAMESPACE,
                timeout_seconds=RESYNC_PERIOD + 5,
            )
            for event in stream:
                if stop["flag"]:
                    break
                obj = event["object"]
                obj = obj.to_dict() if hasattr(obj, "to_dict") else obj
                kind = event["type"]
                log.debug("event %s %s/%s", kind, NAMESPACE, webapp_name(obj))
                if kind in ("ADDED", "MODIFIED"):
                    reconcile(obj, apps_api, core_api, dyn)
                elif kind == "DELETED":
                    log.info(
                        "webapp %s/%s deleted, child resources will be GC'd",
                        NAMESPACE,
                        webapp_name(obj),
                    )
                # Периодический resync, даже если watch «молчит» — нужен,
                # чтобы подтянуть status.availableReplicas.
                if time.monotonic() - last_resync > RESYNC_PERIOD:
                    for wa in list_webapps(dyn):
                        reconcile(wa, apps_api, core_api, dyn)
                    last_resync = time.monotonic()
        except ApiException as exc:
            log.error("watch error: %s, retrying in 3s", exc)
            time.sleep(3)
        except Exception as exc:  # noqa: BLE001
            log.exception("unexpected error: %s, retrying in 3s", exc)
            time.sleep(3)
        finally:
            try:
                w.stop()
            except Exception:  # noqa: BLE001
                pass

    log.info("webapp-operator stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
