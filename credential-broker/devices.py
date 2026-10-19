"""Public per-user device registry; destination capabilities control SSH grants."""
import hashlib
import hmac
import json
import re
import time

from core import BrokerError, canonical
from device_keys import metadata, fingerprint

LEASE_SECONDS = 600


class DeviceRegistry:
    def __init__(self, broker):
        self.broker = broker
        with broker.db() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS devices(
                    id TEXT PRIMARY KEY, context TEXT NOT NULL, owner TEXT NOT NULL,
                    capability TEXT NOT NULL, metadata TEXT NOT NULL, seen REAL NOT NULL,
                    retired INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS device_grants(
                    source TEXT NOT NULL, destination TEXT NOT NULL, state TEXT NOT NULL,
                    updated REAL NOT NULL, PRIMARY KEY(source,destination));
                CREATE TABLE IF NOT EXISTS device_audit(
                    at REAL NOT NULL, owner TEXT NOT NULL, context TEXT NOT NULL,
                    device TEXT NOT NULL, action TEXT NOT NULL, peer TEXT);
            ''')

    def scope(self, identity, data):
        config = self.broker.config.get('deviceRegistry', {})
        context = data.get('context')
        policy = config.get('contexts', {}).get(context, {}) if isinstance(context, str) else {}
        if config.get('enabled') is not True or policy.get('enabled') is not True:
            raise BrokerError(403, 'device_registry_disabled')
        if identity.get('iss') != self.broker.config['issuer'] or not identity.get('sub'):
            raise BrokerError(403, 'device_identity_required')
        owner = canonical([identity['iss'], identity['sub']])
        if context != 'personal' and not any(g.get('issuer') == identity['iss'] and g.get('subject') == identity['sub']
                                            for g in policy.get('members', [])):
            raise BrokerError(403, 'device_context_denied')
        return context, owner

    @staticmethod
    def identifier(value):
        if not isinstance(value, str) or not re.fullmatch(r'device-[a-f0-9]{32}', value):
            raise BrokerError(400, 'invalid_device_id')
        return value

    def device(self, db, value, context, owner):
        row = db.execute('SELECT * FROM devices WHERE id=? AND context=? AND owner=? AND retired=0',
                         (self.identifier(value), context, owner)).fetchone()
        if row is None: raise BrokerError(404, 'device_not_found')
        return row

    @staticmethod
    def capability(row, value):
        if not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{64}', value) or not hmac.compare_digest(
                row['capability'], hashlib.sha256(value.encode()).hexdigest()):
            raise BrokerError(403, 'destination_device_required')

    @staticmethod
    def describe(row):
        data = json.loads(row['metadata'])
        return dict(data, id=row['id'], lastSeen=row['seen'], fingerprint=fingerprint(data['publicKey']),
                    hostFingerprint=fingerprint(data['hostKey']) if data['hostKey'] else '')

    def call(self, identity, operation, data):
        context, owner = self.scope(identity, data)
        with self.broker.db() as db:
            if operation == 'list':
                rows = db.execute('SELECT * FROM devices WHERE context=? AND owner=? AND retired=0 ORDER BY seen DESC',
                                  (context, owner)).fetchall()
                ids = {r['id'] for r in rows}
                grants = [dict(r) for r in db.execute('SELECT * FROM device_grants')
                          if r['source'] in ids and r['destination'] in ids]
                return {'devices': [self.describe(r) for r in rows], 'connections': grants, 'leaseSeconds': LEASE_SECONDS}
            key = self.identifier(data.get('deviceId'))
            if operation == 'register':
                info = metadata(data['metadata'])
                token = data.get('deviceToken')
                if not isinstance(token, str) or not re.fullmatch(r'[a-f0-9]{64}', token):
                    raise BrokerError(400, 'invalid_device_capability')
                row = db.execute('SELECT * FROM devices WHERE id=?', (key,)).fetchone()
                if row:
                    if row['retired'] or row['context'] != context or row['owner'] != owner:
                        raise BrokerError(409, 'device_registration_conflict')
                    self.capability(row, token)
                    previous = json.loads(row['metadata'])
                    if previous['publicKey'] != info['publicKey'] or previous['username'] != info['username']:
                        raise BrokerError(409, 'register_new_device_for_new_login_key')
                    if previous['hostKey'] != info['hostKey'] or previous['address'] != info['address'] or previous['port'] != info['port']:
                        db.execute('DELETE FROM device_grants WHERE source=? OR destination=?', (key, key))
                    db.execute('UPDATE devices SET metadata=?,seen=? WHERE id=?', (canonical(info), time.time(), key))
                else:
                    db.execute('INSERT INTO devices(id,context,owner,capability,metadata,seen) VALUES(?,?,?,?,?,?)',
                               (key, context, owner, hashlib.sha256(token.encode()).hexdigest(), canonical(info), time.time()))
            else:
                if operation == 'forget':
                    row = db.execute('SELECT * FROM devices WHERE id=? AND context=? AND owner=?', (key, context, owner)).fetchone()
                    if row is None: raise BrokerError(404, 'device_not_found')
                else:
                    row = self.device(db, key, context, owner)
                if operation != 'forget': self.capability(row, data.get('deviceToken'))
                if operation in ('request', 'approve', 'revoke'):
                    peer = self.device(db, data.get('peerId'), context, owner)
                    if peer['id'] == key: raise BrokerError(400, 'same_device')
                    source, destination = (key, peer['id']) if operation == 'request' else (peer['id'], key)
                    destination_row = peer if operation == 'request' else row
                    destination_info = json.loads(destination_row['metadata'])
                    if operation != 'revoke' and not (destination_info['hostKey'] and destination_info['address']):
                        raise BrokerError(409, 'destination_ssh_not_configured')
                    if operation == 'revoke':
                        db.execute('DELETE FROM device_grants WHERE source=? AND destination=?', (source, destination))
                    else:
                        existing = db.execute('SELECT state FROM device_grants WHERE source=? AND destination=?',
                                              (source, destination)).fetchone()
                        state = 'approved' if operation == 'approve' or existing and existing['state'] == 'approved' else 'requested'
                        db.execute('INSERT OR REPLACE INTO device_grants VALUES(?,?,?,?)', (source, destination, state, time.time()))
                elif operation == 'forget':
                    db.execute('UPDATE devices SET retired=1 WHERE id=?', (key,))
                    db.execute('DELETE FROM device_grants WHERE source=? OR destination=?', (key, key))
                elif operation == 'sync':
                    db.execute('UPDATE devices SET seen=? WHERE id=?', (time.time(), key))
                    approved = db.execute('''SELECT d.* FROM devices d JOIN device_grants g ON d.id=g.source
                        WHERE g.destination=? AND g.state='approved' AND d.retired=0 AND d.owner=? AND d.context=?''',
                                          (key, owner, context)).fetchall()
                    return {'authorized': [self.describe(r) for r in approved], 'expiresAt': int(time.time()) + LEASE_SECONDS}
                else:
                    raise BrokerError(404, 'not_found')
            db.execute('INSERT INTO device_audit VALUES(?,?,?,?,?,?)',
                       (time.time(), owner, context, key, operation, data.get('peerId')))
            return {'ok': True, 'deviceId': key}
