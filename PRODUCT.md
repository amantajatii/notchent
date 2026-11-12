# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

> Inferred: Notchent is a native macOS 14+ SwiftUI app, but its visual language deliberately follows the iPhone Dynamic Island / Live Activities idiom (the owner's references). `ios` is recorded so Apple HIG guidance applies; the shipping target is macOS.

## Users

Inferred (owner did not answer the interview; confirm when convenient): a developer on a notched Mac who runs coding agents (Codex CLI/desktop, Claude Code) and wants to keep an eye on them without switching windows.

## Product Purpose

A notch companion that surfaces agent activity at a glance: answer Codex questions and approvals, continue a Codex conversation, see remaining Codex and Claude plan limits, plus supporting modules for Spotify now playing, a file shelf, and an integrated terminal. Success: the user glances at the notch and knows what their agents and limits are doing, and can act in one click.

## Positioning

Inferred: agent control from the notch (answer prompts, queue chat, plan usage) rather than a general notch utility.

## Operating Context

- Lives in the notch area; opens on hover at the top-centre of the screen, hides when idle.
- Always dark; content sits on a black surface attached to the notch.
- Used in short glances between coding work; must be readable in under a second.

## Capabilities and Constraints

- macOS 14+, SwiftUI, Swift 6; no SwiftUI macro plugin in the local toolchain (`@State` is spelled through the `PromptState` alias).
- Localized English and Bahasa Indonesia (`Localizable.xcstrings`); terminal text, filenames, and agent content are not translated.
- Codex integration via the local app-server daemon; Claude limits only via the documented status line `rate_limits`.
- Distributed as an ad-hoc signed app from GitHub Releases with an in-app updater; not notarized.

## Brand Commitments

- Name: Notchent ("Notch for Agent").
- Owner direction: should feel like Apple's own Dynamic Island / Live Activities, not generic "AI" styling (no decorative purple/cyan/pink palettes).

## Evidence on Hand

- README.md and docs/validation/*.md describe verified and unverified capabilities honestly; future copy must not overstate support.
- No logo, app icon, testimonials, or metrics exist; do not invent them.

## Product Principles

1. Glance first: the most important number or state is the largest thing on screen.
2. Act in place: answering an agent never requires leaving the notch.
3. Honest status: never present stale or unverified data as current.
4. Quiet by default: colour and motion appear only when they carry meaning.

## Accessibility & Inclusion

Respect Reduce Motion and VoiceOver labels; keep contrast high on the black surface.
