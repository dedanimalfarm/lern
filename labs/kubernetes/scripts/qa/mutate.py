#!/usr/bin/env python3
"""Матрица мутаций для broken-сценариев.

Берёт эталонный манифест и портит его одной типовой ошибкой из каталога, чтобы
масштабировать производство broken-сценариев и не придумывать поломки руками.
Уровни: 1 — опечатки (ловятся apply/describe), 2 — логика (ресурс создаётся, но
ведёт себя не так), 3 — поведение (падения, рестарты, OOM).

Использование:
  scripts/qa/mutate.py --list
  scripts/qa/mutate.py manifests/deploy.yaml image-tag > broken/scenario-05/deploy.yaml
  scripts/qa/mutate.py manifests/deploy.yaml --random 2 -o broken/deploy.yaml --hint
"""
import argparse, copy, random, sys
import yaml

WORKLOADS = {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"}


def pod_spec(doc):
    kind = doc.get("kind")
    if kind == "Pod":
        return doc["spec"]
    if kind == "CronJob":
        return doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
    if kind in WORKLOADS:
        return doc["spec"]["template"]["spec"]
    return None


def first_container(doc):
    ps = pod_spec(doc)
    if not ps or not ps.get("containers"):
        return None
    return ps["containers"][0]


def m_image_tag(doc):
    c = first_container(doc)
    if not c:
        return False
    image = c["image"].rsplit("@", 1)[0]
    base = image.rsplit(":", 1)[0] if ":" in image.split("/")[-1] else image
    c["image"] = base + ":not-a-real-tag"
    return True


def m_selector_typo(doc):
    if doc.get("kind") not in ("Deployment", "StatefulSet", "DaemonSet"):
        return False
    labels = doc["spec"]["selector"]["matchLabels"]
    key = next(iter(labels))
    labels[key] = str(labels[key]) + "-typo"
    return True


def m_service_target_port(doc):
    if doc.get("kind") != "Service":
        return False
    port = doc["spec"]["ports"][0]
    target = port.get("targetPort", port["port"])
    if isinstance(target, int):
        port["targetPort"] = target + 1
    else:
        port["targetPort"] = str(target) + "-typo"
    return True


def m_probe_path(doc):
    c = first_container(doc)
    if not c:
        return False
    probe = c.get("readinessProbe") or c.get("livenessProbe")
    if not probe or "httpGet" not in probe:
        return False
    probe["httpGet"]["path"] = "/healthz-typo"
    return True


def m_namespace_typo(doc):
    meta = doc.setdefault("metadata", {})
    meta["namespace"] = str(meta.get("namespace", "lab")) + "-typo"
    return True


def m_requests_gt_limits(doc):
    c = first_container(doc)
    if not c:
        return False
    res = c.setdefault("resources", {})
    res.setdefault("limits", {})["cpu"] = "100m"
    res.setdefault("requests", {})["cpu"] = "500m"
    return True


def m_drop_resources(doc):
    c = first_container(doc)
    if not c or "resources" not in c:
        return False
    del c["resources"]
    return True


def m_pdb_too_strict(doc):
    if doc.get("kind") != "PodDisruptionBudget":
        return False
    doc["spec"].pop("maxUnavailable", None)
    doc["spec"]["minAvailable"] = "100%"
    return True


def m_replicas_zero(doc):
    if doc.get("kind") not in ("Deployment", "StatefulSet"):
        return False
    doc["spec"]["replicas"] = 0
    return True


def m_crash(doc):
    c = first_container(doc)
    if not c:
        return False
    c["command"] = ["sh", "-c", "echo 'config error: missing DB_URL' >&2; exit 1"]
    c.pop("args", None)
    return True


def m_oom(doc):
    c = first_container(doc)
    if not c:
        return False
    res = c.setdefault("resources", {})
    res.setdefault("limits", {})["memory"] = "8Mi"
    res.setdefault("requests", {})["memory"] = "8Mi"
    return True


def m_liveness_strict(doc):
    c = first_container(doc)
    if not c:
        return False
    c["livenessProbe"] = {
        "httpGet": {"path": "/definitely-missing", "port": c.get("ports", [{"containerPort": 80}])[0]["containerPort"]},
        "initialDelaySeconds": 2, "periodSeconds": 2, "failureThreshold": 1,
    }
    return True


CATALOG = {
    "image-tag":          (1, m_image_tag,           "ImagePullBackOff / ErrImagePull",  "describe pod -> Events: manifest unknown; get pod -o jsonpath='{.spec.containers[0].image}'"),
    "selector-typo":      (1, m_selector_typo,       "apply отклонён: selector does not match template labels", "сравнить spec.selector.matchLabels и spec.template.metadata.labels"),
    "service-target-port":(1, m_service_target_port, "Endpoints есть, curl -> connection refused", "get endpointslices; describe svc (TargetPort) против containerPort"),
    "probe-path":         (1, m_probe_path,          "Running, но READY 0/1; из Endpoints выпал", "describe pod | grep 'Readiness probe failed'"),
    "namespace-typo":     (1, m_namespace_typo,      "apply: namespaces \"...-typo\" not found", "get ns; сверить metadata.namespace"),
    "requests-gt-limits": (2, m_requests_gt_limits,  "apply отклонён: must be less than or equal to cpu limit", "describe: resources.requests против limits"),
    "drop-resources":     (2, m_drop_resources,      "под получает default из LimitRange или отказ квоты 'must specify limits'", "get pod -o jsonpath='{..resources}'; describe quota"),
    "pdb-too-strict":     (2, m_pdb_too_strict,      "drain зависает: Cannot evict pod as it would violate the pod's disruption budget", "get pdb (ALLOWED DISRUPTIONS 0)"),
    "replicas-zero":      (2, m_replicas_zero,       "сервис 'работает', подов нет; Endpoints пустые", "get deploy (READY 0/0); get endpoints"),
    "crash":              (3, m_crash,               "CrashLoopBackOff, RESTARTS растёт", "logs --previous; lastState.terminated.exitCode=1"),
    "oom":                (3, m_oom,                 "OOMKilled (exit 137), рестарты", "lastState.terminated.reason=OOMKilled; describe: limits.memory"),
    "liveness-strict":    (3, m_liveness_strict,     "под рестартует каждые несколько секунд, хотя приложение живо", "describe pod | grep 'Liveness probe failed'; сравнить path пробы с приложением"),
}


def apply_mutation(docs, name):
    tier, fn, symptom, diag = CATALOG[name]
    for doc in docs:
        if isinstance(doc, dict) and fn(doc):
            return doc.get("kind"), doc.get("metadata", {}).get("name"), tier, symptom, diag
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest", nargs="?")
    ap.add_argument("mutation", nargs="?")
    ap.add_argument("--list", action="store_true", help="показать каталог мутаций")
    ap.add_argument("--random", type=int, metavar="TIER", help="случайная мутация заданного уровня (1-3)")
    ap.add_argument("-o", "--output", help="куда писать (по умолчанию stdout)")
    ap.add_argument("--hint", action="store_true", help="напечатать симптом и диагностику в stderr")
    ap.add_argument("--seed", type=int)
    a = ap.parse_args()

    if a.list:
        for n, (tier, _, symptom, _) in sorted(CATALOG.items(), key=lambda kv: (kv[1][0], kv[0])):
            print(f"{tier}  {n:20s} {symptom}")
        return
    if not a.manifest or (not a.mutation and a.random is None):
        ap.error("нужны manifest и mutation (или --random TIER)")
    with open(a.manifest, encoding="utf-8") as f:
        docs = [d for d in yaml.safe_load_all(f) if d is not None]
    rnd = random.Random(a.seed)
    candidates = [a.mutation] if a.mutation else [n for n, v in CATALOG.items() if v[0] == a.random]
    rnd.shuffle(candidates)
    for name in candidates:
        if name not in CATALOG:
            sys.exit(f"неизвестная мутация: {name} (см. --list)")
        mutated = copy.deepcopy(docs)
        res = apply_mutation(mutated, name)
        if res:
            kind, obj, tier, symptom, diag = res
            out = yaml.safe_dump_all(mutated, sort_keys=False, allow_unicode=True)
            if a.output:
                with open(a.output, "w", encoding="utf-8") as f:
                    f.write(out)
            else:
                sys.stdout.write(out)
            if a.hint or a.output:
                print(f"мутация: {name} (уровень {tier}) -> {kind}/{obj}\nсимптом: {symptom}\nдиагностика: {diag}", file=sys.stderr)
            return
    sys.exit("ни одна из мутаций не применима к этому манифесту")


if __name__ == "__main__":
    main()
