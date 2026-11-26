# Used by .github/workflows/r-sysdeps-check.yml. Base R only.
#   Rscript check.R install <test_r.py> <probe pkgs...>   install from PPM (binaries via the image's user agent)
#   Rscript check.R load    <test_r.py> <probe pkgs...>   library() each in a fresh R, write a summary table
# Packages in R_PACKAGES (test_r.py) must load: those the image preinstalls.
# Probe pkgs not in R_PACKAGES are reported only (expected to fail on today's image).
args  <- commandArgs(TRUE)
mode  <- args[1]
probe <- args[-(1:2)]

py <- readLines(args[2])
block <- py[seq(grep("^R_PACKAGES = \\[", py), length(py))]
block <- block[seq_len(grep("^\\]", block)[1])]
required <- setdiff(regmatches(block, regexpr('(?<=")[^"]+(?=")', block, perl = TRUE)), "zonetokenbroker")
pkgs <- union(required, probe)

if (mode == "install") {
  install.packages(pkgs, repos = c(CRAN = Sys.getenv("PPM")), Ncpus = 4)
  quit(status = 0)
}

log <- if (file.exists("install.log")) readLines("install.log", warn = FALSE) else character()
seen <- function(kind, p) any(grepl(sprintf("installing \\*%s\\* package [^A-Za-z0-9._]+%s[^A-Za-z0-9._]", kind, p), log, useBytes = TRUE))
how <- vapply(pkgs, function(p) {
  if (seen("binary", p)) "binary"
  else if (seen("source", p)) "source"
  else if (nzchar(system.file(package = p))) "installed" else "not installed"
}, "")

res <- do.call(rbind, lapply(pkgs, function(p) {
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c("-e", shQuote(sprintf("suppressMessages(library(%s))", p))),
                                  stdout = TRUE, stderr = TRUE))
  ok  <- is.null(attr(out, "status"))
  err <- if (ok) "" else {
    hit <- grep("cannot open shared object|there is no package|Error", out, value = TRUE)
    gsub("\\|", "/", trimws(paste(head(unique(c(hit, out)), 2), collapse = " ")))
  }
  data.frame(pkg = p, required = p %in% required, installed_as = how[[p]], loads = ok, error = substr(err, 1, 160))
}))
res <- res[order(!res$required, res$loads, res$pkg), ]

md <- c(sprintf("### %s", Sys.getenv("CHECK_NAME", "R packages")), "",
        sprintf("%d of %d packages the image preinstalls load; %d of %d probe-only packages load.",
                sum(res$loads & res$required), sum(res$required), sum(res$loads & !res$required), sum(!res$required)), "",
        "| pkg | preinstalled by image | installed as | loads | error |", "|---|---|---|---|---|",
        sprintf("| %s | %s | %s | %s | %s |", res$pkg, ifelse(res$required, "yes", "no (probe)"),
                res$installed_as, ifelse(res$loads, "yes", "**NO**"), res$error))
summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) cat(md, sep = "\n", file = summary_file, append = TRUE)
cat(md, sep = "\n")

bad <- res$pkg[res$required & !res$loads]
if (length(bad)) stop("preinstalled R packages that don't load: ", paste(bad, collapse = ", "))
