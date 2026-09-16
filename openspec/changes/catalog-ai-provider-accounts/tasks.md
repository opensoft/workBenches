## 1. Contracts and Catalogs

- [x] 1.1 Add the shared account-catalog schema and provider normalization contract to workBenches.
- [x] 1.2 Add `ai/accounts/` provider and account catalogs to Opensoft-Tenant using current stable account and credential IDs.
- [x] 1.3 Add `ai/accounts/` provider and account catalogs to AI-Credentials using current stable account and credential IDs.
- [x] 1.4 Link existing profile authentication metadata to the corresponding stable account IDs in both private registries.

## 2. Combined Validation and Reporting

- [x] 2.1 Implement the workBenches combined account validator/report with human and JSON output.
- [x] 2.2 Detect duplicate IDs, orphan relationships, ownership inconsistencies, forbidden secret metadata, and missing active escrow.
- [x] 2.3 Add fixture tests for valid composition and every required failure class.

## 3. Documentation and Integration

- [x] 3.1 Document account, profile, credential, provider, and custody boundaries in both private repositories.
- [x] 3.2 Document combined reporting and secret-safe limitations in workBenches.
- [x] 3.3 Run individual and combined validation against the current Opensoft and Brett registries and reconcile every blocking finding.

## 4. Completion

- [x] 4.1 Verify no account catalog or report contains credential payload fields or token-like values.
- [x] 4.2 Reconcile OpenSpec and Speckit completion and record any metadata gaps that remain intentionally explicit.
