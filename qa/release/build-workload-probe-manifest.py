#!/usr/bin/env python3
"""Emit a secret-free, constrained AKS QA identity probe manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def manifest(client_id, job_name):
    if not re.fullmatch(r'[0-9a-f-]{36}', client_id) or not re.fullmatch(r'openbenches-kv-[a-z0-9-]{1,40}', job_name):
        raise ValueError('Invalid QA identity or job name')
    code = (ROOT / 'credential-broker/core.py').read_text()
    probe = (ROOT / 'qa/release/probe-workload-kv.py').read_text()
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    namespace = 'openbenches-qa'
    annotations = {'openbenches/source-commit': commit, 'openbenches/core-sha256': hashlib.sha256(code.encode()).hexdigest()}
    cm_name = job_name + '-source'
    container = {'name': 'probe', 'image': 'python:3.13-slim', 'imagePullPolicy': 'Always',
        'command': ['/bin/sh', '-ec', 'pip install --no-cache-dir --disable-pip-version-check --target /tmp/site-packages azure-identity==1.26.0 azure-keyvault-secrets==4.11.3 >/tmp/pip.log 2>&1; PYTHONPATH=/tmp/site-packages:/source python /source/probe.py'],
        'securityContext': {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True,
                            'runAsNonRoot': True, 'runAsUser': 10001, 'capabilities': {'drop': ['ALL']}},
        'resources': {'requests': {'cpu': '100m', 'memory': '128Mi'}, 'limits': {'cpu': '1', 'memory': '512Mi'}},
        'volumeMounts': [{'name': 'source', 'mountPath': '/source', 'readOnly': True}, {'name': 'scratch', 'mountPath': '/tmp'}]}
    return {'apiVersion': 'v1', 'kind': 'List', 'items': [
        {'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': namespace, 'labels': {'app.kubernetes.io/part-of': 'openbenches', 'environment': 'qa'}}},
        {'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'credential-broker', 'namespace': namespace,
            'annotations': {'azure.workload.identity/client-id': client_id}}},
        {'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': cm_name, 'namespace': namespace, 'annotations': annotations},
         'data': {'core.py': code, 'probe.py': probe}},
        {'apiVersion': 'batch/v1', 'kind': 'Job', 'metadata': {'name': job_name, 'namespace': namespace, 'annotations': annotations},
         'spec': {'backoffLimit': 0, 'activeDeadlineSeconds': 600, 'ttlSecondsAfterFinished': 3600,
          'template': {'metadata': {'labels': {'azure.workload.identity/use': 'true', 'app.kubernetes.io/name': 'openbenches-kv-probe'}},
           'spec': {'serviceAccountName': 'credential-broker', 'restartPolicy': 'Never',
                    'securityContext': {'seccompProfile': {'type': 'RuntimeDefault'}}, 'containers': [container],
                    'volumes': [{'name': 'source', 'configMap': {'name': cm_name}}, {'name': 'scratch', 'emptyDir': {}}]}}}}]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-id', required=True)
    parser.add_argument('--job-name', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(manifest(args.client_id, args.job_name), indent=2) + '\n')
