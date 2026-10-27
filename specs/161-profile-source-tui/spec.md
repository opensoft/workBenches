# Scoped profile-source setup (v1.6.2)

Authority: Brett, 2026-10-26: implement the approved manifest-source workflow with intuitive personal/company panes matching 1.6.x. Extends the governed `profile-manifest-sources` proposal and integrates feature 160's existing cloud connector.

Provide explicit personal/company ownership, local native picker/manual path, public HTTPS and selected-account GitHub reads, reviewed provider manifests or authorized registry sets, saved-source refresh and scoped recovery. Preserve credentials and unrelated scopes on cancellation/failure; do not publish remote edits. Private Drive sources use feature 160's browser connections and drive browser; unsupported sharing URLs explain that route. No company broker or peer service is required.

A GitHub tenant registry uses the selected verified immutable account, commit-pinned content and that user's grants. Local/provider bundles contain metadata only, not authorizations or sessions. Native dialogs run on the host with manual fallback. File/URL/network reads and persisted metadata are bounded. Protected URLs never prompt for pasted secrets. Atomic source/config writes follow review; review-to-apply races are detected.

Fixture acceptance does not certify live native dialogs or production provider consent. Supported platform routing and errors need meaningful tests, plus attended live checks before release.
