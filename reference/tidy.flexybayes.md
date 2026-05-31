# Tidy a flexybayes model

Returns a tidy data frame of fixed effect estimates with posterior
statistics.

## Usage

``` r
tidy.flexybayes(
  x,
  conf.int = TRUE,
  conf.level = 0.95,
  effects = c("fixed", "random"),
  ...
)
```

## Arguments

- x:

  A flexybayes object

- conf.int:

  Logical: include credible intervals?

- conf.level:

  Credible level (default 0.95)

- effects:

  Which effects to return: `"fixed"` or `"random"`

- ...:

  Additional arguments (ignored)

## Value

A data frame with columns: term, estimate, std.error, conf.low,
conf.high
