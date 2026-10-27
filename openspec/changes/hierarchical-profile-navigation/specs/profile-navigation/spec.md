## ADDED Requirements

### Requirement: Profile navigation has three kinds
The wizard SHALL show Personal, Company and Workstation in its Profile pane.
Each kind SHALL open a separate list with an Add action last. About SHALL
describe only the highlighted item. Selecting a profile SHALL open its editor.

#### Scenario: Personal profile selected
- WHEN a personal profile is highlighted and opened
- THEN its own information, source location, GitHub links and AI profiles are
  available without exposing other profiles' accounts.

### Requirement: AI accounts are nested by model maker
Personal and company editors SHALL open a model-maker list followed by the
selected maker's accounts. Existing source imports and credential recovery
SHALL remain available within that selected owner.

#### Scenario: Multiple personal profiles
- WHEN a second personal profile imports AI accounts
- THEN its stable scope is distinct from the original personal account scope.

### Requirement: Portable metadata is reviewed and explicitly exported
The editor SHALL retain a source locator independently from authentication.
Import SHALL validate and review portable metadata. Export SHALL exclude tokens,
credential paths and provider sessions. Browser-connected GitHub/Drive writes
SHALL require explicit confirmation; HTTPS SHALL offer a local export.

#### Scenario: Remote changed during review
- WHEN a remote's reviewed content differs before publication
- THEN export is refused without replacing it.
