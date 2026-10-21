"""Preserve workflow bytes, job graph and matrix while changing runner selection."""
import re
import yaml

LABELS={'ubuntu-latest':'eagle-linux-ubuntu24','ubuntu-24.04':'eagle-linux-ubuntu24',
        'ubuntu-22.04':'eagle-linux-ubuntu22','blacksmith-4vcpu-ubuntu-2404':'eagle-linux-ubuntu24'}

def route(source):
    root=yaml.compose(source)
    changes=[]
    def walk(node):
        if isinstance(node,yaml.MappingNode):
            for key,value in node.value:
                if key.value=='runs-on' and isinstance(value,yaml.ScalarNode):
                    original=value.value
                    if original in LABELS:
                        replacement=LABELS[original]
                    elif re.fullmatch(r'\$\{\{\s*matrix\.[a-zA-Z_.]+\s*\}\}',original):
                        expression=original[3:-2].strip()
                        replacement='${{ '+''.join(f"{expression} == '{a}' && '{b}' || " for a,b in LABELS.items())+expression+' }}'
                    elif original.startswith('${{') and 'ubuntu' in original:
                        replacement=original
                        for a,b in LABELS.items(): replacement=replacement.replace("'"+a+"'","'"+b+"'")
                    else:
                        continue
                    if replacement!=original:
                        # runs-on expressions contain no YAML colon; keep other bytes intact.
                        changes.append((value.start_mark.index,value.end_mark.index,replacement))
                else: walk(value)
        elif isinstance(node,yaml.SequenceNode):
            for value in node.value: walk(value)
    walk(root)
    result=source
    for start,end,replacement in sorted(changes,reverse=True): result=result[:start]+replacement+result[end:]
    # Round-trip proof: every non-routing value, including permissions/triggers and tests, is unchanged.
    before=yaml.safe_load(source);after=yaml.safe_load(result)
    def erase(value):
        if isinstance(value,dict): return {k:erase(v) for k,v in value.items() if k!='runs-on'}
        if isinstance(value,list): return [erase(v) for v in value]
        return value
    if erase(before)!=erase(after): raise ValueError('Non-routing workflow value changed')
    return result,len(changes)
