# The README's worked example. Every number in README.md comes from running this.
#   Rscript demo/demo.R
suppressMessages(library(levelfield))
set.seed(42)

# 40 simulated daily series: level, drift, weekly and annual cycles, noise
n <- 400; h <- 28; S <- 40
panel <- lapply(seq_len(S), function(s) {
  t <- seq_len(n + h)
  y <- runif(1, 5, 50) + rnorm(1, 0, 0.02) * t + 3 * sin(2 * pi * t / 7) +
       2 * cos(2 * pi * t / 365.25) + rnorm(n + h, 0, runif(1, 0.5, 4))
  y
})

# A ridge forecaster: drift plus K weekly harmonics, standardised penalty lambda
ridge_forecast <- function(y, h, lambda = 1, K = 2) {
  feat <- function(t) cbind(t / length(y), do.call(cbind, lapply(seq_len(K),
            function(k) cbind(sin(2 * pi * k * t / 7), cos(2 * pi * k * t / 7)))))
  X <- scale(feat(seq_along(y))); mu <- mean(y)
  b <- solve(crossprod(X) + lambda * nrow(X) * diag(ncol(X)), crossprod(X, y - mu))
  Xf <- scale(feat(length(y) + seq_len(h)),
              center = attr(X, "scaled:center"), scale = attr(X, "scaled:scale"))
  drop(mu + Xf %*% b)
}

# The two methods being compared. The baseline's wrapper accepts lambda and
# never forwards it -- the defect this example plants.
new_method <- function(y) ridge_forecast(y, h, lambda = 0.001, K = 3)
baseline   <- function(y, lambda = 0.001) ridge_forecast(y, h, K = 2)

mae_by_series <- function(method, win = origin_windows(n + h, h)$evaluate)
  vapply(panel, function(y) mean(abs(method(y[win$train]) - y[win$test])), numeric(1))

paired <- function(a, b) {   # b minus a, per series
  d <- b - a
  sprintf("%+.3f MAE (paired t %.2f), new method better on %d of %d series",
          mean(d), mean(d) / (sd(d) / sqrt(length(d))), sum(d > 0), length(d))
}

cat("== 1. the comparison as run ==\n")
cat("baseline minus new method:", paired(mae_by_series(new_method), mae_by_series(baseline)), "\n\n")

cat("== 2. what each arm actually passed ==\n")
tr <- trace_args(list(new = function() new_method(panel[[1]][1:n]),
                      baseline = function() baseline(panel[[1]][1:n])),
                 "ridge_forecast")
print(arg_diffs(tr, ignore = c("y", "h")))

cat("\n== 3. is each arm at its own best? ==\n")
# A recorded sweep of the baseline's lambda, scored on the SELECTION window
sel <- origin_windows(n + h, h)$select
grid <- c(1e-4, 1e-3, 1e-2, 0.1, 1)
sweep <- do.call(rbind, lapply(grid, function(l) data.frame(
  lambda = l, K = 2, unit = seq_len(S),
  score = mae_by_series(function(y) ridge_forecast(y, h, lambda = l, K = 2), sel))))
a <- audit_args(tr, sweep)
print(a[a$arm == "baseline", c("arm", "arg", "used", "best", "cost", "t", "verdict")], row.names = FALSE)

cat("\n== 4. the comparison with the argument forwarded ==\n")
baseline_fixed <- function(y, lambda = 0.001) ridge_forecast(y, h, lambda = lambda, K = 2)
cat("baseline minus new method:", paired(mae_by_series(new_method), mae_by_series(baseline_fixed)), "\n\n")

cat("== 5. choosing lambda without seeing the evaluation window ==\n")
ev <- origin_windows(n + h, h)$evaluate
print(nested_select(grid,
  select_score = function(l) mae_by_series(function(y) ridge_forecast(y, h, lambda = l, K = 2), sel),
  eval_score   = function(l) mae_by_series(function(y) ridge_forecast(y, h, lambda = l, K = 2), ev)))
