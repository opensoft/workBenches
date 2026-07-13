#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-297b2389-33bf-48c8-8deb-0b92838431e4}"
WORKLOAD_RESOURCE_GROUP="${WORKLOAD_RESOURCE_GROUP:-rg-os-workload-nopcommerce-qa}"
AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-rg-os-sandbox-drtest-qa}"
AKS_NAME="${AKS_NAME:-aks-os-drtest-qa-01}"
LOCATION="${LOCATION:-westus}"

NAMESPACE="${NAMESPACE:-digiwrap-qa-davincisite-com}"
DEPLOYMENT="${DEPLOYMENT:-digiwrap-qa-davincisite-com-gps}"
INSTANCE_LABEL="${INSTANCE_LABEL:-digiwrap-qa-davincisite-com}"
PVC_NAME="${PVC_NAME:-nfs-digiwrap-qa-davincisite-com}"

MEDIA_STORAGE_ACCOUNT="${MEDIA_STORAGE_ACCOUNT:-stosnopmediaqa01}"
MEDIA_CONTAINER="${MEDIA_CONTAINER:-digiwrap-media}"
APP_SECRET_NAME="${APP_SECRET_NAME:-digiwrap-media-blob}"
UPLOAD_SECRET_NAME="${UPLOAD_SECRET_NAME:-digiwrap-media-upload}"
UPLOAD_JOB_NAME="${UPLOAD_JOB_NAME:-digiwrap-media-seed}"
UPLOAD_IMAGE="${UPLOAD_IMAGE:-mcr.microsoft.com/azure-cli:latest}"

APPLY_NARROW_WWWROOT="${APPLY_NARROW_WWWROOT:-true}"
GET_AKS_CREDENTIALS="${GET_AKS_CREDENTIALS:-true}"
AZURE_BLOB_ENDPOINT="https://${MEDIA_STORAGE_ACCOUNT}.blob.core.windows.net"

if [ -n "${AZ_CMD:-}" ]; then
  read -r -a AZ <<< "$AZ_CMD"
else
  AZ=(az)
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

