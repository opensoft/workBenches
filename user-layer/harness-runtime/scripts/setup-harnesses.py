#!/usr/bin/env python3
"""Install, update, inspect or remove one source-qualified CLI harness."""
import argparse
from pathlib import Path
import sys
import signal
import subprocess

from setup_harnesses import HarnessError, Installer, Runner, registry


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(130))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'update', 'uninstall', 'status', 'list'))
    parser.add_argument('component', nargs='?')
    parser.add_argument('--registry', type=Path)
    parser.add_argument('--home', type=Path)
    parser.add_argument('--local', action='store_true')
    parser.add_argument('--bench', action='append', default=[], help='Reviewed bench install/update target; repeat per selected bench')
    parser.add_argument('--selection', type=Path, help='Image-build list of desired harness IDs')
    args = parser.parse_args()
    rows = registry(args.registry) if args.registry else registry()
    if args.action == 'list':
        for key, row in rows.items():
            print(key + '\t' + row['kind'])
        return 0
    if args.selection:
        if args.action != 'install' or args.bench or args.component:
            parser.error('image selections require install without individual/bench targets')
        from setup_harness_targets import read_selection
        for key in sorted(read_selection(args.selection)):
            Installer(rows, home=args.home, runner=Runner(local=args.local)).install(key)
        return 0
    if not args.component:
        parser.error('component is required')
    from setup_harness_targets import prepare, apply
    prepared = prepare(args.bench) if args.action in ('install', 'update', 'uninstall') else None
    installer = Installer(rows, home=args.home, runner=Runner(local=args.local))
    workstation = not args.local and args.home is None
    if args.action == 'status':
        print(installer.workstation_status(args.component) if workstation else installer.status(args.component))
    elif args.action == 'uninstall':
        installer.uninstall(args.component)
    else:
        # An install retry for PATH alone need not redownload a valid payload.
        if not (args.action == 'install' and workstation and installer.workstation_status(args.component) == 'needs path'):
            installer.install(args.component)
    pending = apply(args.action, args.component, prepared) if prepared else []
    if args.action in ('install', 'update') and workstation and installer.workstation_status(args.component) == 'needs path':
        installer.report_path_setup(args.component)
        return 2
    if pending:
        return 2
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (HarnessError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print('Harness operation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
