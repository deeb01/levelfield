# The settings your benchmark actually ran

A benchmark comparison is only as fair as the settings each method ran with.
Those settings are written in the code, and the code is usually right. What
goes wrong is the path from the code to the method.

Here is a small case. Two ridge forecasters are compared on forty simulated
daily series: a new method with three weekly harmonics, and a baseline with
two. The new method wins by 0.87 in mean absolute error, paired t 5.6, on 37 of
40 series. The baseline's wrapper takes a `lambda` argument with the right
value and never passes it on, so the baseline runs at the forecaster's default
penalty. Forward the argument and the difference becomes −0.005, paired t −1.4.
The new method's advantage was the baseline's handicap.

The code reads correctly. The wrapper's signature shows the intended `lambda`,
and so would a configuration table built from the signatures. The value the
forecaster received exists only while the code runs.

## How often this happens

In a research project on hierarchical forecasting, this was the defect we hit
most often: two methods differed in something other than what the comparison
was about. It took several forms. A benchmark function forwarded the
changepoint count to some methods and not to others, which fell through to
their own defaults; after that was fixed, the same omission turned up in the
methods the fix had not reached. A default estimator turned out to be
degenerate, landing on one end of its range or the other, and every method
using it was handicapped identically. We found each instance by hand, and
several only after a number had been quoted.

Reading the code is a weak defence. Gan et al. (2026) planted
implementation-level sabotage, including changed hyperparameters, in nine ML
research codebases. The best automated auditor reached an AUROC of 0.77, and
LLM-assisted human auditors also struggled to detect and fix the changes. When
the defect is a value that never arrives, the code shows what its author
intended.

## Four rules

Each came from a specific incident.

**Read the settings from the run.** Trace the functions that do the work, and
record every argument each call received, including the defaults nobody wrote.
Then list the settings that differ between methods. Each difference is either
the subject of the comparison or a confound, and only the person running the
comparison can say which. In the example, the trace shows `K` differing by
design and `lambda` differing because one method supplied it and the other
received the default.

**A handicap is not a difference.** Comparing methods' settings with each other
finds settings that vary. It cannot find a setting that is the same in every
method and wrong for all of them, which is what the degenerate estimator was.
That needs a per-method check against evidence: given a recorded sweep, is each
method at its own measured best, and what does the gap cost? Sweeps of several
settings at once need care here. The best value of one setting depends on the
others, and has to be read with the others held at the values the method used.
Averaging over them answers a different question, and gave us a false alarm.

**Do not choose a setting on the data you report.** Choosing the best of
several settings by its score on the evaluation data, then reporting that
score, reports a maximum over noisy estimates. Cawley and Talbot (2010) found
the resulting bias is "often of comparable magnitude to differences in
performance between learning algorithms." It also breaks comparisons: a setting
chosen by looking at the evaluation data cannot be compared fairly with one
chosen by a procedure that never saw it, such as cross-validation on training
data. We retracted a claim on this ground. A penalty constant chosen on the
last 28 days of each series appeared to beat adaptive selection, and it had
been chosen on the days it was scored on. For a time series the fix is a second
window: select on the horizon before the evaluation window, score on the
evaluation window, and report how much the oracle choice would have overstated.

**A green check is not evidence the check works.** A guard against committing
confidential data printed "must not be committed" next to offending files and
exited with status 0. Its failure flag was set inside a `while` loop on the
right of a pipe, which runs in a subshell, and the assignment was lost when the
subshell ended. Building the tracer for the package below produced a smaller
version of the same failure: the prototype worked because its tracer happened
to live in R's global environment, where every lookup ends; inside a package it
found nothing, and every tracing test failed. A guard should ship with a
planted violation it must refuse.

## levelfield

[levelfield](https://github.com/deeb01/levelfield) implements the first three
rules for benchmark code written as plain R functions. `trace_args()` and
`arg_diffs()` read settings from the run; `audit_args()` checks each method
against recorded tuning results; `nested_select()` selects on an earlier window
and reports the optimism. Every test in the package plants the defect it checks
for. The example above is the package's demonstration script, and reproduces
every number quoted here.

The ideas are established. Under-tuned baselines are documented (Ferrari
Dacrema, Cremonesi and Jannach, 2019), and so is selection optimism.
mlr3tuning gives correct nested comparisons for benchmarks built within mlr3.
We did not find a tool that checks a benchmark written outside a framework,
which describes most research code.

The tracing has limits. It sees functions called by name, so a copy captured
into another variable before tracing is invisible. It evaluates passed
arguments when the call begins, earlier than a lazily evaluating function
would. And `audit_args()` knows only what a sweep measured: a setting no sweep
covered does not appear.

## References

- Cawley, G. C. and Talbot, N. L. C. (2010). On over-fitting in model selection
  and subsequent selection bias in performance evaluation. *Journal of Machine
  Learning Research* 11(70), 2079–2107.
- Ferrari Dacrema, M., Cremonesi, P. and Jannach, D. (2019). Are we really
  making much progress? A worrying analysis of recent neural recommendation
  approaches. *RecSys '19*.
- Gan, E., Bhatt, A., Shlegeris, B., Stastny, J. and Hebbar, V. (2026).
  Auditing Sabotage Bench: a benchmark for detecting and fixing research
  sabotage in ML codebases. arXiv:2604.16286.