require_tool() {
  command -v "$1" >/dev/null || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

ensure_storage() {
  log "Selecting subscription ${SUBSCRIPTION_ID}"
  "${AZ[@]}" account set --subscription "$SUBSCRIPTION_ID"

  if ! "${AZ[@]}" storage account show \
    --resource-group "$WORKLOAD_RESOURCE_GROUP" \
    --name "$MEDIA_STORAGE_ACCOUNT" >/dev/null 2>&1; then
    log "Creating media storage account ${MEDIA_STORAGE_ACCOUNT}"
    "${AZ[@]}" storage account create \
      --resource-group "$WORKLOAD_RESOURCE_GROUP" \
      --name "$MEDIA_STORAGE_ACCOUNT" \
      --location "$LOCATION" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --https-only true \
      --min-tls-version TLS1_2 \
      --allow-blob-public-access true \
      --tags workload=nopcommerce environment=qa purpose=media pilot=digiwrap \
      --output none
  else
    log "Media storage account ${MEDIA_STORAGE_ACCOUNT} already exists"
  fi

  "${AZ[@]}" storage account update \
    --resource-group "$WORKLOAD_RESOURCE_GROUP" \
    --name "$MEDIA_STORAGE_ACCOUNT" \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access true \
    --output none

  MEDIA_STORAGE_KEY=$("${AZ[@]}" storage account keys list \
    --resource-group "$WORKLOAD_RESOURCE_GROUP" \
    --name "$MEDIA_STORAGE_ACCOUNT" \
    --query "[0].value" \
    --output tsv)

  MEDIA_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${MEDIA_STORAGE_ACCOUNT};AccountKey=${MEDIA_STORAGE_KEY};EndpointSuffix=core.windows.net"

  log "Ensuring media container ${MEDIA_CONTAINER} with blob public access"
  "${AZ[@]}" storage container create \
    --account-name "$MEDIA_STORAGE_ACCOUNT" \
    --account-key "$MEDIA_STORAGE_KEY" \
    --name "$MEDIA_CONTAINER" \
    --public-access blob \
    --output none
}

ensure_cluster_context() {
  if [ "$GET_AKS_CREDENTIALS" = "true" ]; then
    log "Loading AKS credentials for ${AKS_NAME}"
    "${AZ[@]}" aks get-credentials \
      --resource-group "$AKS_RESOURCE_GROUP" \
      --name "$AKS_NAME" \
      --overwrite-existing \
      --output none
  fi
}

create_secrets() {
  log "Creating app-facing AzureBlobConfig secret ${APP_SECRET_NAME}"
  kubectl -n "$NAMESPACE" create secret generic "$APP_SECRET_NAME" \
    --from-literal=AzureBlobConfig__ConnectionString="$MEDIA_CONNECTION_STRING" \
    --from-literal=AzureBlobConfig__ContainerName="$MEDIA_CONTAINER" \
    --from-literal=AzureBlobConfig__EndPoint="$AZURE_BLOB_ENDPOINT" \
    --from-literal=AzureBlobConfig__AppendContainerName="true" \
    --dry-run=client -o yaml | kubectl replace -f - 2>/dev/null || \
  kubectl -n "$NAMESPACE" create secret generic "$APP_SECRET_NAME" \
    --from-literal=AzureBlobConfig__ConnectionString="$MEDIA_CONNECTION_STRING" \
    --from-literal=AzureBlobConfig__ContainerName="$MEDIA_CONTAINER" \
    --from-literal=AzureBlobConfig__EndPoint="$AZURE_BLOB_ENDPOINT" \
    --from-literal=AzureBlobConfig__AppendContainerName="true"

  log "Creating temporary upload secret ${UPLOAD_SECRET_NAME}"
  kubectl -n "$NAMESPACE" create secret generic "$UPLOAD_SECRET_NAME" \
    --from-literal=AZURE_STORAGE_ACCOUNT="$MEDIA_STORAGE_ACCOUNT" \
    --from-literal=AZURE_STORAGE_KEY="$MEDIA_STORAGE_KEY" \
    --from-literal=AZURE_STORAGE_CONTAINER="$MEDIA_CONTAINER" \
    --dry-run=client -o yaml | kubectl apply -f -
}

run_seed_job() {
  log "Starting in-cluster media seed job ${UPLOAD_JOB_NAME}"
  kubectl -n "$NAMESPACE" delete job "$UPLOAD_JOB_NAME" --ignore-not-found --wait=true >/dev/null

  cat <<YAML | kubectl -n "$NAMESPACE" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${UPLOAD_JOB_NAME}
  labels:
    app.kubernetes.io/name: nopcommerce-media-seed
    app.kubernetes.io/instance: ${INSTANCE_LABEL}
spec:
  backoffLimit: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nopcommerce-media-seed
        app.kubernetes.io/instance: ${INSTANCE_LABEL}
    spec:
      restartPolicy: Never
      containers:
        - name: azure-cli
          image: ${UPLOAD_IMAGE}
          imagePullPolicy: IfNotPresent
          envFrom:
            - secretRef:
                name: ${UPLOAD_SECRET_NAME}
          command:
            - bash
            - -lc
            - |
              set -euo pipefail
              SRC=/mnt/site/wwwroot
              echo "source sizes"
              du -sh "\$SRC/images/thumbs" "\$SRC/images/uploaded" "\$SRC/files" 2>/dev/null || true
              echo "source counts"
              find "\$SRC/images/thumbs" -type f | wc -l
              find "\$SRC/images/uploaded" -type f | wc -l
              find "\$SRC/files" -type f | wc -l

              upload_pattern() {
                local pattern="\$1"
                local content_type="\$2"
                local count
                count=\$(find "\$SRC/images/thumbs" -maxdepth 1 -type f -name "\$pattern" | wc -l)
                if [ "\$count" -gt 0 ]; then
                  echo "uploading \$count thumb files matching \$pattern as \$content_type"
                  az storage blob upload-batch \\
                    --account-name "\$AZURE_STORAGE_ACCOUNT" \\
                    --account-key "\$AZURE_STORAGE_KEY" \\
                    --destination "\$AZURE_STORAGE_CONTAINER" \\
                    --source "\$SRC/images/thumbs" \\
                    --pattern "\$pattern" \\
                    --overwrite true \\
                    --content-type "\$content_type" \\
                    --content-cache-control "public,max-age=31536000" \\
                    --only-show-errors
                fi
              }

              upload_pattern "*.png" "image/png"
              upload_pattern "*.jpg" "image/jpeg"
              upload_pattern "*.jpeg" "image/jpeg"
              upload_pattern "*.gif" "image/gif"
              upload_pattern "*.webp" "image/webp"
              upload_pattern "*.svg" "image/svg+xml"

              echo "uploading uploaded media under images/uploaded"
              az storage blob upload-batch \\
                --account-name "\$AZURE_STORAGE_ACCOUNT" \\
                --account-key "\$AZURE_STORAGE_KEY" \\
                --destination "\$AZURE_STORAGE_CONTAINER" \\
                --destination-path images/uploaded \\
                --source "\$SRC/images/uploaded" \\
                --overwrite true \\
                --content-cache-control "public,max-age=31536000" \\
                --only-show-errors || true

              echo "uploading files under files"
              az storage blob upload-batch \\
                --account-name "\$AZURE_STORAGE_ACCOUNT" \\
                --account-key "\$AZURE_STORAGE_KEY" \\
                --destination "\$AZURE_STORAGE_CONTAINER" \\
                --destination-path files \\
                --source "\$SRC/files" \\
                --overwrite true \\
                --only-show-errors || true

              echo "blob count"
              az storage blob list \\
                --account-name "\$AZURE_STORAGE_ACCOUNT" \\
                --account-key "\$AZURE_STORAGE_KEY" \\
                --container-name "\$AZURE_STORAGE_CONTAINER" \\
                --query "length([])" -o tsv
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
          volumeMounts:
            - name: sitefiles
              mountPath: /mnt/site
      volumes:
        - name: sitefiles
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
YAML

  kubectl -n "$NAMESPACE" wait --for=condition=complete "job/${UPLOAD_JOB_NAME}" --timeout=15m
  kubectl -n "$NAMESPACE" logs "job/${UPLOAD_JOB_NAME}"
}

patch_blob_env() {
  log "Patching ${DEPLOYMENT} with AzureBlobConfig env vars"
  kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT" --type=strategic -p "$(cat <<JSON
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "nopcommerce",
            "env": [
              {
                "name": "AzureBlobConfig__ConnectionString",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "${APP_SECRET_NAME}",
                    "key": "AzureBlobConfig__ConnectionString"
                  }
                }
              },
              {
                "name": "AzureBlobConfig__ContainerName",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "${APP_SECRET_NAME}",
                    "key": "AzureBlobConfig__ContainerName"
                  }
                }
              },
              {
                "name": "AzureBlobConfig__EndPoint",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "${APP_SECRET_NAME}",
                    "key": "AzureBlobConfig__EndPoint"
                  }
                }
              },
              {
                "name": "AzureBlobConfig__AppendContainerName",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "${APP_SECRET_NAME}",
                    "key": "AzureBlobConfig__AppendContainerName"
                  }
                }
              },
              {
                "name": "AzureBlobConfig__StoreDataProtectionKeys",
                "value": "false"
              }
            ]
          }
        ]
      }
    }
  }
}
JSON
)"
  kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout=5m
}

