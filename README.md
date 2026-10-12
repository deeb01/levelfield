# levelfield

levelfield checks that the methods in a benchmark comparison ran with the
settings you think they did. It records the arguments each method actually
passed to the functions doing the work, compares them across methods, checks
each method against its own tuning results, and measures how much choosing
settings on the test data inflates a result. It works on benchmark code written
as plain R functions, with no framework to adopt.

It applies to any comparison of methods in R: models of any kind, solvers,
simulation studies. Only `origin_windows()` is specific to time series.

## Why it exists

A benchmark comparison is only as fair as the settings each method ran with, and
those settings can go wrong without any error. Here is a baseline from a
benchmark script:

```r
baseline <- function(y, lambda = 0.001) {
  ridge_forecast(y, h, K = 2)
}
```

The wrapper accepts the penalty tuned for the baseline and never passes it on,
so `ridge_forecast` silently uses its own default. In a simulation with 40
series, that one missing argument makes a new method look like a clear winner:

| | Baseline minus new method (MAE) | Paired t | New method better on |
|---|---|---|---|
| As written | +0.871 | 5.57 | 37 of 40 series |
| `lambda` passed through | −0.005 | −1.39 | 14 of 40 series |

The new method's whole advantage came from the baseline's bug.

levelfield came out of a forecasting research project where bugs of this kind
were the most common defect we found: a benchmark function that passed a setting
to some methods and not to others, a default that was broken in every method at
once, a setting chosen on the same data it was scored on. Each was found by hand,
and some only after the result had been quoted. Reading the code does not
reliably catch them, because the code shows what its author intended rather than
what ran. In a recent study, the best AI auditor reached an AUROC of 0.77 at
finding deliberately altered hyperparameters in machine-learning research code,
and AI-assisted human reviewers also struggled
([Gan et al., 2026](https://arxiv.org/abs/2604.16286)).

The problems themselves are well known. Under-tuned baselines are a documented
issue in machine-learning research
([Ferrari Dacrema et al., 2019](https://arxiv.org/abs/1911.07698)), and choosing
settings on the test data biases results by as much as the differences between
the methods being compared
([Cawley and Talbot, 2010](https://www.jmlr.org/papers/v11/cawley10a.html)).
Frameworks such as [mlr3](https://mlr3tuning.mlr-org.com) avoid both when the
benchmark is built inside the framework. We found no tool that checks a
benchmark written as an ordinary script, which is how most research benchmarks
are written.

## What it checks

| Function | What it does |
|---|---|
| `trace_args()` | Runs each method with chosen functions traced, and records every argument each call received, including defaults nobody wrote |
| `arg_diffs()` | Lists the settings that differ between methods, and flags any argument one method passed while another fell back to the default |
| `audit_args()` | Compares each method's settings with a recorded tuning sweep, and reports methods running away from their own best and what that costs |
| `nested_select()` | Chooses a setting on a selection set, scores it on a separate evaluation set, and reports how much choosing on the evaluation set itself would have inflated the result |
| `origin_windows()` | For time series: builds a selection window and an evaluation window, the first ending where the second begins |

`arg_diffs()` and `audit_args()` catch different problems. Comparing the methods'
settings with each other finds settings that differ. It cannot find a setting
that is the same in every method and wrong for all of them; checking each method
against its own tuning results can.

## Install

```r
# install.packages("remotes")
remotes::install_github("deeb01/levelfield")
```

## Example

[`demo/demo.R`](demo/demo.R) runs the comparison above and reproduces every
number on this page. It is a forecasting benchmark, but the functions work the
same way on any kind of model. Tracing both methods shows the cause:

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

`K` differs on purpose: it is what the comparison is about. `lambda` differs by
accident, and `fell_to_default = TRUE` shows how: one method passed it and the
other received the function's default.

Given a recorded sweep of the baseline's `lambda`, `audit_args()` shows the
baseline running away from its own best value and prices the gap:

```
      arm    arg used  best      cost        t      verdict
 baseline lambda    1 1e-04 0.5842092 2.982022 OFF ITS BEST
 baseline      K    2     2 0.0000000       NA  at its best
```

In the same demo, `nested_select()` finds that choosing `lambda` on the window
before the test period picks the same value as the test period itself would, so
the inflation is zero. On real data it often is not. For data without a time
order, the selection and evaluation sets are an ordinary validation and test
split.

## How it is tested

Every test plants the bug it checks for, and each was seen to fail before it was
trusted to pass. That rule came from experience: the first version of the
tracer worked in a prototype and failed every test once it was inside a
package, because the prototype had only worked by accident.

## Limits

- Tracing sees functions called by name. A copy captured into another variable
  before tracing, or a second definition that shadows the traced one, is not
  seen.
- Passed arguments are evaluated when the call begins, earlier than a lazily
  evaluating function would evaluate them. Defaults are recorded as written in
  the function's definition, without being evaluated, except that a default
  passed to `match.arg()` is recorded as the value `match.arg()` chooses.
- `audit_args()` knows only what a sweep measured. A setting no sweep covered
  does not appear, and a sweep's best value holds only under the settings that
  sweep held fixed. When a method used a value of another swept setting that the
  sweep never recorded, the row says so in `not_held`, and `nearest = TRUE`
  holds that setting at the nearest recorded value instead.

## Licence

MIT
