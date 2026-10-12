# Each test plants the defect the function exists to catch. A check that has
# never been seen to fail on the bug it guards against has not been tested.

fit_lf <- function(y, lambda = 1, K = 2L, verbose) sum(y) / (1 + lambda) + K

test_that("records passed values and the defaults the caller never wrote", {
  tr <- trace_args(list(a = function() fit_lf(1:3, lambda = 0.1),
                        b = function() fit_lf(1:3)), "fit_lf")
  get <- function(arm, arg) tr[tr$arm == arm & tr$arg == arg, ]
  expect_equal(get("a", "lambda")$value, "0.1")
  expect_equal(get("a", "lambda")$source, "passed")
  expect_equal(get("b", "lambda")$value, "1")
  expect_equal(get("b", "lambda")$source, "default")
  expect_equal(get("b", "verbose")$source, "missing")
})

test_that("finds a wrapper that fails to forward an argument", {
  # the planted defect: the baseline's wrapper accepts lambda and drops it
  baseline <- function(y, lambda = 0.1) fit_lf(y)
  tr <- trace_args(list(new = function() fit_lf(1:5, lambda = 0.1),
                        old = function() baseline(1:5, lambda = 0.1)), "fit_lf")
  d <- arg_diffs(tr, ignore = "y")
  expect_equal(d$arg, "lambda")
  expect_true(d$fell_to_default)
  expect_match(d$values, "old = 1")
})

test_that("reports nothing when the arms agree", {
  tr <- trace_args(list(a = function() fit_lf(1:3, lambda = 2),
                        b = function() fit_lf(4:6, lambda = 2)), "fit_lf")
  expect_equal(nrow(arg_diffs(tr, ignore = "y")), 0L)
})

test_that("labels each traced function correctly when several are traced", {
  # a closure built in a loop captures the loop variable, so without force()
  # every call is labelled with the last function traced
  other_lf <- function(x, alpha = 5) x * alpha
  tr <- trace_args(list(a = function() { fit_lf(1); other_lf(1) }),
                   c("fit_lf", "other_lf"))
  expect_setequal(unique(tr$fn), c("fit_lf", "other_lf"))
  expect_equal(tr$value[tr$fn == "other_lf" & tr$arg == "alpha"], "5")
  expect_false("alpha" %in% tr$arg[tr$fn == "fit_lf"])
})

test_that("traces a package function whether called through :: or the attached copy", {
  tr <- trace_args(list(qualified = function() stats::median(c(1, 2, NA), na.rm = TRUE),
                        attached  = function() median(c(1, 2, 3))), "stats::median")
  expect_setequal(unique(tr$arm), c("qualified", "attached"))
  expect_equal(tr$value[tr$arm == "qualified" & tr$arg == "na.rm"], "TRUE")
  expect_equal(tr$value[tr$arm == "attached" & tr$arg == "na.rm"], "FALSE")
})

test_that("restores every traced function, including after an arm errors", {
  expect_warning(
    tr <- trace_args(list(ok = function() fit_lf(1),
                          bad = function() stop("arm failed")), "fit_lf"),
    "raised an error")
  expect_equal(unname(attr(tr, "errors")["bad"]), "arm failed")
  expect_false(inherits(fit_lf, "functionWithTrace"))
  expect_false(inherits(stats::median, "functionWithTrace"))
})

test_that("does not force defaults, which may refer to the body's own variables", {
  late <- function(x, n = length(z)) { z <- x * 2; n }
  res <- NULL
  expect_silent(tr <- trace_args(list(a = function() res <<- late(1:4)), "late"))
  expect_equal(res, 4L)
  expect_equal(tr$value[tr$arg == "n"], "length(z)")
})

test_that("long vectors that differ do not render alike", {
  a <- levelfield:::.render(c(1, 2, 3, 4, 5))
  b <- levelfield:::.render(c(1, 2, 3, 4, 6))
  expect_false(identical(a, b))
})

test_that("repeated identical calls collapse into one row with a count", {
  tr <- trace_args(list(a = function() for (i in 1:7) fit_lf(i, lambda = 0.5)), "fit_lf")
  expect_equal(tr$n_calls[tr$arg == "lambda"], 7L)
})

