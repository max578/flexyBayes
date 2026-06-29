## Instance setup hook (sourced by the engine after pv_root is defined).
## Loads the package under study so card code chunks are runnable.
suppressMessages(
  devtools::load_all(normalizePath(file.path(pv_root, "..", "..", "flexyBayes")),
                     quiet = TRUE)
)
