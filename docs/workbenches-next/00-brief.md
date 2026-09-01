# Stage 0: Product Brief

Status: **brainstorm**

## Product Intent

workBenches should become an installable and maintainable workstation product,
not merely a repository that happens to contain setup scripts and nested Git
repositories.

For a Windows user, the intended experience is:

1. Launch a signed Windows setup application.
2. See whether required Windows and WSL capabilities are ready.
3. Enable WSL 2 and install Ubuntu 24.04 when required.
4. Resume safely after any reboot.
5. Configure the WSL user environment, including Zsh and Oh My Zsh.
6. Select workBenches, AI tools, terminals, and related integrations.
7. Install or pull a compatible set of container images and bench sources.
8. Finish with a clear health report and launch paths.

The same product definitions must remain useful to command-line setup,
continuous integration, CodeXfactory, and future non-Windows installers.

## Goals

- Give users a coherent Windows installation and setup experience.
- Make bench discovery and selection data-driven.
- Give every image layer a clear owner and a written reason for existing at
  that layer.
- Keep independent benches independently maintainable when they have their own
  release cadence or consumers.
- Make a product release reproducible with immutable repository revisions and
  image digests.
- Make CodeXfactory able to govern cross-repository changes without hiding the
  component boundaries.
- Keep canonical documentation close to the component that owns the behavior.
- Preserve a familiar local workspace layout for current users during
  migration.

## Non-goals for the First Proposal

- Rewriting every existing setup script.
- Moving every bench repository at once.
- Deleting current Git submodules before a replacement workflow is proven.
- Selecting every installer UI detail.
- Standardizing all historical bench naming in the same change.
- Moving unrelated operational documentation without first identifying its
  owner.
- Publishing or deploying a Windows installer.
- Changing live images or running containers.

## Constraints

- The Windows installer needs elevation for some operations, but the full
  application should not run elevated continuously.
- WSL enablement may require a reboot, so setup must be resumable and
  idempotent.
- Ubuntu 24.04 is the assumed WSL distribution.
- Zsh and Oh My Zsh are part of the expected user environment.
- Existing workBenches scripts contain useful behavior and should initially be
  treated as an execution backend to wrap and progressively separate.
- Container images are binary release artifacts and should not be stored in
  Git.
- User credentials and AI profiles remain user state; they are not product
  release content.
- A Git branch, floating image tag, or nested working tree is insufficient as
  a reproducible release identity.
- The current worktree contains unrelated changes. Architecture discovery must
  not disturb them.

## Product Boundaries to Define

The proposal must answer six ownership questions:

1. Who owns the product catalog and compatibility release?
2. Who owns Layer 0, each Layer 1 family, and the Layer 3 recipe?
3. Who owns each Layer 2 bench and its tool inventory?
4. Who owns Windows host bootstrap and reboot-resume behavior?
5. Who owns cross-system documentation versus component documentation?
6. How does CodeXfactory coordinate a product change that crosses several
   repositories?

## Success Shape

```text
                 one product definition
                         |
          +--------------+--------------+
          |              |              |
          v              v              v
   Windows setup      CLI setup     CI / CodeXfactory
          |              |              |
          +--------------+--------------+
                         |
                         v
             exact compatible release
                         |
          +--------------+--------------+
          |              |              |
          v              v              v
       sources        image digests   verification
```

The product definition must be shared, but the Windows user interface,
container build graph, and individual benches do not need to live in the same
repository.
