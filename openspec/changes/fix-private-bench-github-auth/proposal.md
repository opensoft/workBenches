# Restore private GitHub bench installation from Tools

Authority: Brett requested fixing workBenches issue #210 for v1.6.1 on
2026-10-23. The failing build is merged main `5407ee9`. Git runs inside the
declared Tools container, while workstation GitHub CLI credentials and keyring
access remain native. An absolute workstation gh credential-helper path cannot
execute inside Tools. A read-only cloudBench probe confirmed that the existing
native gh command bridge can authenticate successfully.

Append a command-local, GitHub.com-scoped `gh auth git-credential` fallback to
HTTPS clone/submodule commands. Resolve gh through PATH so Tools uses its native
bridge. Keep existing helpers first; do not rewrite global Git configuration,
switch accounts, persist tokens in metadata/logs or arguments, or route from Profiles
metadata. SSH remains preferred and public/other-host clones retain their
existing behavior. Failed private-repository preparation must identify the
repository and provide native sign-in/access recovery guidance without exposing
a raw Python subprocess exception.

This repairs the existing source preparation and native GitHub boundary. It
does not implement per-project account selection or change credential storage,
source pins, release versions, or publication gates. Implementation and
verification belong to the appended issue #210 tasks in
`specs/026-profile-onboarding/tasks.md`; no duplicate task list lives here.
