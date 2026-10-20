# Run real native Arch acceptance in one-use VMs

The first actual native run exposed a fixture conflict: shell setup creates
.zshrc links, then the workstation preservation driver refuses to overwrite them.
Run shell installation/repeat in a separate private HOME while retaining all
workstation preservation assertions. Both homes belong to the one-use QA account.

Add an exact-source VM controller: clone a validated stopped golden disk, pin
bootstrap SSH, rotate both guest host key and operator key through that trusted
channel, assign a new reset ID/root marker, transfer git bundles, run the pinned
native adapter and stop/dispose the job. No host directories, agent or Docker
socket are mounted. This is not runner registration or an attestation upload API.

Failure metadata is restricted to known phases/driver basenames, numeric exit
status/line and allowlisted exception classes. Private diagnostics are never
reflected. Failed disks are retained privately for investigation; passing disks
and operator keys are removed. Persistent Raven provisioning hosts remain
ineligible for native release certification.

Validation: release framework tests pass, including diagnostic injection privacy.
The corrected native VM run is in progress; do not claim native acceptance passed
until its complete report and cleanup prove it.
