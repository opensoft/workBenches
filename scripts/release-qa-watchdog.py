#!/usr/bin/env python3
"""Cancel this validation run if protected QA work cannot get a runner in time."""
import json
import os
import re
import time
import urllib.request


def stalled(jobs):
    qa = [job for job in jobs if job.get('name', '').startswith('Protected QA (')]
    if not qa: return 'waiting'
    if all(job['status'] == 'completed' for job in qa): return 'finished'
    return 'active' if any(job['status'] == 'in_progress' for job in qa) else 'waiting'


def main():
    repository, run_id = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_RUN_ID']
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository) or not run_id.isdigit(): raise SystemExit(1)
    token = os.environ['GH_TOKEN']
    def api(path, method='GET'):
        request = urllib.request.Request('https://api.github.com/repos/' + repository + '/actions/runs/' + run_id + path,
            method=method, headers={'Authorization':'Bearer ' + token, 'Accept':'application/vnd.github+json'})
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response) if method == 'GET' else None
    idle = time.monotonic()
    while True:
        value = stalled(api('/jobs?per_page=100')['jobs'])
        if value == 'finished': return
        if value == 'waiting':
            if time.monotonic() - idle > 600:
                print('Protected QA runner queue did not progress within ten minutes. Cancelling; release remains blocked.')
                api('/cancel', 'POST'); return
        else: idle = time.monotonic()
        time.sleep(15)


if __name__ == '__main__': main()
