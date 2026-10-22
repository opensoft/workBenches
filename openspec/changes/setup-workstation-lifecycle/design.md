# Workstation lifecycle design

Use the existing component_checked/component_action queue with four additive service keys and install/uninstall actions. Review includes Workstation changes and dependency/removal warnings. Missing required services may be queued for install; prerequisite-only removal plans do not require the services being removed to be Up. Unrelated component plans retain readiness gates.

A native Bash serializer writes the existing schemaVersion-1 JSON atomically/private without Python, allowing a missing-Docker installation plan to be saved. The root launcher validates the complete canonical generated plan with a strict Bash reader before prerequisite actions, then installs services. Full Python validation still runs before component work. Service-only plans avoid unrelated component/account/image setup. Managed removals and host removals run last, with preflight for every removal before any service action. Bootstrap checks do not auto-install missing/stopped Tools; selected install/start does so.

The shared lifecycle library contains no renderer calls. Display uses in-memory state only. Supported Linux Engine package removals preserve data and avoid autoremove/purge. Unsupported Docker Desktop and WSL teardown are explicit failures with manual directions; no success or reboot is fabricated. Tools/Vault removal validates role, uid and HOME labels before stop/rm, never removes volumes/images, and does not refresh afterward (which could recreate a removed service).

Component plans retain required readiness. When prerequisites are missing, apply a service-only install plan first; then reopen setup for components. Mixed plans receive full Python/catalog validation before any selected service change.
