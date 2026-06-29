## run_all.R -- battery driver: run each card bench, then the smoke profile.
## Run from report/ AFTER sourcing the engine (build.R does this), or:
##   Rscript build.R bench
for (b in c(
  "bench/fb-correctness.R",
  "bench/fb-inla-correctness.R",
  "bench/fb-greta-correctness.R",
  NULL)) if (!is.null(b)) { cat("bench:", b, "\n"); source(b) }
source("bench/contract-smoke.R")
