"""Public-only job egress. Request content and credentials are never logged."""
import ipaddress
import select
import socket
import socketserver
from urllib.parse import urlsplit


def connect_public(host, port):
    addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
        raise ValueError('Non-public destination')
    failure = None
    for family, kind, proto, _, address in addresses:
        upstream = socket.socket(family, kind, proto)
        upstream.settimeout(30)
        try:
            upstream.connect(address)
            upstream.settimeout(300)
            return upstream
        except OSError as error:
            failure = error
            upstream.close()
    raise failure


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(300)
        try:
            method, target, version = self.rfile.readline(8192).decode('ascii').split()
            headers, size = [], 0
            while True:
                line = self.rfile.readline(8192)
                size += len(line)
                if not line or size > 32768:
                    raise ValueError('Invalid headers')
                if line in (b'\r\n', b'\n'):
                    break
                key, value = line.split(b':', 1)
                if key.lower() not in (b'proxy-authorization', b'proxy-connection', b'connection', b'host'):
                    headers.append((key, value.strip()))
            if method == 'CONNECT':
                host, port = target.rsplit(':', 1)
                port = int(port)
                if port not in (22, 443):
                    raise ValueError('Port denied')
                request = None
            elif method in ('GET', 'HEAD'):
                url = urlsplit(target)
                if url.scheme != 'http' or url.port not in (None, 80) or url.username or url.password:
                    raise ValueError('Only public HTTP downloads supported')
                host, port = url.hostname, 80
                if not host or any(k.lower() in (b'content-length', b'transfer-encoding') for k, _ in headers):
                    raise ValueError('Unexpected body')
                path = (url.path or '/') + ('?' + url.query if url.query else '')
                request = f'{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n'.encode('ascii')
                request += b''.join(k+b': '+v+b'\r\n' for k,v in headers) + b'\r\n'
            else:
                raise ValueError('Method denied')
            with connect_public(host, port) as upstream:
                if request is None:
                    self.wfile.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                    self.wfile.flush()
                else:
                    upstream.sendall(request)
                peers = (self.connection, upstream)
                while True:
                    ready, _, _ = select.select(peers, (), (), 600)
                    if not ready:
                        return
                    for source in ready:
                        data = source.recv(65536)
                        if not data:
                            return
                        (upstream if source is self.connection else self.connection).sendall(data)
        except (ValueError, OSError, UnicodeError):
            try:
                self.wfile.write(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
                self.wfile.flush()
            except OSError:
                pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == '__main__':
    Server(('0.0.0.0', 3128), Handler).serve_forever()
