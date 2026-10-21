# Feature 030: Eagle fleet routing

Governance: openspec/changes/route-github-fleet-to-eagle.

The user requires all GitHub jobs affected by the hosted billing cap to use Eagle, not only midNet. Inventory all accessible owned/admin repositories and classify each job by OS, architecture, tools, services, public/fork controls and deployment gates. Explicit Eagle labels must queue when busy and never fall back to billed hosted capacity.

Acceptance: portable Linux validation jobs across repositories execute normally on fresh Eagle workers; Windows/macOS/hardware gaps remain explicit until compatible capacity exists; assertions and matrix rows remain present; protected publishing remains approved by humans; job code cannot reach host files, shared Docker daemon, host credentials, LAN or metadata; live benches remain running; source changes and activation are tracked per repository with exact heads and run results.

Clarifications: Eagle uses WSL-backed Docker. Docker, WSL and Windows must not be restarted. Windows VM and Mac availability choices have been requested; Linux work continues independently. Existing specialized self-hosted worker queues are not billing-blocked hosted jobs.