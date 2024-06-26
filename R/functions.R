datasets <-
function(url = "https://data.bis.org/bulkdownload", ...) {
    u <- url(url)
    txt <- try(readLines(u, warn = FALSE), silent = TRUE)
    try(close(u), silent = TRUE)
    if (inherits(txt, "try-error")) {
        warning("download failed with message ", sQuote(txt, FALSE))
        return(invisible(NULL))
    }
    txt <- paste(txt, collapse = "")

    m <- gregexec("/static/bulk/(.{1,110}zip)", txt, perl = TRUE)
    mm <- regmatches(txt, m, invert = FALSE)[[1]][2, ]
    fn <- mm[grep("_csv", mm, ignore.case = TRUE)]
    fn <- unique(fn)

    data.frame(filename = trimws(fn),
               description = NA,
               updated = NA)
}



fetch_dataset <-
function(dest.dir, dataset,
         bis.url = "https://data.bis.org/static/bulk/",
         exdir = tempdir(),
         return.class = NULL,
         frequency = NULL,
         ...,
         header = TRUE,
         sep = ",",
         stringsAsFactors = FALSE,
         check.names = FALSE,
         na.strings = "",
         quote = "\"",
         fill = TRUE) {


    if (!dir.exists(dest.dir)) {
        create.dir <- askYesNo(
            paste(sQuote("dest.dir"), "does not exist. Create it?"),
            default = FALSE)
        if (!isTRUE(create.dir))
            return(invisible(NULL))
        dir.create(dest.dir, recursive = TRUE)
    }

    dataset <- basename(dataset)
    f.name <- paste0(format(Sys.Date(), "%Y%m%d_"), dataset)

    dataset <- paste0(bis.url, dataset)
    f.path <- file.path(normalizePath(dest.dir), f.name)

    if (!file.exists(f.path)) {
        dl.result <- try(download.file(dataset, f.path), silent = TRUE)
        if (inherits(dl.result, "try-error")) {
            warning("download failed with message ", sQuote(dl.result, FALSE))
            return(invisible(NULL))
        }
    } else
        dl.result <- 0

    if (dl.result != 0L) {
        warning("download failed with code ", dl.result, "; see ?download.file")
        return(invisible(NULL))
    }
    txt <- process_dataset(f.path,
                           exdir = exdir,
                           return.class = return.class,
                           frequency = frequency,
                           ...,
                           header = header,
                           sep = sep,
                           stringsAsFactors = stringsAsFactors,
                           check.names = check.names,
                           na.strings = na.strings,
                           quote = quote,
                           fill = fill)
    txt
}



process_dataset <-
function(f.path, exdir, return.class, frequency,
         ...,
         header,
         sep,
         stringsAsFactors,
         check.names,
         na.strings,
         quote,
         fill) {

    tmp <- unzip(f.path, exdir = exdir)
    on.exit(file.remove(tmp))
    txt <- read.table(tmp,
                      header = header,
                      sep = sep,
                      stringsAsFactors = stringsAsFactors,
                      check.names = check.names,
                      na.strings = na.strings,
                      quote = quote,
                      fill = fill,
                      ...)

    if (is.null(return.class))
        return(txt)

    if (return.class == "zoo") {

        if (!requireNamespace("zoo")) {
            warning("package ", sQuote("zoo"), " not available")
            return(txt)
        }

        if (grepl("full_webstats_credit_gap_dataflow_csv.zip",
                  basename(f.path), fixed = TRUE) ||
            grepl("full_bis_total_credit_csv.zip",
                  basename(f.path), fixed = TRUE)) {

            ## FIXME grep for first date?
            j <- which(colnames(txt) == "Time Period")
            ans <- t(txt[, -seq_len(j)])
            ans <- zoo::zoo(ans,
                            zoo::as.yearqtr(rownames(ans),
                                            format = "%Y-Q%q"))
            attr(ans, "headers") <- t(txt[, seq_len(j)])
            colnames(ans) <- colnames(attr(ans, "headers")) <-
                txt[["Time Period"]]
        } else if (grepl("full_xru_d_csv_row.zip",
                         basename(f.path), fixed = TRUE)) {
            i <- which(txt[[1]] == "Time Period")
            ans <- txt[-seq_len(i), -1]
            ans <- apply(ans, 2, as.numeric)

            t <- as.Date(txt[-seq_len(i), 1])
            ans <- zoo::zoo(ans, t)
            attr(ans, "headers") <- txt[seq_len(i), -1]

            colnames(ans) <- colnames(attr(ans, "headers"))  <-
                txt[i, -1]
        } else if (grepl("full_xru_csv.zip", f.path, fixed = TRUE)) {
            if (is.null(frequency)) {
                message(sQuote("frequency"), " set to ", sQuote("annual"))
                frequency <- "annual"
            } else if (!frequency %in% c("annual", "quarterly", "monthly")) {
                stop(sQuote("frequency"), " must be ",
                     sQuote("annual"), ", ",
                     sQuote("quarterly"), " or ",
                     sQuote("monthly"))
            }
            if (frequency == "annual") {
                t.re <- "^[0-9]{4}$"
                txt <- txt[txt$FREQ == "A", ]
                t <- colnames(txt)[grepl(t.re, colnames(txt))]

                ans <- t(txt[, grepl(t.re, colnames(txt))])
                ans <- zoo::zoo(ans, t)
                j <- which(colnames(txt) == "Series")
                attr(ans, "headers") <- t(txt[, seq_len(j)])
                colnames(ans) <- colnames(attr(ans, "headers")) <- txt[, j]
            } else if (frequency == "quarterly") {
                t.re <- "^[0-9]{4}-Q[0-9]$"
                txt <- txt[txt$FREQ == "Q", ]
                t <- colnames(txt)[grepl(t.re, colnames(txt))]
                t <- zoo::as.yearqtr(t, format = "%Y-Q%q")
                ans <- t(txt[, grepl(t.re, colnames(txt))])
                ans <- zoo::zoo(ans, t)
                j <- which(colnames(txt) == "Series")
                attr(ans, "headers") <- t(txt[, seq_len(j)])
                colnames(ans) <- colnames(attr(ans, "headers")) <- txt[, j]
            } else if (frequency == "monthly") {
                t.re <- "^[0-9]{4}-[^Q][0-9]$"
                txt <- txt[txt$FREQ == "M", ]
                t <- colnames(txt)[grepl(t.re, colnames(txt))]
                t <- zoo::as.yearmon(t)
                ans <- t(txt[, grepl(t.re, colnames(txt))])
                ans <- zoo::zoo(ans, t)
                j <- which(colnames(txt) == "Series")
                attr(ans, "headers") <- t(txt[, seq_len(j)])
                colnames(ans) <- colnames(attr(ans, "headers")) <- txt[, j]
            }
        } else if (grepl("full_cbpol_d_csv_row.zip", f.path, fixed = TRUE)) {
            i <- which(txt[, 1L] == "Time Period")
            ans <- txt[-seq_len(i), -1]
            ans <- apply(ans, 2, as.numeric)/100
            ans <- zoo::zoo(ans, as.Date(txt[-seq_len(i), 1]))
            attr(ans, "headers") <- txt[seq_len(i), -1]
            colnames(ans) <- txt[i, -1]
            rownames(attr(ans, "headers")) <- txt[seq_len(i), 1]
            colnames(attr(ans, "headers")) <- txt[i, -1]
        } else
            ans <- txt

    } else
        ans <- txt
    ans
}
