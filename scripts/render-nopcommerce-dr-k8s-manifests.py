#!/usr/bin/env python3
"""Render/apply DR Kubernetes app manifests for a nopCommerce backup site.

This intentionally keeps the SQL connection string out of rendered manifest
files. When --connection-string-file and --apply are used, the Secret is applied
directly through kubectl from the local file.
"""

import argparse
import copy
import json
import os
import re
import subprocess
import sys
from pathlib import Path


CONNECTION_ENV_NAME = "ConnectionStrings__ConnectionString"


def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def dns_label(value):
    value = re.sub(r"[^a-z0-9-]+", "-", value.lower())
    value = re.sub(r"-+", "-", value).strip("-")
    return value[:63].strip("-") or "nopcommerce"


def clean_metadata(resource, namespace=None):
    resource = copy.deepcopy(resource)
    metadata = resource.setdefault("metadata", {})
    metadata.pop("uid", None)
    metadata.pop("resourceVersion", None)
    metadata.pop("generation", None)
    metadata.pop("creationTimestamp", None)
    metadata.pop("managedFields", None)
    annotations = metadata.get("annotations") or {}
    annotations = {
        key: value
        for key, value in annotations.items()
        if not key.startswith("kubectl.kubernetes.io/")
    }
    if annotations:
        metadata["annotations"] = annotations
    else:
        metadata.pop("annotations", None)
    if namespace:
        metadata["namespace"] = namespace
    resource.pop("status", None)
    return resource


def source_deployment(inventory):
    deployment = inventory.get("deployment")
    if not deployment:
        die("k8s-inventory.json does not contain a deployment")
    return deployment


def matching_service_name(inventory, deployment, default_name):
    pod_labels = deployment.get("spec", {}).get("template", {}).get("metadata", {}).get("labels", {})
    services = inventory.get("serviceList", {}).get("items", [])
    for service in services:
        selector = service.get("spec", {}).get("selector") or {}
        if selector and all(pod_labels.get(key) == value for key, value in selector.items()):
            return service.get("metadata", {}).get("name") or default_name
    return default_name


def first_container(deployment):
    containers = deployment.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if not containers:
        die("source deployment has no containers")
    return containers[0]


def build_namespace(namespace, site):
    return {
        "apiVersion": "v1",
        "kind": "Namespace",
        "metadata": {
            "name": namespace,
            "labels": {
                "opensoft.one/dr-site": site,
                "opensoft.one/managed-by": "nopcommerce-dr-restore",
            },
        },
    }


def build_pv_pvc(args, namespace):
    pv_name = args.pv_name or args.pvc_name
    pv = {
        "apiVersion": "v1",
        "kind": "PersistentVolume",
        "metadata": {
            "name": pv_name,
            "labels": {
                "opensoft.one/dr-site": args.site_name,
                "opensoft.one/managed-by": "nopcommerce-dr-restore",
            },
        },
        "spec": {
            "capacity": {"storage": args.storage_size},
            "accessModes": ["ReadWriteMany"],
            "persistentVolumeReclaimPolicy": "Retain",
            "mountOptions": args.nfs_mount_option,
            "nfs": {
                "server": args.nfs_server,
                "path": args.nfs_path,
            },
        },
    }
    pvc = {
        "apiVersion": "v1",
        "kind": "PersistentVolumeClaim",
        "metadata": {
            "name": args.pvc_name,
            "namespace": namespace,
            "labels": {
                "opensoft.one/dr-site": args.site_name,
                "opensoft.one/managed-by": "nopcommerce-dr-restore",
            },
        },
        "spec": {
            "accessModes": ["ReadWriteMany"],
            "resources": {"requests": {"storage": args.storage_size}},
            "volumeName": pv_name,
            "storageClassName": "",
        },
    }
    return [pv, pvc]


def patch_deployment(args, inventory, namespace, secret_name):
    deployment = clean_metadata(source_deployment(inventory), namespace)
    metadata = deployment.setdefault("metadata", {})
    metadata["name"] = args.deployment_name
    labels = metadata.setdefault("labels", {})
    labels["opensoft.one/dr-site"] = args.site_name
    labels["opensoft.one/managed-by"] = "nopcommerce-dr-restore"

    spec = deployment.setdefault("spec", {})
    if args.replicas is not None:
        spec["replicas"] = args.replicas
    template = spec.setdefault("template", {})
    template_meta = template.setdefault("metadata", {})
    template_labels = template_meta.setdefault("labels", {})
    template_labels["opensoft.one/dr-site"] = args.site_name
    template_labels["opensoft.one/managed-by"] = "nopcommerce-dr-restore"
    template_spec = template.setdefault("spec", {})

    for volume in template_spec.get("volumes", []):
        claim = volume.get("persistentVolumeClaim")
        if claim:
            claim["claimName"] = args.pvc_name

    container = first_container(deployment)
    container["image"] = args.image
    env = container.setdefault("env", [])
    env = [item for item in env if item.get("name") != CONNECTION_ENV_NAME]
    env.append(
        {
            "name": CONNECTION_ENV_NAME,
            "valueFrom": {
                "secretKeyRef": {
                    "name": secret_name,
                    "key": args.secret_key,
                }
            },
        }
    )
    container["env"] = env
    return deployment


