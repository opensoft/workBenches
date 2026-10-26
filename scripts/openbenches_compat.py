"""Resolve openBenches environment aliases and state roots."""
import argparse
import os
from pathlib import Path
import re
import sys


class EnvironmentConflict(ValueError):
    pass


def environment_names(suffix):
    if not isinstance(suffix, str) or not re.fullmatch(r'[A-Z][A-Z0-9_]*', suffix):
        raise ValueError('Environment suffix must be an uppercase variable-name suffix.')
    return tuple(prefix + suffix for prefix in ('OPENBENCHES_', 'WORKBENCHES_', 'WB_'))


def resolve_env(suffix, default='', *, sensitive=False, environ=None):
    environment = os.environ if environ is None else environ
    selected_name = None
    selected_value = None
    for name in environment_names(suffix):
        if name not in environment:
            continue
        value = environment[name]
        if selected_name is None:
            selected_name, selected_value = name, value
        elif sensitive and value != selected_value:
            raise EnvironmentConflict(
                f'openBenches environment conflict: {selected_name} and {name} differ. '
                'Set configured aliases to one identical value or unset the conflicting alias, then retry.')
    return default if selected_name is None else selected_value


def state_root(kind, base=None, *, environ=None):
    locations = {
        'config': ('XDG_CONFIG_HOME', '.config'),
        'cache': ('XDG_CACHE_HOME', '.cache'),
        'data': ('XDG_DATA_HOME', '.local/share'),
    }
    if kind not in locations:
        raise ValueError('State root kind must be config, cache, or data.')
    environment = os.environ if environ is None else environ
    variable, default = locations[kind]
    if base is None:
        base = environment.get(variable) or Path.home() / default
    root = Path(base)
    canonical = root / 'openbenches'
    return canonical if canonical.is_dir() else root / 'workbenches'


def config_root(config_home=None, *, environ=None):
    return state_root('config', config_home, environ=environ)


def cache_root(cache_home=None, *, environ=None):
    return state_root('cache', cache_home, environ=environ)


def data_root(data_home=None, *, environ=None):
    return state_root('data', data_home, environ=environ)


def main(argv=None):
    capabilities = ('openbenches-config-root-v1',)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    capability = commands.add_parser('capability')
    capability.add_argument('name', choices=capabilities)
    commands.add_parser('capabilities')
    for kind in ('config', 'cache', 'data'):
        command = commands.add_parser(kind + '-root')
        command.add_argument('base', nargs='?', type=Path)
    args = parser.parse_args(argv)
    if args.command == 'capability':
        print(args.name)
        return 0
    if args.command == 'capabilities':
        print('\n'.join(capabilities))
        return 0
    kind = args.command.removesuffix('-root')
    print(state_root(kind, args.base))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (EnvironmentConflict, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
