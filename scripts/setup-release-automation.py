#!/usr/bin/env python3
"""Inspect or create dedicated release environments; never register a daily workstation."""
import argparse
import json
import re
import subprocess
from release_validation import load_manifest, selected


def api(path, method='GET', data=None, absent=False):
    args = ['gh','api',path]
    if method != 'GET': args += ['--method',method]
    if data is not None: args += ['--input','-']
    result = subprocess.run(args,input=json.dumps(data) if data is not None else None,text=True,capture_output=True,timeout=30)
    if result.returncode:
        if absent and 'HTTP 404' in result.stderr: return None
        raise ValueError('GitHub administration request failed; check repository/organization permissions.')
    return json.loads(result.stdout) if result.stdout.strip() else {}


def ensure_variable(base, name, value):
    if api(base + '/' + name, absent=True) is None:
        api(base, 'POST', {'name':name,'value':value})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inspect','configure'))
    parser.add_argument('--repository', default='opensoft/workBenches')
    parser.add_argument('--version', default='1.6.0')
    parser.add_argument('--reviewer', help='Optional final publication reviewer; never removes existing protections')
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+/[\w.-]+',args.repository): raise ValueError('Invalid repository')
    base = 'repos/' + args.repository
    if args.action == 'configure':
        if not api(base)['permissions'].get('admin'): raise ValueError('Repository administration permission required')
        for name in ('release-qa','release-publish'):
            path = base + '/environments/' + name
            current = api(path, absent=True)
            if current is not None:
                print(name + ': existing environment preserved; inspect its branch/reviewer policy.')
                continue
            data = {'deployment_branch_policy':{'protected_branches':False,'custom_branch_policies':True}}
            if name == 'release-publish' and args.reviewer:
                user = api('users/' + args.reviewer)
                data['reviewers'] = [{'type':'User','id':user['id']}]
            api(path, 'PUT', data)
            api(path + '/deployment-branch-policies', 'POST', {'name':'main','type':'branch'})
            print(name + ': created, main-only')
        ensure_variable(base + '/actions/variables','WB_RELEASE_QA_NIGHTLY','false')
        envbase = base + '/environments/release-qa/variables'
        ensure_variable(envbase,'WB_QA_CONFIGURED','false')
        ensure_variable(envbase,'WB_QA_CONFIG_PATH','/etc/workbenches/release-qa.json')
    runners = api(base + '/actions/runners?per_page=100')['runners']
    suites = selected(load_manifest(),args.version,'release')
    print(json.dumps({'repository':args.repository,'version':args.version,'registeredRunners':len(runners),
        'externalRequirements':[{ 'suite':name, 'labels':suite['labels'],
            'onlineMatches':[r['name'] for r in runners if r['status']=='online' and set(suite['labels']) <= {v['name'] for v in r['labels']}]}
            for name,suite in suites.items() if suite['kind']=='external']},indent=2))
    print('Protected org runner-group workflow restrictions, QA accounts, approved adapters and inventory-token provisioning are required before enabling live QA. No runners or cloud resources were created.')


if __name__ == '__main__':
    try: main()
    except (ValueError,OSError,KeyError,TypeError): raise SystemExit('Release environment setup blocked; check repository administration permissions and configuration.')
