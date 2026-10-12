# Render a value so that two arms agree on an argument exactly when the
# rendered strings are equal. Long vectors get a checksum rather than being
# collapsed to their length: two different penalty vectors of the same length
# must not compare equal.
.render <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.function(x)) return("<function>")
  if (is.environment(x)) return("<environment>")
  if (is.data.frame(x)) return(sprintf("<data.frame %dx%d #%s>", nrow(x), ncol(x), .checksum(x)))
  if (is.language(x)) return(paste(deparse(x), collapse = " "))
  if (is.atomic(x) && length(x) <= 4L) {
    if (!length(x)) return(sprintf("%s(0)", typeof(x)))
    return(paste(format(x, digits = 6, trim = TRUE), collapse = ", "))
  }
  if (is.atomic(x)) return(sprintf("<%s[%d] #%s>", typeof(x), length(x), .checksum(x)))
  sprintf("<%s[%d] #%s>", class(x)[1], length(x), .checksum(x))
}

.checksum <- function(x) {
  b <- as.numeric(serialize(x, NULL, xdr = FALSE))
  sprintf("%08x", as.integer(sum(b * seq_along(b)) %% 2147483647))
}

# A default is recorded as the expression in the function's formals, not by
# forcing it: a default may refer to variables the body has not created yet,
# and forcing it at entry would fail -- and leave R warning about an
# interrupted promise when the body forces it again.
.render_default <- function(e) {
  if (is.call(e) || is.name(e)) paste(deparse(e), collapse = " ") else .render(e)
}

# Equality for settings, as a logical vector with no NA in it. An NA level
# matches NA (sweeps often record a switched-off component that way), and the
# string "NA" -- how trace_args() renders an NA -- counts as NA too.
.num_eq <- function(a, b) {
  is_na <- function(x) is.na(x) | (is.character(x) & x %in% "NA")
  na_a <- is_na(a); na_b <- is_na(b)
  xa <- suppressWarnings(as.numeric(a)); xb <- suppressWarnings(as.numeric(b))
  out <- ifelse(!is.na(xa) & !is.na(xb), abs(xa - xb) <= 1e-9 * pmax(1, abs(xa)),
                as.character(a) == as.character(b))
  out[na_a & na_b] <- TRUE
  out[xor(na_a, na_b)] <- FALSE
  out[is.na(out)] <- FALSE
  out
}

.check_arms <- function(arms) {
  if (!is.list(arms) || !length(arms) || is.null(names(arms)) ||
      any(!nzchar(names(arms))) || anyDuplicated(names(arms)))
    stop("`arms` must be a list of functions with unique, non-empty names",
         call. = FALSE)
  if (!all(vapply(arms, is.function, logical(1))))
    stop("every element of `arms` must be a function taking no arguments",
         call. = FALSE)
}

# The choices of a match.arg-style default, c("a", "b", ...): a call to c()
# whose arguments are all single strings. NULL for anything else.
.choices <- function(e) {
  if (!is.call(e) || !identical(e[[1]], as.name("c")) || length(e) < 2L) return(NULL)
  args <- as.list(e)[-1]
  if (!all(vapply(args, function(x) is.character(x) && length(x) == 1L, logical(1)))) return(NULL)
  unlist(args)
}

# Does a function body pass argument `a` to match.arg()?
# Parts are indexed rather than assigned to a variable: a call such as x[, 1]
# contains the empty symbol, and a variable holding it errors when touched.
.uses_match_arg <- function(expr, a) {
  if (!is.call(expr)) return(FALSE)
  if (identical(expr[[1]], as.name("match.arg")) && length(expr) >= 2L &&
      identical(expr[[2]], as.name(a))) return(TRUE)
  for (i in seq_along(expr)[-1])
    if (is.call(expr[[i]]) && .uses_match_arg(expr[[i]], a)) return(TRUE)
  FALSE
}
