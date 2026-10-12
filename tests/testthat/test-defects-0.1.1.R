# Defects found when sennit's research harness adopted levelfield 0.1.0. Each
# test reproduces one, and each was confirmed to fail on the 0.1.0 code.

test_that("a package loaded with pkgload is traced through every call path", {
  skip_if_not_installed("pkgload")
  # 0.1.0 traced only the attached copy; R carries that into the namespace only
  # when the attached binding is locked, which load_all does not do. Every
  # pkg::fn call went untraced and the trace came back EMPTY, with no warning.
  dir <- file.path(tempfile("lfpkg"), "lfpkgtest")
  dir.create(file.path(dir, "R"), recursive = TRUE)
  writeLines(c("Package: lfpkgtest", "Version: 0.0.1", "Title: T", "Description: T.",
               "License: MIT", 'Authors@R: person("A", "B", email = "a@b.c", role = c("aut", "cre"))'),
             file.path(dir, "DESCRIPTION"))
  writeLines(c("export(fitx)", "export(callfit)"), file.path(dir, "NAMESPACE"))
  writeLines(c("fitx <- function(y, lambda = 1) sum(y) / (1 + lambda)",
               "callfit <- function(y) fitx(y, lambda = 0.5)"), file.path(dir, "R", "f.R"))
  pkgload::load_all(dir, quiet = TRUE)
  on.exit(pkgload::unload("lfpkgtest"), add = TRUE)

  tr <- trace_args(list(qualified = function() lfpkgtest::fitx(1, lambda = 2),
                        attached  = function() fitx(1),
                        internal  = function() lfpkgtest::callfit(1)),
                   "lfpkgtest::fitx")
  expect_setequal(unique(tr$arm), c("qualified", "attached", "internal"))
  lam <- function(arm) tr$value[tr$arm == arm & tr$arg == "lambda"]
  expect_equal(lam("qualified"), "2")
  expect_equal(lam("attached"), "1")
  expect_equal(lam("internal"), "0.5")
  expect_false(inherits(get("fitx", asNamespace("lfpkgtest")), "functionWithTrace"))
})

test_that("an arm that makes no traced call is reported, never silently absent", {
  fit_d <- function(y, lambda = 1) y
  other <- function(y) y
  expect_warning(tr <- trace_args(list(uses = function() fit_d(1),
                                       misses = function() other(1)), "fit_d"),
                 "made no call to a traced function: misses")
  expect_equal(attr(tr, "untraced"), "misses")
})

test_that("an NA level in a swept setting is a level, and does not break the audit", {
  # sweeps record a switched-off component as NA; 0.1.0 then gave every level a
  # score of NA and crashed choosing among them
  fit_na <- function(y, tau = 1) y
  set.seed(5)
  ev <- expand.grid(tau = c(NA, 0.3, 1), unit = 1:30)
  ev$score <- with(ev, ifelse(is.na(tau), 2, ifelse(tau == 0.3, 1, 1.4))) +
              rnorm(nrow(ev), 0, 0.05)
  tr <- trace_args(list(off_best = function() fit_na(1, tau = 1)), "fit_na")
  a <- audit_args(tr, ev)
  expect_equal(a$best, "0.3")
  expect_equal(a$verdict, "OFF ITS BEST")
  expect_gt(a$cost, 0.3)
})

test_that("a match.arg default is recorded as the value match.arg chooses", {
  # 0.1.0 recorded c("auto", "dense", "sparse"), which never matches evidence
  # recorded as "auto"
  fit_m <- function(y, solver = c("auto", "dense", "sparse"), labels = c("a", "b")) {
    solver <- match.arg(solver)
    y[, 1]   # the empty symbol in a body must not break the scan for match.arg
  }
  tr <- trace_args(list(a = function() fit_m(matrix(1:4, 2))), "fit_m")
  expect_equal(tr$value[tr$arg == "solver"], "auto")
  # a character-vector default NOT passed to match.arg stays as written
  expect_equal(tr$value[tr$arg == "labels"], 'c("a", "b")')
})

test_that("a setting that cannot be held is reported, and nearest = TRUE holds it", {
  # the arm runs K = 75; the sweep recorded K = 20 and 35 only. 0.1.0 silently
  # averaged over K. Here the best lambda differs by K, so averaging misleads.
  fit_k <- function(y, lambda = 1, K = 2) y
  set.seed(9)
  ev <- expand.grid(lambda = c(0.1, 1), K = c(20, 35), unit = 1:40)
  ev$score <- with(ev, ifelse(K == 35, ifelse(lambda == 1, 1.0, 1.5),
                                       ifelse(lambda == 1, 2.0, 1.0))) +
              rnorm(nrow(ev), 0, 0.02)
  tr <- trace_args(list(arm = function() fit_k(1, lambda = 1, K = 75)), "fit_k")
  expect_warning(a <- audit_args(tr, ev), "could not be held")
  expect_match(a$not_held[a$arg == "lambda"], "K \\(used 75\\)")
  n <- audit_args(tr, ev, nearest = TRUE)
  l <- n[n$arg == "lambda", ]
  expect_match(l$conditioned_on, "K = 35 \\(nearest to 75\\)")
  expect_equal(l$not_held, "")
  expect_equal(l$verdict, "at its best")
})
