"""Preserve workflow bytes, job graph and matrix while changing runner selection."""
import re
import json
import yaml

LABELS={'ubuntu-latest':'eagle-linux-ubuntu24','ubuntu-24.04':'eagle-linux-ubuntu24',
        'ubuntu-22.04':'eagle-linux-ubuntu22','blacksmith-4vcpu-ubuntu-2404':'eagle-linux-ubuntu24'}

def route(source):
    root=yaml.compose(source)
    changes=[]
    jobs=next((value for key,value in root.value if key.value=='jobs'),None) if isinstance(root,yaml.MappingNode) else None
    if isinstance(jobs,yaml.MappingNode):
        for _,job in jobs.value:
            if not isinstance(job,yaml.MappingNode): continue
            for key,value in job.value:
                if key.value=='runs-on' and isinstance(value,yaml.ScalarNode):
                    original=value.value
                    if original in LABELS:
                        replacement=LABELS[original]
                    elif original.startswith('${{') and original.endswith('}}') and ('matrix.' in original or 'ubuntu' in original):
                        expression=original[3:-2].strip()
                        mapping=json.dumps(LABELS,separators=(',',':'))
                        replacement="${{ fromJSON('"+mapping+"')[("+expression+")] || ("+expression+") }}"
                    else:
                        continue
                    if replacement!=original:
                        # runs-on expressions contain no YAML colon; keep other bytes intact.
                        changes.append((value.start_mark.index,value.end_mark.index,replacement))
    result=source
    for start,end,replacement in sorted(changes,reverse=True): result=result[:start]+replacement+result[end:]
    # Round-trip proof: every non-routing value, including permissions/triggers and tests, is unchanged.
    before=yaml.safe_load(source);after=yaml.safe_load(result)
    for document in (before,after):
        for job in document.get('jobs',{}).values():
            job.pop('runs-on',None)
    if before!=after: raise ValueError('Non-routing workflow value changed')
    return result,len(changes)
