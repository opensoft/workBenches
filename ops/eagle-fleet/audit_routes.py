"""Report platform and immutable reusable-workflow dependencies before activation."""
import argparse,json,re
import yaml
from pathlib import Path

def audit(workflows):
    result=[]
    for workflow in workflows:
        source=workflow.get('source')
        if not source: continue
        document=yaml.safe_load(source) or {}
        pins=[]
        for job in document.get('jobs',{}).values():
            reference=job.get('uses','')
            match=re.fullmatch(r'([\w.-]+/[\w.-]+/\.github/workflows/[^\s@]+)@([0-9a-f]{40})',reference)
            if match: pins.append(match.groups())
        flags=[]
        for name,pattern in [('native-platform',r'windows-(?:latest|\d+)|macos-\d+|macos-latest|xcode-\d+'),
                             ('arm-platform',r'(?:ubuntu|windows)-\S*(?:arm|aarch64)'),
                             ('kvm',r'/dev/kvm|KERNEL=="kvm"'),('host-swap',r'\bswapon\b|\bmkswap\b'),
                             ('host-sysctl',r'\bsysctl\b'),('cloud-cli',r'\baz\s|shell:\s*pwsh'),
                             ('blacksmith-actions',r'uses:\s*useblacksmith/')]:
            if re.search(pattern,source): flags.append(name)
        result.append(dict(repository=workflow['repository'],path=workflow['path'],flags=flags,
                           pinned_reusable_workflows=[dict(workflow=path,commit=commit) for path,commit in pins]))
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('inventory',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();records=audit(json.loads(args.inventory.read_text()));args.output.write_text(json.dumps(records,indent=2))
    print(json.dumps(dict(workflow_definitions=len(records),pinned_reusable_calls=sum(len(r['pinned_reusable_workflows']) for r in records),
                         flagged_definitions=sum(bool(r['flags']) for r in records))))
