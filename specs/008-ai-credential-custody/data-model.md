# Data Model: AI Credential Custody

## Profile Record

- `provider`: normalized provider ID
- `name`: canonical profile name
- `aliases`: alternate launcher names
- `email`: expected login identity metadata
- `family`: non-secret state-sharing group
- `status`: `active`, `planned`, `disabled`, or `retired`
- `owner`: exactly one `{type, id}` authority
- `accountId`: stable provider-account identifier
- `credentialId`: stable credential identifier

Relationship: one profile record references one credential record; canonical names may repeat across providers but account and credential IDs cannot.

## Credential Record

- `credentialId`: globally stable identity
- `authentication.type`: provider authentication mode
- `canonicalStore`: `azure-key-vault` for Opensoft or `sops-age` for Brett personal
- `escrowStatus`: lifecycle/coverage state
- `automationAllowed`: explicit policy, false by default for interactive subscription credentials

## Durable Secret Mapping

- `provider`
- `profile`
- `credentialId`
- `secretName`
- `enabled`
- `lifecycle`: `active`, `planned`, `disabled`, `retired`, or `legacy-dr`

Validation rules:

- Enabled provider/profile and secret names are unique.
- Secret names follow `ai-credential-<provider>-<profile>`.
- Owner is inherited only through an explicit credential relationship, never inferred from spelling.
- Personal credentials cannot point at the Opensoft canonical vault.

## Vault Contract

- `schemaVersion`
- `owner`
- `tenantId`
- `subscriptionId`
- `vaultName`
- `canonicalFor`: list of owner IDs or credential classes
- `secretNamePattern`
- `entries`: durable secret mappings

The contract contains no secret value or version payload.

## Credential Generation

- `secretId`: exact versioned URI
- `provider`
- `profile`
- `contentType`
- management tags
- creation/update metadata supplied by the vault

State transitions:

```text
planned → available → verified → superseded
                    ↘ disabled → retained
```

Restore never deletes or mutates a generation.

## Local Materialization

- Canonical provider-contained path
- Mode-0600 regular JSON file
- Provider-specific structural validity
- Exact restored `secretId` recorded in owner-only local state

State transitions:

```text
missing → staged → validated → atomically installed
existing → preserved
existing + explicit force → staged → validated → atomically replaced
```
