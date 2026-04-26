# 1. Record architecture decisions

Date: 2026-04-27

## Status

Accepted.

## Context

`bayesreml` is evolving from an ASReml-syntax-to-greta translator
(v0.1.0 baseline) into a multi-backend Bayesian framework with
cross-engine triangulation as the signature output (Variant D
trajectory, AAGI-AUS collective). Significant architecture decisions
will accumulate across the v0.1 → v1.0 path: backend additions
(greta → gretaR, NIMBLE, JAGS, PyMC tier), DSL extensions
(`fb_prior()` v0.2 surface, restricted-grammar LaTeX layer), class-
system migration (S3 → potentially S7 at v1.0), and dispatch /
capability-gating policy changes.

A future maintainer joining the project should be able to read the
chronology of those decisions, including the rationale and the
alternatives that were considered and rejected. Conventional
project-log entries (`PROJECT_LOG.md`) capture *what* changed; they
do not always capture *why* a particular path was chosen over
another. ADRs fill that gap.

## Decision

We will record significant architecture decisions in this directory
(`docs/adr/`), one decision per file, using Michael Nygard's
[Architecture Decision Record (ADR)](https://github.com/joelparkerhenderson/architecture-decision-record)
format adapted for R-package work:

- Numbered file names (`NNNN-kebab-case-title.md`) starting at 0001.
- Sections: **Status**, **Context**, **Decision**, **Consequences**.
- Optional sections: **Alternatives considered**, **Cite-trail**.
- Status transitions are explicit: Proposed → Accepted → Superseded
  by ADR-NNNN. Accepted ADRs are not edited; superseded decisions
  remain in place with a "Superseded by" annotation pointing forward.

## Consequences

- New maintainers can read the architecture trail chronologically.
- Decisions that turn out to be wrong are not deleted; they are
  superseded by a new ADR that names the prior one.
- The ADR set is shipped under `docs/` (excluded from the package
  tarball via `.Rbuildignore`) and rendered in the pkgdown site under
  Articles → Architecture decisions when pkgdown is deployed.
- ADRs are not a substitute for `NEWS.md` (user-facing changelog) or
  `PROJECT_LOG.md` (working notes); they sit one layer deeper —
  closer to the rationale than the changelog and closer to the
  external interface than the project log.

## Cite-trail

- Nygard, M. (2011). *Documenting Architecture Decisions*.
  <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- AAGI-AUS `/rpkg` audit preset S3 (mandatory uplift v0.4.1):
  ADR set under `docs/adr/`.
