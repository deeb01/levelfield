test_that("optimism is zero when selection agrees with the oracle", {
  f <- function(v) rep(abs(v - 3), 10)
  r <- nested_select(1:5, f, f)
  expect_true(r$agreed)
  expect_equal(r$optimism, 0)
})

test_that("a window shift that moves the optimum produces positive optimism", {
  # planted: the selection window favours 2, the evaluation window favours 4
  r <- nested_select(1:5,
                     select_score = function(v) rep((v - 2)^2, 20) + rnorm(20, 0, 0.01),
                     eval_score   = function(v) rep((v - 4)^2, 20) + rnorm(20, 0, 0.01))
  expect_false(r$agreed)
  expect_equal(r$chosen, 2L)
  expect_equal(r$oracle, 4L)
  expect_equal(r$optimism, 4, tolerance = 0.01)
  expect_gt(r$optimism_t, 10)
})

test_that("origin_windows keeps the selection fit away from the evaluation window", {
  w <- origin_windows(100, h = 10)
  expect_length(w$select$test, 10)
  expect_length(w$evaluate$test, 10)
  expect_length(intersect(w$select$test, w$evaluate$test), 0)   # scored windows disjoint
  expect_true(all(w$select$train %in% w$evaluate$train))        # inner fit nested in outer
  expect_true(max(w$select$train) < min(w$select$test))
  expect_lt(max(c(w$select$train, w$select$test)), min(w$evaluate$test))
  expect_error(origin_windows(15, h = 10), "twice")
})
