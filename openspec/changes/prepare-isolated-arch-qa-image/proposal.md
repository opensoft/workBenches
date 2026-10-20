# Prepare isolated native Arch QA images

Provide a KVM image preparer for the existing native QA contract. Use a pinned
Arch cloud image, a separate disk and SSH identity, private loopback metadata,
root-owned adapters, serial-pinned SSH and a validated upgraded-kernel reboot.
Refuse existing state directories and unverified images. Stop the VM after
validation or failure. Never install/register a runner on the daily host or
claim live QA is enabled. Per-job reset/registration remains a separate prerequisite.

Validate with configuration/guard regressions and a real disposable VM boot,
package preparation, Docker/Buildx checks and clean shutdown on Raven.
