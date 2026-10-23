#!/usr/bin/env python3
"""Real AKS workload-identity KV infrastructure check, fictional payload only.

Not an AI-provider release attestation. Broker identity must access only this
fixture and must be denied access to the two QA user OAuth secrets.
"""
import json
import os
import sys
import uuid
from azure.core.exceptions import HttpResponseError
from core import AzureVault


def main():
    vault = AzureVault(os.environ['AZURE_CLIENT_ID'], 'workload')
    profile = {'vaultUrl': 'https://kv-openbenches-qa.vault.azure.net', 'secretName': 'qa-provider-fixture'}
    # This is intentionally invalid at every real provider.
    payload = {'accountId': 'openbenches-qa-fictional-account', 'access_token': 'fixture-not-a-provider-credential'}
    operation = 'qa-workload-check-' + str(uuid.uuid4())
    version = vault.put(profile, payload, operation)
    if vault.get(profile, version) != payload or vault.put(profile, payload, operation) != version:
        raise ValueError('QA fixture roundtrip/idempotency failed')
    for name in ('github-opensoft-test-user-1-oauth', 'github-opensoft-test-user-2-oauth'):
        try:
            vault.client(profile).get_secret(name)
        except HttpResponseError as error:
            if error.status_code != 403:
                raise ValueError('Expected authorization denial') from None
        else:
            raise ValueError('Broker identity must not read QA user sessions')
    print(json.dumps({'identityMode': 'workload', 'fixtureRoundtrip': 'passed',
                      'idempotency': 'passed', 'qaSessionAccessDenied': 'passed', 'status': 'passed'}))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # SDK/HTTP exceptions may contain payloads; never reflect their text.
        print(json.dumps({'status': 'failed', 'reason': 'workload_identity_kv_probe_failed'}))
        sys.exit(1)
