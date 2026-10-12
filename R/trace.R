#' Record the arguments each arm passes to the functions it calls
#'
#' Runs every arm with the named functions traced, and records every argument
#' each call received, including defaults the caller never wrote. A benchmark's
#' configuration is what its code passed at run time. A comment, a config file
#' or a results table can disagree with that, and the run time is what the
#' scores came from.
#'
#' @param arms A named list of functions taking no arguments, one per method
#'   being compared. Each runs that method end to end.
#' @param fns Functions to trace, as `"pkg::fn"` for a package function or
#'   `"fn"` for any other, which is looked up from `where`.
#' @param where Environment from which unqualified names in `fns` are looked
#'   up. The default, the caller's environment, finds functions defined in a
#'   script, a test file or the body of a function.
#'
#' @return A data frame of class `levelfield_trace` with one row per distinct
#'   (arm, function, argument, value): `source` is `"passed"` when the caller
#'   supplied the argument, `"default"` when it fell through to the default in
#'   the function's formals, and `"missing"` when neither; `n_calls` counts the
#'   calls that saw that value. Errors raised by an arm are kept in the
#'   `"errors"` attribute instead of stopping the trace.
#'
#' @details The function is traced in the environment that holds it, and an arm
#'   is traced only if it reaches that binding by name. A copy captured into
#'   another variable before tracing starts (`f <- fit; f(y)`), or a second
#'   definition that shadows the traced one, is not traced. An arm that makes
#'   no traced call appears in no row; check that every arm you expected is
#'   present.
#'
#'   Passed arguments are evaluated when the call begins, which is earlier than
#'   a lazily evaluating function would evaluate them. Defaults are not
#'   evaluated: they are recorded as the expression in the formals.
#'
#' @examples
#' fit <- function(y, lambda = 1) sum(y) / (1 + lambda)
#' tr <- trace_args(
#'   list(tuned    = function() fit(1:10, lambda = 0.1),
#'        baseline = function() fit(1:10)),
#'   "fit")
#' tr
#' arg_diffs(tr)
#' @export
trace_args <- function(arms, fns, where = parent.frame()) {
  .check_arms(arms)
  if (!is.character(fns) || !length(fns))
    stop("`fns` must name at least one function", call. = FALSE)

  log <- new.env(parent = emptyenv())
  log$rows <- list()
  log$arm <- NA_character_

  targets <- lapply(fns, .resolve, where = where)
  on.exit(for (tg in targets) .trace_off(tg), add = TRUE)
  for (tg in targets) .trace_on(tg, .make_tracer(tg$label, log))

  errors <- character(0)
  for (k in names(arms)) {
    log$arm <- k
    msg <- tryCatch({ arms[[k]](); NA_character_ },
                    error = function(e) conditionMessage(e))
    if (!is.na(msg)) errors[k] <- msg
  }

  out <- .collect(log$rows)
  attr(out, "errors") <- errors
  # An arm that reached no traced function contributes no rows, and an empty
  # trace reads exactly like "the arms agree". Say so.
  silent <- setdiff(names(arms), c(unique(out$arm), names(errors)))
  attr(out, "untraced") <- silent
  if (length(silent))
    warning(sprintf("%d arm(s) made no call to a traced function: %s. Check the names in `fns`, and that the arm calls the function by that name.",
                    length(silent), paste(silent, collapse = ", ")), call. = FALSE)
  if (length(errors))
    warning(sprintf("%d arm(s) raised an error and are partly traced: %s",
                    length(errors), paste(names(errors), collapse = ", ")),
            call. = FALSE)
  out
}

