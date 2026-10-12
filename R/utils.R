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

.num_eq <- function(a, b) {
  na <- suppressWarnings(as.numeric(a)); nb <- suppressWarnings(as.numeric(b))
  ifelse(!is.na(na) & !is.na(nb), abs(na - nb) <= 1e-9 * pmax(1, abs(na)),
         as.character(a) == as.character(b))
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