def build_service(args, inventory, deployment, namespace):
    source_name = matching_service_name(inventory, source_deployment(inventory), args.service_name)
    services = inventory.get("serviceList", {}).get("items", [])
    source = next((svc for svc in services if svc.get("metadata", {}).get("name") == source_name), None)
    if source:
        service = clean_metadata(source, namespace)
        service["metadata"]["name"] = args.service_name
        service_spec = service.setdefault("spec", {})
        for field in ["clusterIP", "clusterIPs", "ipFamilies", "ipFamilyPolicy", "healthCheckNodePort"]:
            service_spec.pop(field, None)
    else:
        labels = deployment.get("spec", {}).get("template", {}).get("metadata", {}).get("labels", {})
        service = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": args.service_name, "namespace": namespace},
            "spec": {
                "type": "ClusterIP",
                "selector": labels,
                "ports": [{"name": "http", "port": 80, "targetPort": 80}],
            },
        }
    metadata = service.setdefault("metadata", {})
    labels = metadata.setdefault("labels", {})
    labels["opensoft.one/dr-site"] = args.site_name
    labels["opensoft.one/managed-by"] = "nopcommerce-dr-restore"
    return service


def build_ingress(args, namespace):
    tls_secret = args.tls_secret or f"{args.ingress_name}-tls"
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "Ingress",
        "metadata": {
            "name": args.ingress_name,
            "namespace": namespace,
            "labels": {
                "opensoft.one/dr-site": args.site_name,
                "opensoft.one/managed-by": "nopcommerce-dr-restore",
            },
            "annotations": {
                "cert-manager.io/cluster-issuer": args.cluster_issuer,
                "nginx.ingress.kubernetes.io/proxy-body-size": args.proxy_body_size,
            },
        },
        "spec": {
            "ingressClassName": args.ingress_class,
            "tls": [{"hosts": args.host, "secretName": tls_secret}],
            "rules": [
                {
                    "host": host,
                    "http": {
                        "paths": [
                            {
                                "path": "/",
                                "pathType": "Prefix",
                                "backend": {
                                    "service": {
                                        "name": args.service_name,
                                        "port": {"number": 80},
                                    }
                                },
                            }
                        ]
                    },
                }
                for host in args.host
            ],
        },
    }


def write_manifest(path, resources):
    payload = {"apiVersion": "v1", "kind": "List", "items": resources}
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def resource_json(resource):
    return json.dumps(resource, indent=2) + "\n"


def run_kubectl(args, stdin=None):
    subprocess.run(["kubectl", *args], input=stdin, text=True, check=True)


def apply_secret(args, namespace, secret_name):
    if args.existing_secret_name:
        return
    if not args.connection_string_file:
        die("internal error: no connection string source")
    source = Path(args.connection_string_file)
    if not source.is_file():
        die(f"connection string file not found: {source}")
    secret_value = source.read_text(encoding="utf-8").rstrip("\r\n")
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": secret_name,
            "namespace": namespace,
            "labels": {
                "opensoft.one/dr-site": args.site_name,
                "opensoft.one/managed-by": "nopcommerce-dr-restore",
            },
        },
        "type": "Opaque",
        "stringData": {args.secret_key: secret_value},
    }
    run_kubectl(["apply", "-f", "-"], stdin=resource_json(secret))


