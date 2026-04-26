# 4. Maintenance posture

Date: 2026-04-27

## Status

Accepted (with TODO numbers — to be filled before v0.1.0 release per
collective decision).

## Context

`bayesreml` is an AAGI-AUS collective effort. CRAN's *Repository
Policy* requires that a package have a responsive maintainer; the
AAGI preset audit (`presets/aagi.yml`, mandatory-uplift v0.4.1, item
S5) requires that maintenance capacity be **disclosed honestly** in
`SUPPORT.md` so that users can calibrate expectations.

A pattern across academic / institutional R packages is the silent
abandonment of maintenance — packages remain on CRAN, accumulate
issues, fall out of compatibility with their dependencies, and
eventually get archived. The honest mitigation is to declare the
maintenance budget up-front, plus an explicit abandonment protocol.

## Decision

Maintenance posture is documented and committed-to in two places:

1. **`SUPPORT.md`** — user-facing capacity block: primary maintainer,
   bus factor, weekly maintenance hours, issue-response SLA, critical
   security SLA, abandonment protocol.
2. **`API_STABILITY.md`** — developer-facing stability ladder per
   export with promotion / deprecation policy.

The capacity-block fields below are placeholders; concrete numbers
land before v0.1.0 release per collective decision.

| Field | Current value | Target value (v0.1.0) |
|---|---|---|
| Primary maintainer | Max Moldovan | Max Moldovan |
| Bus factor | TODO | ≥ 2 (Max + one of {Emi Tanaka, Francis K.C. Hui, Beata Sznajder}) |
| Weekly maintenance hours | TODO | Honest median across recent quarters; not aspirational |
| Issue response SLA — bug | TODO | First response within 7 business days |
| Issue response SLA — feature | TODO | First response within 14 business days |
| Critical security SLA | 7 days | 7 days (frozen — see `SECURITY.md`) |
| Abandonment protocol | TODO | Hand-off to a named successor within AAGI-AUS or transfer to a community fork; archive notification on the README + CRAN withdrawal if no successor |

## Alternatives considered

- **Aspirational SLAs.** Rejected: an unmet SLA is worse than no
  SLA. The capacity block must reflect what the maintainer can
  *honestly* do given competing institutional commitments.
- **No maintenance disclosure.** Rejected: AAGI preset S5 requires
  it; users have a right to calibrate expectations before adopting
  the package in publication-track work.
- **Single SLA across bug / feature.** Rejected: bugs are reactive
  and have a shorter natural cycle; features are scoped against the
  v0.1 / v0.2 / v0.3 trajectory and have a longer planning horizon.

## Consequences

- Users see, before depending on the package, what response speed to
  expect.
- The TODO entries in this ADR mirror those in `SUPPORT.md` exactly;
  filling one fills the other (per release-rehearsal checklist).
- The abandonment protocol is binding: if maintenance capacity falls
  to zero, the README + CRAN withdrawal procedure fires. Users
  pinning to a specific 0.1.x patch via `renv::snapshot()` will keep
  working in a withdrawn-package world.

## Cite-trail

- AAGI preset audit `presets/aagi.yml`, mandatory-uplift v0.4.1,
  item S5.
- `/rpkg` audit recipe 31 ("SUPPORT.md with maintenance-capacity
  block").
- CRAN Repository Policy, *Maintainer responsibilities* section.
