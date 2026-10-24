# Verification

Select `SPECIFY_FEATURE=033-company-connection-wizard` and
`SPECIFY_FEATURE_DIRECTORY=specs/033-company-connection-wizard`.
Run tasks' commands inside declared Tools/workstation test containers.

User walkthrough: add company → Sign in → import company setup or open admin
guide → review issuer/application ID → discovery check → confirm → optional
descriptor export → existing browser/device login. Decline/back/cancel must
preserve existing configuration, saved identities and queued software.

Test exported descriptors only with disposable fixtures or explicitly authorized
administration. Fixture success does not register a client or certify an actual
provider deployment. Record local/CI results separately from attended sign-in.