def parse_args():
    parser = argparse.ArgumentParser(
        description="Render/apply nopCommerce DR Kubernetes manifests using secretKeyRef."
    )
    parser.add_argument("--backup-site-dir", required=True, help="Directory containing manifest.json and k8s-inventory.json.")
    parser.add_argument("--output-dir", help="Directory for rendered non-secret manifests.")
    parser.add_argument("--namespace", help="Target namespace. Defaults to manifest.site.")
    parser.add_argument("--site-name", help="Logical site name. Defaults to manifest.site.")
    parser.add_argument("--image", help="Target container image. Defaults to manifest.app.image.")
    parser.add_argument("--replicas", type=int, default=1)
    parser.add_argument("--host", action="append", help="Target ingress host. Can be repeated. Defaults to manifest app hosts.")
    parser.add_argument("--deployment-name", help="Target Deployment name.")
    parser.add_argument("--service-name", help="Target Service name.")
    parser.add_argument("--ingress-name", help="Target Ingress name.")
    parser.add_argument("--ingress-class", default="nginx")
    parser.add_argument("--cluster-issuer", default="letsencrypt-prod")
    parser.add_argument("--proxy-body-size", default="100m")
    parser.add_argument("--tls-secret")
    parser.add_argument("--pvc-name", help="Target PVC name. Defaults to manifest.files.pvc or <site>-nfs.")
    parser.add_argument("--pv-name", help="Target PV name. Defaults to --pvc-name.")
    parser.add_argument("--nfs-server", help="Target NFS server. Required unless --skip-pv-pvc.")
    parser.add_argument("--nfs-path", help="Target NFS path. Required unless --skip-pv-pvc.")
    parser.add_argument("--storage-size", default="100Gi")
    parser.add_argument("--nfs-mount-option", action="append", default=["nconnect=4"])
    parser.add_argument("--skip-pv-pvc", action="store_true", help="Do not render PV/PVC resources.")
    parser.add_argument("--existing-secret-name", help="Use an already-restored Kubernetes Secret.")
    parser.add_argument("--connection-string-file", help="Apply/update the Kubernetes Secret from this local file when --apply is used.")
    parser.add_argument("--secret-name", help="Secret to reference/create. Defaults to <site>-app-secrets.")
    parser.add_argument("--secret-key", default=CONNECTION_ENV_NAME)
    parser.add_argument("--apply", action="store_true", help="Apply rendered manifests with kubectl. Secret is applied directly from file.")
    return parser.parse_args()


def main():
    args = parse_args()
    backup_dir = Path(args.backup_site_dir)
    manifest = load_json(backup_dir / "manifest.json")
    inventory = load_json(backup_dir / "k8s-inventory.json")

    args.site_name = args.site_name or manifest.get("site") or backup_dir.name
    args.namespace = args.namespace or args.site_name
    args.image = args.image or manifest.get("app", {}).get("image")
    if not args.image:
        die("image was not provided and manifest.app.image is empty")
    args.host = args.host or manifest.get("app", {}).get("hosts") or []
    if not args.host:
        die("at least one --host is required")
    args.deployment_name = args.deployment_name or source_deployment(inventory).get("metadata", {}).get("name") or f"{args.site_name}-gps"
    args.service_name = args.service_name or matching_service_name(inventory, source_deployment(inventory), f"{args.site_name}-gps")
    args.ingress_name = args.ingress_name or dns_label(args.host[0])
    args.pvc_name = args.pvc_name or manifest.get("files", {}).get("pvc") or f"{args.site_name}-nfs"
    secret_name = args.existing_secret_name or args.secret_name or f"{args.site_name}-app-secrets"

    if not args.existing_secret_name and not args.connection_string_file:
        die("provide --existing-secret-name or --connection-string-file")
    if args.connection_string_file and not args.apply and not args.existing_secret_name:
        print(
            "WARNING: --connection-string-file is only used with --apply; rendered manifests will reference "
            f"Secret/{secret_name} but will not contain the secret value.",
            file=sys.stderr,
        )
    if not args.skip_pv_pvc and (not args.nfs_server or not args.nfs_path):
        die("--nfs-server and --nfs-path are required unless --skip-pv-pvc is set")

    namespace = args.namespace
    deployment = patch_deployment(args, inventory, namespace, secret_name)
    resources = [build_namespace(namespace, args.site_name)]
    if not args.skip_pv_pvc:
        resources.extend(build_pv_pvc(args, namespace))
    resources.append(deployment)
    resources.append(build_service(args, inventory, deployment, namespace))
    resources.append(build_ingress(args, namespace))

    output_dir = Path(args.output_dir or Path("restore-manifests") / args.site_name)
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "k8s-restore.json"
    write_manifest(manifest_path, resources)

    print(f"Wrote non-secret Kubernetes restore manifests to {manifest_path}")
    print(f"Deployment uses secretKeyRef: Secret/{secret_name} key {args.secret_key}")

    if args.apply:
        run_kubectl(["apply", "-f", "-"], stdin=resource_json(resources[0]))
        apply_secret(args, namespace, secret_name)
        run_kubectl(["apply", "-f", str(manifest_path)])
        run_kubectl(["rollout", "restart", f"deployment/{args.deployment_name}", "-n", namespace])
        print(f"Applied restore manifests for {namespace}")


if __name__ == "__main__":
    main()
