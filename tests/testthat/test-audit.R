fit_au <- function(y, lambda = 1, K = 2) NULL

ev_one <- function(best = 0.1, others = c(1, 10), units = 30, gap = 0.3) {
  set.seed(7)
  ev <- expand.grid(lambda = c(best, others), unit = seq_len(units))
  ev$score <- 1 + ifelse(ev$lambda == best, 0, gap) + rnorm(nrow(ev), 0, 0.05)
  ev
}

test_that("an arm off its measured best is named, with the cost and its sign", {
  tr <- trace_args(list(tuned = function() fit_au(1, lambda = 0.1),
                        stuck = function() fit_au(1)), "fit_au")
  a <- audit_args(tr, ev_one())
  s <- a[a$arm == "stuck", ]
  expect_equal(s$verdict, "OFF ITS BEST")
  expect_equal(s$best, "0.1")
  expect_gt(s$cost, 0.25)
  expect_gt(s$t, 10)
  expect_equal(a$verdict[a$arm == "tuned"], "at its best")
})

test_that("a gap below the threshold is reported as negligible", {
  tr <- trace_args(list(stuck = function() fit_au(1)), "fit_au")
  a <- audit_args(tr, ev_one(gap = 0.002), threshold = 0.01)
  expect_equal(a$verdict, "off its best, negligible")
})

test_that("a value the evidence never measured is reported, not guessed", {
  tr <- trace_args(list(odd = function() fit_au(1, lambda = 3)), "fit_au")
  expect_equal(audit_args(tr, ev_one())$verdict, "value not in evidence")
})

test_that("the best of one setting is found with the others held at the arm's values", {
  # planted: averaged over K, lambda = 1 looks best; at the arm's own K = 2,
  # lambda = 0.1 is best. A marginal audit would call this arm at its best.
  set.seed(3)
  ev <- expand.grid(lambda = c(0.1, 1), K = c(2, 6), unit = 1:40)
  ev$score <- with(ev, ifelse(K == 2, ifelse(lambda == 0.1, 1.0, 1.2),
                                       ifelse(lambda == 0.1, 3.0, 1.5))) +
              rnorm(nrow(ev), 0, 0.02)
  tr <- trace_args(list(arm = function() fit_au(1, lambda = 1, K = 2)), "fit_au")
  a <- audit_args(tr, ev)
  l <- a[a$arg == "lambda", ]
  expect_equal(l$best, "0.1")
  expect_equal(l$verdict, "OFF ITS BEST")
  expect_match(l$conditioned_on, "K = 2")
})

test_that("the evidence must carry the named score and unit columns", {
  tr <- trace_args(list(a = function() fit_au(1)), "fit_au")
  expect_error(audit_args(tr, data.frame(lambda = 1, loss = 1)), "no column `score`")
})

