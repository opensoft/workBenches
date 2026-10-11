"""Cancellation-aware setup prompts. Never use these for passwords."""
import signal
import sys


def prompt(text):
    try:
        value = input(text).strip()
    except EOFError:
        raise SystemExit(130) from None
    if value.lower() == "q":
        raise SystemExit(130)
    return value


def cancellation_signals():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(130))


def propagate_cancel(status):
    if status in (130, 143, -signal.SIGINT, -signal.SIGTERM):
        raise SystemExit(130 if status in (130, -signal.SIGINT) else 143)
