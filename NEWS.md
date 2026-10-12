# levelfield 0.1.1

Four defects found by the first real use of the package, in the research
harness of the sennit forecasting package. Each has a test that fails on 0.1.0.

* `trace_args()` returned an empty trace, with no warning, for a package loaded
  with `pkgload::load_all()`. It traced only the attached copy of the function,
  which R carries into the namespace only when the attached binding is locked;
  `library()` locks it and `load_all()` does not. The namespace and the attached
  copy are now traced separately.
* `trace_args()` now warns when an arm makes no call to a traced function, and
  lists such arms in the `"untraced"` attribute. An empty trace reads like "the
  methods agree".
* `audit_args()` crashed when a swept setting had an `NA` level, as sweeps often
  record a switched-off component. `NA` is now a level of its own, and the
  summary statistic receives finite scores only.
* `audit_args()` averaged silently over another swept setting when the method's
  value for it was absent from the evidence. Such rows now list the setting in a
  new `not_held` column, with a warning, and `nearest = TRUE` holds a numeric
  setting at the nearest recorded value instead.
* `trace_args()` records a default passed to `match.arg()`, such as
  `c("auto", "dense", "sparse")`, as the value `match.arg()` chooses, so it can
  match evidence recorded as that value.

# levelfield 0.1.0

First release.
