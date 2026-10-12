#' Choose a setting on one data set, score it on another, and price the peek
#'
#' Selects the best value of a setting on a selection set, scores that choice
#' on a separate evaluation set the selection never saw, and compares it with
#' the *oracle*: the value that would have been chosen by looking at the
#' evaluation set itself. The difference is the optimism of the common
#' practice of tuning on the data a result is then reported on.
#'
#' The two sets can be anything: a validation and a test split for
#' independent data, or two time windows for a series.
#'
#' @param grid Candidate values, as a vector or list.
#' @param select_score Function of one candidate returning per-unit scores on
#'   the selection set. Lower is better.
#' @param eval_score Function of one candidate returning per-unit scores on the
#'   evaluation set, with units in the same order as `select_score`.
#' @param summary Function reducing per-unit scores to the statistic used for
#'   selection.
#'
#' @return An object of class `levelfield_select`: a list with `table` (each
#'   candidate's selection and evaluation statistic), `chosen`, `oracle`,
#'   `optimism` (evaluation statistic at `chosen` minus at `oracle`, never
#'   negative), `optimism_t` (paired over units), and `agreed`.
#'
#' @details A setting chosen on the evaluation set is not comparable with one
#'   chosen by a procedure that never sees that set, such as REML or
#'   cross-validation on training data. Comparing the two measures the
#'   protocol rather than the methods. `optimism` puts a number on that.
#'
#'   For time series, [origin_windows()] gives the two sets as windows, with
#'   the selection window one horizon before the evaluation window.
#'
#' @references Cawley, G. C. and Talbot, N. L. C. (2010). On over-fitting in
#'   model selection and subsequent selection bias in performance evaluation.
#'   *Journal of Machine Learning Research* 11, 2079--2107.
#'
#' @examples
#' set.seed(1)
#' y <- cumsum(rnorm(200)) + 10 * sin(2 * pi * (1:200) / 50)
#' w <- origin_windows(length(y), h = 20)
#' mean_fc <- function(win, k) {
#'   tr <- y[win$train]
#'   abs(y[win$test] - mean(utils::tail(tr, k)))
#' }
#' nested_select(c(5, 10, 20, 40),
#'               select_score = function(k) mean_fc(w$select, k),
#'               eval_score   = function(k) mean_fc(w$evaluate, k))
#' @export
nested_select <- function(grid, select_score, eval_score, summary = mean) {
  if (!length(grid)) stop("`grid` is empty", call. = FALSE)
  sel <- lapply(grid, select_score)
  evl <- lapply(grid, eval_score)
  s_sel <- vapply(sel, function(v) summary(v[is.finite(v)]), numeric(1))
  s_evl <- vapply(evl, function(v) summary(v[is.finite(v)]), numeric(1))
  if (all(!is.finite(s_sel))) stop("no candidate produced a finite selection score", call. = FALSE)
  i_c <- which.min(s_sel)
  i_o <- which.min(s_evl)
  d <- evl[[i_c]] - evl[[i_o]]
  d <- d[is.finite(d)]
  se <- if (length(d) > 1L) stats::sd(d) / sqrt(length(d)) else NA_real_
  out <- list(
    table = data.frame(value = vapply(grid, .render, ""), select = s_sel,
                       evaluate = s_evl, chosen = seq_along(grid) == i_c,
                       oracle = seq_along(grid) == i_o, stringsAsFactors = FALSE),
    chosen = grid[[i_c]], oracle = grid[[i_o]],
    optimism = s_evl[i_c] - s_evl[i_o],
    optimism_t = if (is.finite(se) && se > 0) mean(d) / se else NA_real_,
    agreed = i_c == i_o)
  class(out) <- "levelfield_select"
  out
}

#' @export
print.levelfield_select <- function(x, ...) {
  cat(sprintf("<levelfield_select> chose %s on the selection set; the oracle is %s\n",
              .render(x$chosen), .render(x$oracle)))
  if (x$agreed) cat("  selection agrees with the oracle: optimism 0\n")
  else cat(sprintf("  optimism %.4g (paired t %.2f): what reporting the oracle would overstate\n",
                   x$optimism, x$optimism_t))
  print(x$table, row.names = FALSE)
  invisible(x)
}

#' Selection and evaluation windows for a time series
#'
#' Index sets for the nested protocol [nested_select()] expects. The
#' evaluation window is the last `h` observations, fitted on everything before
#' them. The selection window is the `h` observations before those, fitted on
#' everything before *it*. The two scored windows are disjoint, and the
#' selection fit never sees the evaluation window.
#'
#' @param n Length of the series.
#' @param h Forecast horizon.
#'
#' @return A list with `select` and `evaluate`, each a list of `train` and
#'   `test` index vectors.
#' @examples
#' str(origin_windows(100, h = 10))
#' @export
origin_windows <- function(n, h) {
  n <- as.integer(n); h <- as.integer(h)
  if (n <= 2L * h) stop("`n` must exceed twice `h` to leave a training window", call. = FALSE)
  list(select   = list(train = seq_len(n - 2L * h), test = (n - 2L * h) + seq_len(h)),
       evaluate = list(train = seq_len(n - h),      test = (n - h) + seq_len(h)))
}
