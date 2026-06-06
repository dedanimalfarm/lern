import kopf
import kubernetes.client as k8s
import kubernetes.config as config
from kubernetes.client.rest import ApiException

try:
    config.load_incluster_config()
except config.ConfigException:
    config.load_kube_config()

apps_api = k8s.AppsV1Api()
core_api = k8s.CoreV1Api()
custom_api = k8s.CustomObjectsApi()
from datetime import datetime, timezone
import os
if os.environ.get("USE_WEBHOOK") == "true":
    @kopf.on.mutate('lab.example.com', 'v1', 'webapps')
    def mutate_webapp(spec, patch, **kwargs):
        """
        Kopf Mutating Webhook: Ensure 'host' is set.
        Requires Kopf to be running as a webhook server in-cluster.
        """
        if 'host' not in spec:
            patch.spec['host'] = "localhost"

def _make_condition(type_str, status_str, reason, message):
    return {
        "type": type_str,
        "status": status_str,
        "reason": reason,
        "message": message,
        "lastTransitionTime": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    }



@kopf.on.create('lab.example.com', 'v1', 'webapps')
@kopf.on.update('lab.example.com', 'v1', 'webapps')
@kopf.on.resume('lab.example.com', 'v1', 'webapps')
def reconcile_webapp(spec, name, namespace, logger, patch, **kwargs):
    replicas = spec.get('replicas', 1)
    image = spec.get('image')
    host = spec.get('host', 'localhost')
    
    if not image:
        raise kopf.PermanentError("Image must be set")
    
    # 1. Deployment
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {
            'name': f"{name}-deploy",
            'namespace': namespace,
            'labels': {'app': name}
        },
        'spec': {
            'replicas': replicas,
            'selector': {'matchLabels': {'app': name}},
            'template': {
                'metadata': {'labels': {'app': name}},
                'spec': {
                    'containers': [{
                        'name': 'web',
                        'image': image,
                        'ports': [{'containerPort': 80}]
                    }]
                }
            }
        }
    }
    
    # 2. Service
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {
            'name': f"{name}-svc",
            'namespace': namespace,
            'labels': {'app': name}
        },
        'spec': {
            'selector': {'app': name},
            'ports': [{'port': 80, 'targetPort': 80}]
        }
    }

    # Make WebApp the owner of Deployment and Service
    kopf.adopt(deployment)
    kopf.adopt(service)

    # Apply Deployment
    try:
        apps_api.read_namespaced_deployment(name=f"{name}-deploy", namespace=namespace)
        apps_api.patch_namespaced_deployment(name=f"{name}-deploy", namespace=namespace, body=deployment)
        logger.info(f"Deployment {name}-deploy updated")
    except ApiException as e:
        if e.status == 404:
            apps_api.create_namespaced_deployment(namespace=namespace, body=deployment)
            logger.info(f"Deployment {name}-deploy created")
        else:
            raise

    # Apply Service
    try:
        core_api.read_namespaced_service(name=f"{name}-svc", namespace=namespace)
        core_api.patch_namespaced_service(name=f"{name}-svc", namespace=namespace, body=service)
        logger.info(f"Service {name}-svc updated")
    except ApiException as e:
        if e.status == 404:
            core_api.create_namespaced_service(namespace=namespace, body=service)
            logger.info(f"Service {name}-svc created")
        else:
            raise
            
    # Set status via CustomObjectsApi
    try:
        dep_status = apps_api.read_namespaced_deployment_status(name=f"{name}-deploy", namespace=namespace)
        avail = dep_status.status.available_replicas or 0
    except ApiException:
        avail = 0

    conds = [_make_condition("Ready", "True", "Reconciled", "Deployment and Service configured")]

    custom_api.patch_namespaced_custom_object_status(
        group="lab.example.com",
        version="v1",
        namespace=namespace,
        plural="webapps",
        name=name,
        body={"status": {"availableReplicas": avail, "conditions": conds}}
    )

@kopf.timer('lab.example.com', 'v1', 'webapps', interval=10.0, idle=10.0)
def update_status(spec, name, namespace, logger, **kwargs):
    """Periodically sync actual availableReplicas to status without spec changes."""
    try:
        dep = apps_api.read_namespaced_deployment_status(name=f"{name}-deploy", namespace=namespace)
        avail = dep.status.available_replicas or 0
    except ApiException:
        avail = 0

    conds = [_make_condition("Ready", "True", "Synced", "Status synced with Deployment")]
    try:
        custom_api.patch_namespaced_custom_object_status(
            group="lab.example.com",
            version="v1",
            namespace=namespace,
            plural="webapps",
            name=name,
            body={"status": {"availableReplicas": avail, "conditions": conds}}
        )
    except ApiException:
        pass
