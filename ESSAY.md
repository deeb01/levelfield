# Is your baseline running the settings you think it is?

Here is a baseline from a benchmark script:

```r
baseline <- function(y, lambda = 0.001) {
  ridge_forecast(y, h, K = 2)
}
```

`ridge_forecast` fits a penalised regression and forecasts `h` days ahead, and
`lambda` is its penalty. The wrapper accepts the penalty you tuned for the
baseline and then never passes it on, so `ridge_forecast` quietly uses its own
default instead. Nothing errors, and the numbers look normal.

In a small simulation with 40 series, that one missing argument is enough to
make a competing method look like a clear winner: it beats this baseline on 37
of the 40 series, with a paired t-statistic of 5.6. Pass `lambda` through and
the advantage disappears. The whole difference came from the baseline's bug.

## We kept making this mistake

This isn't hypothetical for us. In a research project comparing ways of
forecasting many related time series at once, this family of bug was the one we
hit most often. The details varied. One benchmark function passed the number of
trend changepoints to some methods but not to others, which silently used their
own defaults. When we fixed it, the same omission turned up again in the
methods the fix had missed. Another time, a default setting turned out to be
broken in every method at once, so comparing the methods' settings against each
other showed nothing wrong. We found each problem by hand, and more than once
only after we had started quoting the result.

Careful code review doesn't reliably catch this kind of bug. In a
[recent study](https://arxiv.org/abs/2604.16286), researchers deliberately
planted changes such as altered hyperparameters into nine machine-learning
research codebases, then asked AI models and AI-assisted human reviewers to find
them. The best model reached an AUROC of 0.77, and the human reviewers also
struggled. The code shows what its author intended; the bug is in what actually
happens when it runs.

## Three checks

So we stopped trusting our reading of the code, and started checking benchmarks
the way we would check any other result.

**Look at what each method actually received.** Instead of reading the
configuration, record it while the benchmark runs: trace the functions that do
the work, and log every argument each call receives, including the defaults
nobody typed. Then list where the methods differ. Some differences are the point
of the comparison. Others are accidents, and the most common accident has a
recognisable shape: one method passed an argument and another got the default.

**Check each method against its own best settings.** Comparing methods side by
side only catches settings that differ between them. If every method shares the
same bad default, they all look consistent and the comparison comes up clean.
Catching that takes evidence about each method's best settings, usually a
tuning sweep you have already run, and a check of each method's actual settings
against it.

**Don't tune on the data you report.** If you try several settings, keep the one
that scores best on your test data, and report that score, you are reporting the
luckiest of several noisy numbers.
[Cawley and Talbot](https://www.jmlr.org/papers/v11/cawley10a.html) showed in
2010 that this bias is often as large as the differences between the methods
being compared. It also makes comparisons unfair in a quieter way: a setting
picked by looking at the test data can't be fairly compared with one picked by a
procedure that never saw it. We retracted one of our own conclusions over
exactly this. For time series the fix is simple: choose settings on the stretch
of data just before the test period, then score on the test period.

## levelfield

We packaged the three checks as a small R package,
[levelfield](https://github.com/deeb01/levelfield). It works on benchmark code
written as ordinary R functions, with no framework to adopt. `trace_args()` and
`arg_diffs()` record and compare what each method received, `audit_args()`
checks each method against a tuning sweep, and `nested_select()` handles tuning
for time series. The example at the top of this post is the package's demo, and
the README walks through it step by step.

The ideas themselves are not new. Under-tuned baselines are a
[documented problem](https://arxiv.org/abs/1911.07698) in machine-learning
research, and frameworks such as [mlr3](https://mlr3tuning.mlr-org.com) handle
tuning correctly when you build your benchmark inside them. What we couldn't find
was a tool that checks the kind of benchmark most of us actually write: a script
full of plain functions.

## Test the checks too

Our project had a script meant to stop confidential files from being committed.
It printed "must not be committed" next to each offending file, and then
reported that everything was clean. A shell-scripting mistake meant the failure
was never recorded. We noticed only because the output contradicted itself.

Building levelfield taught us the same lesson on a smaller scale. Our prototype
worked, and the same code failed every test once it was inside a package,
because the prototype had only worked by accident. So every test in levelfield
now plants the bug it is meant to catch, and we watched each one fail before
trusting it to pass.
