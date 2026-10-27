"""Private, bounded Rclone browser setup in a disposable Tools-image container."""
import configparser
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

PORT = 53682


class Relay(BaseHTTPRequestHandler):
    # Docker publishes this container-interface listener on host loopback only.
    # Rclone itself listens on container loopback at the same port.
    def log_message(self, *_):
        pass  # Callback query parameters must never enter logs.

    def do_GET(self):
        if len(self.path) > 16384 or self.path.split('?', 1)[0] not in ('/', '/auth'):
            self.send_error(404); return
        client = http.client.HTTPConnection('127.0.0.1', PORT, timeout=15)
        try:
            client.request('GET', self.path)
            response = client.getresponse()
            body = response.read(65537)
            if len(body) > 65536:
                self.send_error(502); return
            self.send_response(response.status)
            for key in ('Content-Type', 'Location'):
                if response.getheader(key): self.send_header(key, response.getheader(key))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers(); self.wfile.write(body)
        except (OSError, http.client.HTTPException):
            self.send_error(503, 'Waiting for browser sign-in')
        finally:
            client.close()


def reply(option):
    name = option.get('Name')
    # Never fall back to manual token/secret entry or silently choose a shared app.
    if option.get('IsPassword') or name not in {
            'config_is_local', 'config_type', 'config_driveid', 'config_driveok',
            'config_team_drive', 'config_change_team_drive', 'config_root_folder_id'}:
        raise ValueError('This provider needs supported OAuth application configuration.')
    if name == 'config_is_local': return 'true'
    if name == 'config_type': return 'onedrive'
    examples = option.get('Examples') or []
    print('Select a drive/folder for this connection:', flush=True)
    for index, example in enumerate(examples, 1):
        label = ''.join(c for c in str(example.get('Help') or example.get('Value', '')) if c.isprintable())
        print(f'  {index}. {label[:180]}', flush=True)
    answer = input('Choice number (Enter uses default, Q cancels): ').strip()
    if answer.lower() == 'q': raise SystemExit(130)
    if not answer: return str(option.get('DefaultStr', ''))
    if not answer.isdigit() or not 1 <= int(answer) <= len(examples):
        raise ValueError('Choose a listed drive.')
    return str(examples[int(answer) - 1]['Value'])


def private_command(argv, env, root):
    """Capture sensitive Rclone output while exposing only its safe browser URL."""
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(argv, env=env, stdout=output, stderr=errors)
        deadline = time.monotonic() + 600; shown = False
        try:
            while process.poll() is None:
                url_file = root / 'browser-url'
                if not shown and url_file.exists():
                    url = url_file.read_text()[:2048]
                    if url.startswith('http://127.0.0.1:53682/auth?state=') and all(c.isprintable() for c in url):
                        print('If the browser did not open, open this page on your workstation: ' + url, flush=True)
                    shown = True
                if time.monotonic() >= deadline: raise ValueError('Browser approval timed out.')
                time.sleep(.1)
            if process.returncode: raise ValueError('Browser sign-in did not complete.')
            output.seek(0); raw = output.read(65537)
            if len(raw) > 65536: raise ValueError('Invalid provider configuration response.')
            return json.loads(raw or b'{}')
        finally:
            if process.poll() is None: process.kill(); process.wait()
            (root / 'browser-url').unlink(missing_ok=True)


def configure(root, backend, write=False):
    os.umask(0o077)
    options = {'config_is_local': 'true'}
    if backend == 'drive': options['scope'] = 'drive' if write else 'drive.readonly'
    elif backend == 'onedrive':
        options.update(access_scopes='Files.ReadWrite offline_access' if write else 'Files.Read offline_access')
    else: raise ValueError('Unsupported provider.')
    app = root / 'app.json'
    if app.exists():
        data = json.loads(app.read_text())
        if set(data) - {'client_id', 'client_secret'}: raise ValueError('Invalid app settings.')
        options.update(data)
    if options.get('client_secret'):
        result = subprocess.run(['rclone', 'obscure', '-'], input=options['client_secret'] + '\n',
                                capture_output=True, text=True, timeout=10)
        if result.returncode: raise ValueError('Could not protect application configuration.')
        options['client_secret'] = result.stdout.strip()
    if backend == 'drive' and not options.get('client_id'):
        raise ValueError('Google Drive needs a configured OAuth application.')
    config = root / 'rclone.conf'
    # Secret app options are in the private config, never process arguments.
    parser = configparser.ConfigParser(interpolation=None)
    parser['cloud'] = dict(type=backend, **options)
    with config.open('x') as stream: parser.write(stream)
    config.chmod(0o600)
    base = ['rclone', 'config', 'update', 'cloud', '--config', str(config), '--non-interactive']
    env = {k: v for k, v in os.environ.items() if not k.startswith('RCLONE_')}
    env['PATH'] = '/opt/workbenches/rclone-browser-bin:' + env['PATH']
    print('Complete sign-in in your workstation browser. Q/Ctrl+C cancels.', flush=True)
    state, answer = '', ''
    for _ in range(16):
        argv = base + (['--continue', '--state', state, '--result', answer] if state else [])
        # Outputs may contain credentials. Capture privately and never reflect errors.
        response = private_command(argv, env, root)
        state = response.get('State', '')
        if response.get('Error'): raise ValueError('Provider setup needs attention.')
        if not state:
            parser.read(config)
            if not parser.get('cloud', 'token', fallback=''): raise ValueError('No authorization saved.')
            print('Browser authorization saved privately.', flush=True)
            return
        answer = reply(response.get('Option') or {})
    raise ValueError('Provider setup did not finish.')


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    root, backend = Path(sys.argv[1]), sys.argv[2]
    address = socket.gethostbyname(socket.gethostname())
    if address.startswith('127.'): raise ValueError('Use the isolated login container.')
    server = ThreadingHTTPServer((address, PORT), Relay)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try: configure(root, backend, write='--write' in sys.argv[3:])
    finally: server.shutdown(); server.server_close()


if __name__ == '__main__':
    try: main()
    except (KeyboardInterrupt, EOFError): raise SystemExit(130)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print('Cloud connection failed. Check app configuration, browser approval and callback port 53682. Existing connections are preserved.', file=sys.stderr)
        raise SystemExit(1)
