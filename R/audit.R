#' Is each arm running at its own measured best?
#'
#' Joins the settings each arm actually used, from [trace_args()], to recorded
#' tuning evidence, and reports for every (arm, setting) the value used, the
#' value the evidence measures as best, and what the gap costs.
#'
#' [arg_diffs()] finds settings that differ between arms. This finds a
#' different defect: a setting can be identical in every arm and wrong for all
#' of them, or can differ legitimately because each arm sits at its own
#' optimum. A difference is not a handicap, and a handicap need not be a
#' difference.
#'
#' @param trace The result of [trace_args()].
#' @param evidence A data frame of recorded tuning results in long form: one
#'   column per swept setting, named after the function argument it sets, plus
#'   a pairing column and a score column. Each row is one unit (a series, a
#'   fold, a seed) scored at one combination of settings.
#' @param score Name of the score column. Lower is better.
#' @param unit Name of the pairing column. The cost of a gap is computed from
#'   differences within each unit, which removes between-unit variation.
#' @param fn Restrict the audit to arguments of this traced function, given as
#'   it was given to [trace_args()]. `NULL` audits every traced function.
#' @param threshold Gaps smaller than this are reported as negligible however
#'   significant they are. Pairing can make a negligible difference highly
#'   significant.
#' @param summary Function reducing per-unit scores to the statistic that
#'   decides which setting is best.
#'
#' @return A data frame with one row per (arm, function, setting): `used`,
#'   `best`, `cost` (the paired mean of score at `used` minus score at `best`,
#'   so positive is the price of the gap), `t`, `n_units`, `conditioned_on`
#'   (the other swept settings held at the arm's own values), and `verdict`.
#'
#' @details When the evidence sweeps several settings jointly, the best value
#'   of one is found with the others held at the values the arm used. The best
#'   value of one setting averaged over the others answers a different
#'   question, and can disagree with the conditional answer. A setting the arm
#'   used but the evidence never measured is reported as
#'   `"value not in evidence"`; a setting no evidence covers does not appear.
#'
#' @examples
#' fit <- function(y, lambda = 1) sum(y) / (1 + lambda)
#' tr <- trace_args(
#'   list(tuned    = function() fit(1:10, lambda = 0.1),
#'        baseline = function() fit(1:10)),
#'   "fit")
#' # recorded sweep: lambda = 0.1 is best on every unit
#' ev <- expand.grid(lambda = c(0.1, 1), unit = 1:20)
#' ev$score <- ifelse(ev$lambda == 0.1, 1, 1.3) + rnorm(nrow(ev), 0, 0.05)
#' audit_args(tr, ev)
#' @export
audit_args <- function(trace, evidence, score = "score", unit = "unit",
                       fn = NULL, threshold = 0, summary = mean) {
  if (!inherits(trace, "levelfield_trace"))
    stop("`trace` must come from trace_args()", call. = FALSE)
  if (!is.data.frame(evidence)) stop("`evidence` must be a data frame", call. = FALSE)
  for (col in c(score, unit))
    if (!col %in% names(evidence))
      stop(sprintf("`evidence` has no column `%s`", col), call. = FALSE)
  if (!is.null(fn)) trace <- trace[trace$fn %in% fn, , drop = FALSE]

  settings <- setdiff(names(evidence), c(score, unit))
  settings <- intersect(settings, unique(trace$arg))
  if (!length(settings)) return(.empty_audit())

  rows <- list()
  for (key in unique(paste(trace$arm, trace$fn, sep = "\r"))) {
    tk <- trace[paste(trace$arm, trace$fn, sep = "\r") == key, , drop = FALSE]
    arm <- tk$arm[1]; f <- tk$fn[1]
    used_of <- function(s) unique(tk$value[tk$arg == s])
    for (s in intersect(settings, unique(tk$arg))) {
      for (u in used_of(s)) {
        sub <- evidence
        held <- character(0)
        for (o in setdiff(settings, s)) {
          uo <- used_of(o)
          if (length(uo) != 1L) next
          keep <- .num_eq(sub[[o]], uo)
          if (any(keep)) { sub <- sub[keep, , drop = FALSE]; held <- c(held, sprintf("%s = %s", o, uo)) }
        }
        rows[[length(rows) + 1L]] <- .audit_one(arm, f, s, u, sub, score, unit,
                                                 threshold, summary, held)
      }
    }
  }
  if (!length(rows)) return(.empty_audit())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out <- out[order(out$verdict != "OFF ITS BEST", -abs(ifelse(is.na(out$cost), 0, out$cost))), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}

.audit_one <- function(arm, fn, s, used, sub, score, unit, threshold, summary, held) {
  lv <- unique(sub[[s]])
  stat <- vapply(lv, function(v) summary(sub[[score]][.num_eq(sub[[s]], v)]), numeric(1))
  best <- lv[which.min(stat)]
  m <- lv[.num_eq(lv, used)]
  base <- data.frame(arm = arm, fn = fn, arg = s, used = used,
                     best = as.character(best), cost = NA_real_, t = NA_real_,
                     n_units = NA_integer_,
                     conditioned_on = if (length(held)) paste(held, collapse = ", ") else "",
                     verdict = "value not in evidence", stringsAsFactors = FALSE)
  if (!length(m)) return(base)
  a <- sub[.num_eq(sub[[s]], m[1]), c(unit, score)]
  b <- sub[.num_eq(sub[[s]], best), c(unit, score)]
  names(a)[2] <- ".used"; names(b)[2] <- ".best"
  z <- merge(a, b, by = unit)
  d <- z$.used - z$.best
  d <- d[is.finite(d)]
  base$n_units <- length(d)
  if (.num_eq(m[1], best)) { base$cost <- 0; base$verdict <- "at its best"; return(base) }
  if (length(d) < 2L) { base$verdict <- "too few paired units"; return(base) }
  se <- stats::sd(d) / sqrt(length(d))
  base$cost <- mean(d)
  base$t <- if (se > 0) mean(d) / se else NA_real_
  base$verdict <- if (abs(mean(d)) < threshold) "off its best, negligible" else "OFF ITS BEST"
  base
}

.empty_audit <- function() {
  data.frame(arm = character(0), fn = character(0), arg = character(0),
             used = character(0), best = character(0), cost = numeric(0),
             t = numeric(0), n_units = integer(0), conditioned_on = character(0),
             verdict = character(0), stringsAsFactors = FALSE)
}
