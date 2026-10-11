#!/usr/bin/env python3
"""Restore explicitly mapped credentials through a temporary vault container."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).resolve().parents[1] / "credential-container/credential_recovery.py"), run_name="__main__")
