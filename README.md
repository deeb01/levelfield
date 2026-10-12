# levelfield

Check that the methods in a benchmark comparison ran on equal footing before
reading the comparison.

A benchmark compares methods, and the comparison is only as sound as the
settings each method actually ran with. Those settings are easy to get wrong
silently: a wrapper accepts an argument and never forwards it, a default
changes, a baseline is tuned less carefully than the new method. The numbers
still come out, and they still look like results.

levelfield checks a benchmark written as plain R functions. It needs no
modelling framework and no changes to the code being checked.

| function | question it answers |
|---|---|
| `trace_args()` | What arguments did each method actually pass, defaults included? |
| `arg_diffs()` | Which settings differ between methods? |
| `audit_args()` | Is each method running at its own measured best? |
| `nested_select()` | What does choosing a setting on the data it is scored on overstate? |
| `origin_windows()` | Selection and evaluation windows for a time series |

## Install

```r
# install.packages("remotes")
remotes::install_github("deeb01/levelfield")
```

## A worked example

The full script is [`demo/demo.R`](demo/demo.R). It simulates 40 daily series
and compares two ridge forecasters: a new method with three weekly harmonics,
and a baseline with two. The baseline's wrapper takes a `lambda` argument and
does not forward it, so the baseline runs at the forecaster's default.

```r
new_method <- function(y) ridge_forecast(y, h, lambda = 0.001, K = 3)
baseline   <- function(y, lambda = 0.001) ridge_forecast(y, h, K = 2)
```

**The comparison as run** favours the new method decisively:

```
baseline minus new method: +0.871 MAE (paired t 5.57), new method better on 37 of 40 series
```

**What each method actually passed.** `trace_args()` runs both methods with
`ridge_forecast` traced, and `arg_diffs()` reports where they differ:

```r
tr <- trace_args(list(new      = function() new_method(y),
                      baseline = function() baseline(y)),
                 "ridge_forecast")
arg_diffs(tr, ignore = c("y", "h"))
```
```
              fn    arg                    values fell_to_default
1 ridge_forecast lambda baseline = 1; new = 0.001            TRUE
2 ridge_forecast      K     baseline = 2; new = 3           FALSE
```

`K` differs by design; it is what the comparison is about. `lambda` differs by
accident, and `fell_to_default = TRUE` says how: one method supplied it and the
other received the function's default.

**Is each method at its own best?** Given a recorded sweep of the baseline's
`lambda`, `audit_args()` compares the value each method used with the value the
sweep measures as best, and prices the gap from paired differences:

```r
audit_args(tr, sweep)
```
```
      arm    arg used  best      cost        t      verdict
 baseline lambda    1 1e-04 0.5842092 2.982022 OFF ITS BEST
 baseline      K    2     2 0.0000000       NA  at its best
```

`arg_diffs()` and `audit_args()` catch different defects. A setting can differ
between methods legitimately, because each is at its own optimum; and a
setting can be identical in every method and wrong for all of them, which
`arg_diffs()` cannot see.

**The comparison with the argument forwarded:**

```
baseline minus new method: -0.005 MAE (paired t -1.39), new method better on 14 of 40 series
```

The new method's advantage was the baseline's handicap.

**Choosing a setting without seeing the evaluation window.** `nested_select()`
picks a value on a selection window one horizon before the evaluation window,
then compares it with the *oracle*, the value that looking at the evaluation
window would have picked:

```
<levelfield_select> chose 1e-04 on the selection window; the oracle is 1e-04
  selection agrees with the oracle: optimism 0
```

On this simulated panel the choice transfers and the optimism is zero. On real
data it often does not: Cawley and Talbot (2010) found the optimism of
selection can rival the differences between the methods being compared.

## Scope

- **Tracing finds what was called by name.** A function is traced in the
  environment that holds it. A copy captured into another variable before
  tracing, or a second definition shadowing the traced one, is not seen. An arm
  that makes no traced call appears in no row.
- **Passed arguments are evaluated at the start of the call**, earlier than a
  lazily evaluating function would. Defaults are not evaluated; they are
  recorded as the expression in the formals.
- **`audit_args()` knows only what the evidence measured.** A setting no sweep
  covered does not appear, and a sweep's best holds only under the settings
  that sweep held fixed.

## Related work

The failures this package checks for are well documented; tooling that checks
for them in ordinary benchmark code is what it adds.

- Under-tuned baselines: Ferrari Dacrema, Cremonesi and Jannach (2019), *Are we
  really making much progress?* RecSys.
- Selection optimism: Cawley and Talbot (2010), *On over-fitting in model
  selection and subsequent selection bias in performance evaluation*, JMLR 11.
- [mlr3tuning](https://mlr3tuning.mlr-org.com) gives nested, paired comparisons
  for benchmarks built within mlr3. levelfield checks benchmarks that were not.

## Licence

MIT