#' Settings that differ between arms
#'
#' Reports every argument of a traced function whose value is not the same in
#' every arm that called it. Each such difference is either the thing the
#' comparison is about or a confound, and only the reader can say which.
#'
#' @param trace The result of [trace_args()].
#' @param ignore Argument names to leave out, typically the data arguments,
#'   which differ by design.
#'
#' @return A data frame with one row per differing (function, argument):
#'   `values` lists each arm's value, and `fell_to_default` is `TRUE` when at
#'   least one arm supplied the argument and another received the default.
#'   That pattern is how a wrapper that fails to forward an argument appears.
#' @export
arg_diffs <- function(trace, ignore = character(0)) {
  if (!inherits(trace, "levelfield_trace"))
    stop("`trace` must come from trace_args()", call. = FALSE)
  t <- trace[!trace$arg %in% ignore, , drop = FALSE]
  if (!nrow(t)) return(.empty_diffs())
  key <- paste(t$fn, t$arg, sep = "\r")
  rows <- lapply(split(t, key), function(g) {
    per_arm <- tapply(g$value, g$arm, function(v) paste(sort(unique(v)), collapse = " | "))
    if (length(unique(per_arm)) <= 1L) return(NULL)
    src <- tapply(g$source, g$arm, function(s) paste(sort(unique(s)), collapse = "|"))
    data.frame(fn = g$fn[1], arg = g$arg[1],
               values = paste(sprintf("%s = %s", names(per_arm), per_arm), collapse = "; "),
               fell_to_default = any(src == "default") && any(src == "passed"),
               stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(.empty_diffs())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out <- out[order(!out$fell_to_default, out$fn, out$arg), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' @export
print.levelfield_trace <- function(x, ...) {
  calls <- tapply(x$n_calls, paste(x$arm, x$fn), max)
  cat(sprintf("<levelfield_trace> %d arm(s), %d function(s), %d distinct arguments\n",
              length(unique(x$arm)), length(unique(x$fn)), nrow(x)))
  err <- attr(x, "errors")
  if (length(err)) cat(sprintf("  arm %s raised: %s\n", names(err), err), sep = "")
  print(as.data.frame(x)[, c("arm", "fn", "arg", "value", "source", "n_calls")],
        row.names = FALSE)
  invisible(x)
}

# --- internals --------------------------------------------------------------

.resolve <- function(spec, where) {
  if (grepl("::", spec, fixed = TRUE)) {
    parts <- strsplit(spec, "::", fixed = TRUE)[[1]]
    pkg <- parts[1]; nm <- parts[length(parts)]
    if (!exists(nm, envir = asNamespace(pkg), inherits = FALSE))
      stop(sprintf("`%s` is not in the namespace of %s", nm, pkg), call. = FALSE)
    return(list(label = spec, name = nm, where = .package_where(pkg, nm)))
  }
  env <- where
  while (!identical(env, emptyenv()) && !exists(spec, envir = env, inherits = FALSE))
    env <- parent.env(env)
  if (identical(env, emptyenv()))
    stop(sprintf("`%s` was not found from `where`; use \"pkg::%s\" for a package function",
                 spec, spec), call. = FALSE)
  # An unqualified name that resolves into a package is traced as one.
  nm_env <- environmentName(env)
  if (startsWith(nm_env, "package:"))
    return(list(label = spec, name = spec, where = .package_where(sub("^package:", "", nm_env), spec)))
  if (isNamespace(env))
    return(list(label = spec, name = spec, where = .package_where(getNamespaceName(env), spec)))
  list(label = spec, name = spec, where = list(env))
}

# A package function can live in two places: its namespace, which every
# `pkg::fn` call and every call from inside the package reads, and the attached
# package environment, which an unqualified call from a script reads. Both are
# traced, separately.
#
# Tracing only the attached copy is not enough. R carries a trace from the
# attached copy into the namespace only when the attached binding is LOCKED,
# which library() does and pkgload::load_all() does not. Under load_all a trace
# through the attached copy alone misses every `pkg::fn` call -- and returns an
# empty trace, which reads exactly like "the arms agree".
.package_where <- function(pkg, name) {
  out <- list(asNamespace(pkg))
  att <- paste0("package:", pkg)
  if (att %in% search() && exists(name, envir = as.environment(att), inherits = FALSE))
    out <- c(out, list(as.environment(att)))
  out
}

# trace() inserts a CALL to its tracer into the traced function's body and
# evaluates it in that function's frame. Passing `tracer = tracer` would insert
# the call `tracer()`, which only resolves if a function of that name happens
# to be visible from the traced function -- true for a tracer in the global
# environment, false for one built here. Inlining the function object into the
# call removes the lookup.
.trace_on <- function(tg, tracer) {
  for (w in tg$where)
    suppressMessages(trace(tg$name, tracer = as.call(list(tracer)),
                           where = w, print = FALSE))
}

.trace_off <- function(tg) {
  for (w in tg$where)
    try(suppressMessages(untrace(tg$name, where = w)), silent = TRUE)
}

# The tracer runs inside the traced call: R's .doTrace evaluates it in that
# call's frame, so parent.frame() is the call and sys.function(sys.parent()) is
# the function. Both are built per target with force(), because a closure made
# in a loop captures the loop variable and would label every call alike.
.make_tracer <- function(label, log) {
  force(label); force(log)
  function() {
    fr <- parent.frame()
    fml <- formals(sys.function(sys.parent()))
    for (a in setdiff(names(fml), "...")) {
      passed <- !eval(call("missing", as.name(a)), fr)
      if (passed) {
        v <- tryCatch(.render(get(a, envir = fr, inherits = FALSE)),
                      error = function(e) "<error evaluating argument>")
        src <- "passed"
      } else {
        d <- deparse(fml[[a]])
        if (!nzchar(d[1])) { v <- "<missing>"; src <- "missing" }
        else {
          # A default written as c("a", "b") and passed to match.arg() runs as
          # its first element. Recording the whole vector would never match
          # evidence that recorded the value actually used.
          ch <- .choices(fml[[a]])
          v <- if (!is.null(ch) && .uses_match_arg(body(sys.function(sys.parent())), a))
                 ch[1] else .render_default(fml[[a]])
          src <- "default"
        }
      }
      log$rows[[length(log$rows) + 1L]] <-
        c(arm = log$arm, fn = label, arg = a, value = v, source = src)
    }
    invisible(NULL)
  }
}

.collect <- function(rows) {
  if (!length(rows)) {
    out <- data.frame(arm = character(0), fn = character(0), arg = character(0),
                      value = character(0), source = character(0),
                      n_calls = integer(0), stringsAsFactors = FALSE)
  } else {
    m <- do.call(rbind, rows)
    d <- as.data.frame(m, stringsAsFactors = FALSE)
    key <- do.call(paste, c(d[c("arm", "fn", "arg", "value", "source")], sep = "\r"))
    n <- table(key)
    d <- d[!duplicated(key), , drop = FALSE]
    d$n_calls <- as.integer(n[do.call(paste, c(d[c("arm", "fn", "arg", "value", "source")], sep = "\r"))])
    out <- d
  }
  rownames(out) <- NULL
  class(out) <- c("levelfield_trace", "data.frame")
  out
}

.empty_diffs <- function() {
  data.frame(fn = character(0), arg = character(0), values = character(0),
             fell_to_default = logical(0), stringsAsFactors = FALSE)
}
