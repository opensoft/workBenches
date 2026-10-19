"""WSGI API. TLS terminates at the organization's authenticated HTTPS ingress."""
import json
import os
import re
from pathlib import Path

from core import AzureVault, Broker, BrokerError, MAX_BYTES, https
from devices import DeviceRegistry


class OIDC:
    def __init__(self, config):
        import jwt
        self.jwt = jwt
        self.issuer = https(config['issuer'])
        self.audience = config['audience']
        self.jwks = jwt.PyJWKClient(https(config['jwksUrl']), timeout=10)

    def __call__(self, authorization):
        if not authorization.startswith('Bearer ') or len(authorization) > 16384:
            raise BrokerError(401, 'authentication_required')
        try:
            token = authorization[7:]
            key = self.jwks.get_signing_key_from_jwt(token)
            claims = self.jwt.decode(token, key.key, algorithms=['RS256'],
                issuer=self.issuer, audience=self.audience,
                options={'require': ['iss', 'sub', 'exp', 'iat', 'aud']})
            if not isinstance(claims['sub'], str) or not claims['sub']:
                raise ValueError()
            return claims
        except Exception:
            raise BrokerError(401, 'invalid_or_expired_identity') from None


class Application:
    def __init__(self, broker, authenticate, config_path=None):
        self.broker, self.authenticate, self.config_path = broker, authenticate, config_path

    def __call__(self, env, start):
        try:
            broker = self.broker
            if self.config_path:
                config = json.loads(Path(self.config_path).read_text())
                # A deployment identity change requires restart; grant revocation
                # and profile disabling take effect on the very next request.
                if any(config[k] != broker.config[k] for k in ('issuer', 'audience', 'jwksUrl', 'database')):
                    raise BrokerError(503, 'deployment_configuration_changed')
                broker = Broker(config, broker.vault)
            identity = self.authenticate(env.get('HTTP_AUTHORIZATION', ''))
            path = env.get('PATH_INFO', '')
            if env['REQUEST_METHOD'] == 'GET' and path == '/v1/profiles':
                value = broker.metadata(identity)
            else:
                length = int(env.get('CONTENT_LENGTH') or 0)
                if env['REQUEST_METHOD'] != 'POST' or not 0 < length <= MAX_BYTES * 2:
                    raise BrokerError(400, 'invalid_request')
                raw = env['wsgi.input'].read(length)
                if len(raw) != length:
                    raise BrokerError(400, 'invalid_request')
                data = json.loads(raw)
                if not isinstance(data, dict): raise BrokerError(400, 'invalid_request')
                device_route = path.startswith('/v1/devices/')
                if device_route:
                    value = DeviceRegistry(broker).call(identity, path.removeprefix('/v1/devices/'), data)
                    name = None
                else:
                    name = data['profileId']
                if not device_route and (not isinstance(name, str) or not re.fullmatch(r'[a-zA-Z0-9_.:-]{1,180}', name)):
                    raise BrokerError(400, 'invalid_request')
                if device_route:
                    pass
                elif path == '/v1/fetch':
                    value = broker.fetch(identity, name)
                elif path == '/v1/publish':
                    value = broker.publish(identity, name, data['credential'], data['expectedVersion'], data['idempotencyKey'])
                elif path == '/v1/maintain':
                    value = broker.maintain(identity, name)
                elif path == '/v1/reconcile':
                    value = broker.reconcile(identity, name)
                elif path == '/v1/require-login':
                    value = broker.require_login(identity, name, data['expectedVersion'])
                else:
                    raise BrokerError(404, 'not_found')
            status = 200
        except BrokerError as error:
            status, value = error.status, {'error': error.code}
        except (ValueError, KeyError, TypeError):
            status, value = 400, {'error': 'invalid_request'}
        except Exception:
            # SDK/adapter exceptions can contain payloads: never reflect or log them.
            status, value = 503, {'error': 'broker_unavailable'}
        body = json.dumps(value, allow_nan=False).encode()
        start(str(status) + ' ' + {200: 'OK', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden',
              404: 'Not Found', 409: 'Conflict', 422: 'Unprocessable Entity', 503: 'Service Unavailable'}.get(status, 'Error'),
              [('Content-Type', 'application/json'), ('Cache-Control', 'no-store'),
               ('Content-Length', str(len(body))), ('X-Content-Type-Options', 'nosniff')])
        return [body]


def create_app():
    os.umask(0o077)
    config = json.loads(Path(os.environ['WORKBENCHES_BROKER_CONFIG']).read_text())
    return Application(Broker(config, AzureVault(config.get('managedIdentityClientId'))), OIDC(config), os.environ['WORKBENCHES_BROKER_CONFIG'])
