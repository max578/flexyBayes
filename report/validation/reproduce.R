#!/usr/bin/env Rscript
## reproduce.R -- regenerate every reported card result from scratch.
## Run from this report/ directory:  Rscript reproduce.R
##
## Requires flexyBayes (../flexyBayes) plus any competitor packages named in the benches.
## Each card benchmark is self-contained -- it load_all()s flexyBayes and runs any
## competitor in an isolated session on identical, seeded data -- and writes the
## cache the document reads, so every reported number can be checked against
## bench/results/. The argument-wide conformance sweep is driven by the
## /validation engine; run it with `Rscript build.R bench`.
benches <- c(
  "bench/fb-correctness.R",
  "bench/fb-inla-correctness.R",
  "bench/fb-greta-correctness.R"
)
for (b in benches) { cat("\n== ", b, " ==\n", sep = ""); source(b) }
cat("\nDone. Cached results are in bench/results/; the documents read them.\n")
