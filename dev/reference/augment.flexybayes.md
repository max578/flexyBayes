# Augment a flexybayes model

Returns the original data with fitted values, residuals, and other
observation-level statistics.

## Usage

``` r
augment.flexybayes(x, data = NULL, ...)
```

## Arguments

- x:

  A flexybayes object

- data:

  Optional data frame (defaults to original data)

- ...:

  Additional arguments (ignored)

## Value

A data frame with added columns: .fitted, .resid
