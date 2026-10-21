# Eagle fleet execution

The Windows controller serves selected repositories in organization groups named
`Eagle Linux`. Workflows select `eagle-linux-ubuntu24` explicitly. There is no
GitHub-hosted fallback. A second profile must be qualified before using the
`eagle-linux-ubuntu22` label. Native Windows, macOS and KVM jobs require their own
qualified capacity; changing a label does not change their operating system.

Each assigned job gets a fresh network guard and an unprivileged rootless Docker
backend. The runner itself is a nested container. Its workspace, tool cache,
externals and Docker socket belong exclusively to that backend. No host folder,
host Docker socket, bench credential or GitHub administration token enters it.
The socket mounted in the nested runner is its disposable rootless engine.
Package installation and Bubblewrap capabilities apply inside its user namespace.
The public egress gateway rejects private, loopback, link-local and mixed DNS
answers and connects to validated numeric addresses. Fork approval and protected
environment approval remain GitHub's existing controls. Containers share Eagle's
kernel; this architecture does not provide a VM boundary.

One fleet worker runs at a time, with an 8 GiB backend limit and four CPUs.
Admission requires 10 GiB of Linux MemAvailable. No bench is stopped or restarted.
The host enforces a 7.5-hour maximum lifetime independently of code running inside
the sandbox; GitHub's original job timeout still applies. Idle listeners retire
after 15 minutes. Runner deletion precedes normal teardown and fails closed on
assignment races. Container/volume names are journaled before deletion. An
uncertain create is reconciled by its exact identity, never repeated blindly.

Deploy this directory to a host-local service directory. Keep `config.json`,
`pools.json`, DPAPI authentication, state, locks and logs outside Git. Build the
gateway and worker images from their declared Dockerfiles and pin their image
IDs in configuration. Provision selected-repository groups before enabling any
workflow. Start-Infrastructure.ps1 touches only owned fleet infrastructure.
Run Watch-Fleet.ps1 with an explicit Python executable from a current-user
interactive AtLogon task. Authentication uses a same-user DPAPI file and exists
only in the host controller environment; registration tokens go to config.sh over
stdin, never arguments or logs.

Put an empty `STOP` file in the service directory to drain: an assigned job
continues, while an idle runner retires and the controller exits. Resume by
removing STOP and starting the scheduled task. Recover a stale create by first
inspecting the exact journaled names and GitHub assignment. Never use global
Docker prune, WSL shutdown or a Docker restart as runner cleanup.

Validation: `python -m unittest discover -s . -p 'test_*.py'` on Windows;
`python3 -m unittest discover -s . -p test_routing.py` in the Python bench.
The local compatibility probe proved nonroot execution, sudo, a user-namespace
UID mapping, private rootless Docker, container-action workspace roundtrip,
localhost service connectivity, public HTTPS/apt and Bubblewrap. Private-address
HTTPS was denied. These probes are preparation; actual GitHub run URLs and job
runner names are required to report successful workflow migration.

Routing changes preserve workflow triggers, job dependencies, test commands,
permissions, environment approvals and matrix rows. Matrix values remain original
so platform conditionals retain their meaning. Pinned reusable workflow providers
must land before consumers advance coherent pins through their declared tooling.
Never edit a shape-copy digest just to silence its drift gate.
