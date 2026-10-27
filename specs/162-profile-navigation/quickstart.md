# Verify and review

Run the declared Tools image for profile data/transport tests and the declared
`workbenches-test:workstation` image for workstation setup fixtures. Temporary
test directories need executable fixture scripts; a noexec temporary mount is
not a valid native-host fixture environment. Never mount production credentials
into standalone acceptance fixtures.

Profile suites: `test-profile-navigation.py`, `test-profile-multi-identity.py`,
`test-setup-profiles.py`, `test-profile-sources.py`, `test-cloud-profiles.py`,
`test-company-connection.py`. Workstation suites: `test-setup-guided-flow.py`,
`test-setup-requirements.py`, `test-setup-async.py`, `test-release-version.py`.
The standard tools-runtime Compose service checks actual native/Tools boundaries.

Manual review: run `./setup.sh`, press G, select each profile kind, inspect the
list and About, add/edit disposable metadata, then open AI profiles → model maker
→ accounts. Check B at every level and PgUp/PgDn for a long About description.
Use a disposable portable file for import/export; production cloud uploads need
explicit attended authorization in the UI. The existing personal/company IDs
and credential paths must remain unchanged after navigation.
