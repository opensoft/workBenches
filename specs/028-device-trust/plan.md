# v1.7 implementation plan

1. Extend the authenticated broker with a disabled-by-default public device
   registry, immutable owners, scoped contexts, device capabilities, requests,
   directional grants, audit records, check-in, and retirement.
2. Add workstation registration, dedicated key generation through native Tools
   callbacks, leased authorized_keys reconciliation, strict host-pinned connect,
   sign-in/sign-out integration, and an optional periodic agent.
3. Add keyboard Devices management to Profiles, with personal/company selection,
   explicit approval confirmations, pending requests, and revocation status.
4. Verify real isolated SSH login/rejection/revocation, owner/context isolation,
   key changes, offline behavior, filesystem preservation, and cancellation.
5. Record implementation evidence and remaining live deployment/platform gates.
   Do not deploy infrastructure, publish a release, or change v1.6 sources.
