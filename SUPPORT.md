# Getting help with flexyBayes

Thanks for using `flexyBayes`. The fastest path to a useful answer
depends on what kind of question you have.

## Where to ask

| Question type | Where |
|---|---|
| "How do I do X with flexyBayes?" | [GitHub Discussions — Q&A](https://github.com/AAGI-AUS/flexyBayes/discussions/categories/q-a) |
| "I think this is a bug." | [GitHub Issues — bug report](https://github.com/AAGI-AUS/flexyBayes/issues/new?template=bug_report.yml) — please include a [reprex](https://reprex.tidyverse.org). |
| "I'd like a new feature / backend / capability." | [GitHub Issues — feature request](https://github.com/AAGI-AUS/flexyBayes/issues/new?template=feature_request.yml) |
| Security-sensitive disclosure | See [`SECURITY.md`](SECURITY.md) — please do **not** open a public issue. |
| General Bayesian-mixed-model methodology | [Stan Forums](https://discourse.mc-stan.org/) or [INLA mailing list](https://www.r-inla.org/contact-us) — broader and more active than this project. |

## Maintenance capacity

`flexyBayes` is maintained by a small team within the Australian
Agricultural Genomics Institute (AAGI-AUS) collective. The capacity
block below is updated alongside each release.

> **TODO (Max + collective):** fill in concrete numbers before v0.1.0.
> Honest, not aspirational. Per audit AAGI preset S5 the entries
> below are *placeholders* and must be replaced before this file
> ships at release.

| Field | Current value | Notes |
|---|---|---|
| Primary maintainer | Max Moldovan | Adelaide University; contact via package author email. |
| Bus factor | TODO | Number of contributors who can land a release without external help. |
| Weekly maintenance hours | TODO | Honest median across recent quarters. |
| Issue response SLA | TODO | E.g., "first response within 7 business days for bug reports." |
| Critical security SLA | 7 days | See [`SECURITY.md`](SECURITY.md). |
| Abandonment protocol | TODO | What happens if maintainers can no longer maintain — handover plan, archive plan, or hand-off to an institutional successor. |

## Reprex etiquette

A reproducible example (reprex) lets us help you in one round-trip
instead of three. The minimum:

1. A small `data.frame` we can copy-paste.
2. The exact `flexybayes()` / `fb()` call.
3. The full output of `sessionInfo()` — especially the greta /
   TensorFlow / INLA versions.
4. The error / unexpected output, copied verbatim.

For runtime issues, please run with `verbose = TRUE` and include the
emitted greta code (or, for `backend = "inla"`, the printed INLA
formula).

## What we cannot help with

- General R help — see [Stack Overflow `[r]`](https://stackoverflow.com/questions/tagged/r).
- ASReml-R proprietary syntax outside the subset that `flexyBayes`
  implements — see VSNi support.
- INLA model-tuning beyond the `lgm_gate()` / `priors_to_inla()`
  surface — see [r-inla.org](https://www.r-inla.org/).
- greta's own Python / TensorFlow installation — see
  [greta-stats.org](https://greta-stats.org).
