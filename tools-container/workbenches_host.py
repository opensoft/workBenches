"""Explicit native-host probes for Python helpers running in the Tools container.

The launcher starts a private, short-lived Bash broker. Arguments and input use
files, never shell evaluation. This channel does not handle interactive passwords.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def active():
    return bool(os.environ.get('WORKBENCHES_HOST_RPC'))


def run(argv, *, capture_output=False, text=False, timeout=30, env=None, input=None):
    if not active():
        return subprocess.run(argv, capture_output=capture_output, text=text,
                              timeout=timeout, env=env, input=input)
    root = Path(os.environ['WORKBENCHES_HOST_RPC'])
    if not (root / 'alive').is_file():
        raise OSError('The workstation command session is no longer available')
    with tempfile.TemporaryDirectory(prefix='request-', dir=root) as temporary:
        directory = Path(temporary)
        os.chmod(directory, 0o700)
        arguments = [os.fspath(arg) for arg in argv]
        environment = dict(env or {})
        # Container runtime paths must never replace the workstation's PATH.
        for key in ('PATH', 'PYTHONPATH', 'LD_LIBRARY_PATH'):
            environment.pop(key, None)
        fields = [str(Path.cwd()), str(timeout), str(len(arguments)), *arguments,
                  str(len(environment))]
        for key, value in environment.items():
            fields.extend((key, value))
        if any('\0' in value for value in fields):
            raise ValueError('NUL in workstation command arguments')
        (directory / 'request').write_bytes(('\0'.join(fields) + '\0').encode())
        (directory / 'timeout').write_text(str(int(timeout)) + '\n')
        (directory / 'input').write_bytes(input.encode() if isinstance(input, str) else input or b'')
        (directory / 'ready').touch()
        deadline = time.monotonic() + timeout + 5
        positions = {'stdout': 0, 'stderr': 0}
        try:
            while not (directory / 'exit').exists():
                if time.monotonic() > deadline or not (root / 'alive').is_file():
                    (directory / 'cancel').touch()
                    for _ in range(100):
                        if (directory / 'exit').exists() or not (root / 'alive').is_file():
                            break
                        time.sleep(0.025)
                    raise subprocess.TimeoutExpired(arguments, timeout)
                if not capture_output:
                    for name, stream in (('stdout', sys.stdout), ('stderr', sys.stderr)):
                        source = directory / name
                        if source.exists():
                            with source.open('rb') as output:
                                output.seek(positions[name]); data = output.read()
                            positions[name] += len(data)
                            stream.buffer.write(data); stream.flush()
                time.sleep(0.025)
        except BaseException:
            # Cancellation must reach a native dialog/command before its private
            # request directory is removed by TemporaryDirectory.
            (directory / 'cancel').touch()
            for _ in range(100):
                if (directory / 'exit').exists() or not (root / 'alive').is_file(): break
                time.sleep(.025)
            raise
        code = int((directory / 'exit').read_text())
        outputs = []
        for name, stream in (('stdout', sys.stdout), ('stderr', sys.stderr)):
            data = (directory / name).read_bytes()
            if not capture_output:
                stream.buffer.write(data[positions[name]:]); stream.flush()
            outputs.append(data.decode(errors='replace') if text else data)
        if code == 77 and (directory / 'sudo-required').exists():
            (root / 'sudo-required').touch()
            raise SystemExit(77)
        return subprocess.CompletedProcess(arguments, code,
                                           outputs[0] if capture_output else None,
                                           outputs[1] if capture_output else None)


def which(name):
    if not active():
        return shutil.which(name)
    result = run(['@which', name], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def resolve(path):
    if not active():
        return Path(path).resolve()
    result = run(['@resolve', os.fspath(path)], capture_output=True, text=True)
    if result.returncode:
        raise OSError('Cannot resolve workstation path: ' + os.fspath(path))
    return Path(result.stdout.strip())


def read_text(path):
    if not active():
        return Path(path).read_text()
    result = run(['@read', os.fspath(path)], capture_output=True, text=True)
    if result.returncode:
        raise OSError('Cannot read workstation metadata: ' + os.fspath(path))
    return result.stdout


def access(path, mode):
    if not active():
        return os.access(path, mode)
    return run(['@access', os.fspath(path), 'x' if mode == os.X_OK else 'w'],
               capture_output=True).returncode == 0
