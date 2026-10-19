#!/usr/bin/env python3
"""Periodic public device check-in and bounded incoming SSH lease renewal."""
import argparse
import signal
import time
from company_sync import SyncError, atomic, lock
from device_trust import check_all
from setup_profiles import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    args = parser.parse_args()
    if not args.watch: check_all(); return
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    try:
        with lock(ROOT / 'device-agent.lock', nonblocking=True):
            while running:
                check_all()
                atomic(ROOT / 'device-agent-status.json', {'heartbeat': time.time()})
                for _ in range(120):
                    if not running: break
                    time.sleep(1)
    except SyncError:
        return  # An existing agent already owns the lock.


if __name__ == '__main__': main()
