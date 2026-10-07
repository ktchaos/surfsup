<!--
Sync Impact Report
- Version change: unratified template → 1.0.0
- Modified principles: none (initial ratification; template placeholders replaced)
  - [PRINCIPLE_1_NAME] → I. Native iOS First
  - [PRINCIPLE_2_NAME] → II. On-Device First
  - [PRINCIPLE_3_NAME] → III. Computer Vision / Domain Separation
- Added sections:
  - Platform Constraints
  - Quality Gates
- Removed sections:
  - Template principle slots IV and V were not adopted; this project
    defines three principles. Stack, architecture, localization, UI
    constants, and reducer tests are rules of Principle I.
- Follow-up TODOs: none
-->

# SurfsUp Constitution

## Core Principles

### I. Native iOS First

SurfsUp is a native iOS application.

- Swift MUST be the primary language.
- SwiftUI MUST be the primary UI framework.
- AVFoundation MUST be responsible for video processing and playback.
- Vision and Core ML MUST be the default technologies for computer vision.
- A third-party framework MUST NOT be introduced unless the spec or plan
  records an explicit justification that first-party frameworks cannot meet
  the requirement.

**SwiftUI + TCA.** Feature UI MUST be built with SwiftUI. Feature state and
behavior MUST use The Composable Architecture: `@Reducer`, `@ObservableState`,
delegate actions, and `@Dependency` clients. A child feature MUST talk to its
parent through a `Delegate` action enum. Side effects such as persistence
MUST be accessed through `@Dependency` clients (for example
`@Dependency(\.persistenceClient)`), and MUST NOT be constructed inside the
reducer.

**Localization completeness.** Every user-facing string MUST exist in all
15 locales (`da`, `de`, `es`, `fr`, `it`, `ja`, `ko`, `nl`, `pl`, `pt`,
`ru`, `sv`, `tr`, `zh-Hans`, `zh-Hant`) inside `Localizable.xcstrings` with
`"state": "translated"`.

**No magic numbers in UI.** Layout, spacing, corner radius, and animation
timing MUST be named constants under `AppConstants.UI`, `Typography`,
`AppColors`, or a feature-scoped `UIConstants.<Feature>` enum.

**Test-first for reducer logic.** Reducer behavior MUST be covered with
Swift Testing and a TCA `TestStore` before or alongside any reducer change.
A reducer change that lands without that test is non-compliant.

Rationale: One native stack, one architecture, and shared localization,
layout, and reducer-test rules keep every later spec, plan, and task
aligned with the same constraints.

### II. On-Device First

Video analysis SHOULD run on-device whenever technically feasible.
The MVP MUST NOT introduce a backend solely to perform computation
that can reasonably run on the device.
Cloud processing MAY be introduced only when a concrete limitation
of on-device processing has been demonstrated and recorded in the spec
or plan.

Rationale: Analysis stays on the device unless a recorded limit shows
that the work cannot reasonably run there.

### III. Computer Vision / Domain Separation

Raw computer vision output MUST remain separate from derived
surf-domain metrics.

- Vision is responsible for detecting observations.
- The biomechanics layer is responsible for interpreting observations.
- Surf event detection is responsible for interpreting biomechanics.

A layer MUST NOT consume or produce another layer's responsibility.
Derived surf metrics MUST NOT be written back into raw vision output.

Rationale: Separate detection, biomechanical interpretation, and surf-event
interpretation keep each layer independently testable.

## Platform Constraints

- Language: Swift.
- UI: SwiftUI.
- Architecture: The Composable Architecture (`@Reducer`, `@ObservableState`,
  `Delegate` actions, `@Dependency` clients).
- Video processing and playback: AVFoundation.
- Computer vision defaults: Vision and Core ML.
- Side effects: `@Dependency` clients.
- Required locales in `Localizable.xcstrings`: `da`, `de`, `es`, `fr`,
  `it`, `ja`, `ko`, `nl`, `pl`, `pt`, `ru`, `sv`, `tr`, `zh-Hans`,
  `zh-Hant`, each with `"state": "translated"`.

## Quality Gates

Specs, plans, tasks, and pull requests MUST show compliance with this
constitution:

- Third-party frameworks include a written justification.
- Every user-facing string is present for all 15 locales in
  `Localizable.xcstrings` with `"state": "translated"`.
- Layout, spacing, corner radius, and animation timing use named constants
  under `AppConstants.UI`, `Typography`, `AppColors`, or
  `UIConstants.<Feature>`.
- Reducer changes include Swift Testing coverage through `TestStore`
  in the same change.
- A new backend or cloud computation states the demonstrated on-device
  limitation it exists to overcome.
- Vision observations, biomechanics interpretation, and surf-event
  detection stay in separate layers.

## Governance

This constitution supersedes conflicting practice. Amendments MUST be made
in this file, state the semantic version bump, and set the last-amended
date. Version bumps follow:

- MAJOR: backward-incompatible removal or redefinition of a principle.
- MINOR: a new principle or section, or a material expansion of guidance.
- PATCH: clarification, wording, or other non-semantic refinement.

Compliance is reviewed when a spec, plan, or implementation is produced,
and again in pull-request review. Cursor rules that restate these
principles, including localization completeness, MUST stay consistent with
this constitution. On conflict, this constitution wins.

**Version**: 1.0.0 | **Ratified**: 2026-10-07 | **Last Amended**: 2026-10-07
