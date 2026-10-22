"""Generate a reviewable plan from an inventory, without writing any repository."""
import argparse
import difflib
import json
from pathlib import Path
from routing import route

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('inventory',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    records=[]
    for workflow in json.loads(args.inventory.read_text()):
        source=workflow.get('source')
        if not source: continue
        after,count=route(source)
        if not count: continue
        records.append(dict(repository=workflow['repository'],path=workflow['path'],
                            source_blob=workflow['sha'],runner_changes=count,before=source,after=after,
                            diff=''.join(difflib.unified_diff(source.splitlines(True),after.splitlines(True),fromfile=workflow['path'],tofile=workflow['path']))))
    args.output.write_text(json.dumps(records,indent=2))
    print(json.dumps(dict(definitions=len(records),repositories=len({r['repository'] for r in records}),runner_selectors=sum(r['runner_changes'] for r in records))))

if __name__=='__main__': main()
