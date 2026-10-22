"""Preserve workflow bytes, job graph and matrix while changing runner selection."""
import re
import json
import yaml

LABELS={'ubuntu-latest':'eagle-linux-ubuntu24','ubuntu-24.04':'eagle-linux-ubuntu24',
        'ubuntu-22.04':'eagle-linux-ubuntu22','blacksmith-4vcpu-ubuntu-2404':'eagle-linux-ubuntu24',
        'windows-latest':'eagle-windows-2025','windows-2025':'eagle-windows-2025',
        'windows-2022':'eagle-windows-2022','windows-2019':'eagle-windows-2019',
        'macos-latest':'eagle-macos-latest','macos-15':'eagle-macos-15',
        'macos-14':'eagle-macos-14','macos-13':'eagle-macos-13'}

def route(source):
    root=yaml.compose(source)
    changes=set()
    # Scalar tokens exclude anchor/tag prefixes; aliases share the original span.
    scalar_spans={token.end_mark.index:(token.start_mark.index,token.end_mark.index)
                  for token in yaml.scan(source) if isinstance(token,yaml.ScalarToken)}
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
                        generated=re.fullmatch(r"fromJSON\('(?P<mapping>[^']+)'\)\[\((?P<expression>.*)\)\] \|\| \((?P=expression)\)",expression)
                        if generated:
                            previous=json.loads(generated['mapping'])
                            if all(LABELS.get(k)==v for k,v in previous.items()):
                                expression=generated['expression']
                        mapping=json.dumps(LABELS,separators=(',',':'))
                        replacement="${{ fromJSON('"+mapping+"')[("+expression+")] || ("+expression+") }}"
                    else:
                        continue
                    if replacement!=original:
                        # runs-on expressions contain no YAML colon; keep other bytes intact.
                        start,end=scalar_spans[value.end_mark.index]
                        changes.add((start,end,replacement))
    result=source
    for start,end,replacement in sorted(changes,reverse=True): result=result[:start]+replacement+result[end:]
    # Round-trip proof: every non-routing value, including permissions/triggers and tests, is unchanged.
    before=yaml.safe_load(source);after=yaml.safe_load(result)
    for document in (before,after):
        for job in document.get('jobs',{}).values():
            job.pop('runs-on',None)
    if before!=after: raise ValueError('Non-routing workflow value changed')
    return result,len(changes)