patch_narrow_wwwroot_mounts() {
  if [ "$APPLY_NARROW_WWWROOT" != "true" ]; then
    log "Skipping narrow wwwroot mount patch"
    return
  fi

  log "Ensuring writable wwwroot subdirectories exist on the PVC"
  local pod
  pod=$(kubectl -n "$NAMESPACE" get pods \
    -l "app.kubernetes.io/instance=${INSTANCE_LABEL}" \
    --field-selector=status.phase=Running \
    -o jsonpath="{.items[0].metadata.name}")
  kubectl -n "$NAMESPACE" exec "$pod" -- sh -lc \
    "mkdir -p /app/wwwroot/files /app/wwwroot/sitemaps /app/wwwroot/bundles"

  log "Replacing broad /app/wwwroot NFS mount with targeted writable mounts"
  kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT" --type=json -p "$(cat <<JSON
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {"name": "sitefiles", "mountPath": "/app/App_Data", "subPath": "App_Data"},
      {"name": "sitefiles", "mountPath": "/app/Plugins", "subPath": "Plugins"},
      {"name": "sitefiles", "mountPath": "/app/Themes", "subPath": "Themes"},
      {"name": "sitefiles", "mountPath": "/app/wwwroot/files", "subPath": "wwwroot/files"},
      {"name": "sitefiles", "mountPath": "/app/wwwroot/sitemaps", "subPath": "wwwroot/sitemaps"},
      {"name": "wwwroot-bundles", "mountPath": "/app/wwwroot/bundles"}
    ]
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "sitefiles",
        "persistentVolumeClaim": {
          "claimName": "${PVC_NAME}"
        }
      },
      {
        "name": "wwwroot-bundles",
        "emptyDir": {}
      }
    ]
  }
]
JSON
)"
  kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout=5m
}

cleanup_upload_secret() {
  log "Deleting temporary upload secret and completed job"
  kubectl -n "$NAMESPACE" delete secret "$UPLOAD_SECRET_NAME" --ignore-not-found >/dev/null
  kubectl -n "$NAMESPACE" delete job "$UPLOAD_JOB_NAME" --ignore-not-found --wait=true >/dev/null
}

smoke_test() {
  if [ -z "${SMOKE_URL:-}" ]; then
    log "No SMOKE_URL set; skipping HTTP smoke"
    return
  fi

  log "Running smoke test for ${SMOKE_URL}"
  local output
  output=$(curl -k -sS -L -o /tmp/nopcommerce-media-pilot.html \
    -w "http=%{http_code} time=%{time_total} size=%{size_download}" \
    "$SMOKE_URL")
  echo "$output"
  grep -o "${MEDIA_STORAGE_ACCOUNT}.blob.core.windows.net/${MEDIA_CONTAINER}" \
    /tmp/nopcommerce-media-pilot.html | wc -l | awk '{print "blob-url-count=" $1}'
}

main() {
  require_tool kubectl
  require_tool curl
  ensure_storage
  ensure_cluster_context
  create_secrets
  run_seed_job
  patch_blob_env
  patch_narrow_wwwroot_mounts
  cleanup_upload_secret
  smoke_test

  log "Pilot complete for ${NAMESPACE}/${DEPLOYMENT}"
}

main "$@"
