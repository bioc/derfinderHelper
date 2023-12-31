#' Calculate F-statistics per base by extracting chunks from a DataFrame
#'
#' Extract chunks from a DataFrame and get the F-statistics on the rows of
#' `data`, comparing the models `mod` (alternative) and `mod0`
#' (null).
#'
#' @param index An index (logical Rle is the best for saving memory) indicating
#' which rows of the DataFrame to use.
#' @param data The DataFrame containing the coverage information. Normally
#' stored in `coveragePrep$coverageProcessed` from
#' `derfinder::preprocessCoverage`. Could also be the full data from
#' `derfinder::loadCoverage`.
#' @param mod The design matrix for the alternative model. Should be m by p
#' where p is the number of covariates (normally also including the intercept).
#' @param mod0 The design matrix for the null model. Should be m by p_0.
#' @param adjustF A single value to adjust that is added in the denominator of
#' the F-stat calculation. Useful when the Residual Sum of Squares of the
#' alternative model is very small.
#' @param lowMemDir The directory where the processed chunks are saved when
#' using `derfinder::preprocessCoverage` with a specified `lowMemDir`.
#' @param method Has to be either 'Matrix' (default), 'Rle' or 'regular'. See
#' details.
#' @param scalefac The scaling factor used in
#' `derfinder::preprocessCoverage`. It is only used when
#' `method='Matrix'`.
#'
#' @details If `lowMemDir` is specified then `index` is expected to
#' specify the chunk number.
#'
#' [fstats.apply] has three different implemenations which are controlled
#' by the `method` parameter. `method='regular'` coerces the data to
#' a standard 'matrix' object. `method='Matrix'` coerces the data to a
#' [sparseMatrix][Matrix::sparseMatrix] which reduces the required memory. This method
#' is only usable when the projection matrices have row sums equal to 0. Note
#' that these row sums are not exactly 0 due to how the computer works, thus
#' leading to very small numerical differences in the F-statistics calculated
#' versus `method='regular'`. Finally, `method='Rle'` calculates the
#' F-statistics using the Rle compressed data without coercing it to other
#' types of objects, thus using less memory that the other methods. However,
#' it's speed is affected by the number of samples (n) as the current
#' implementation requires n (n + 1) operations, so it's only recommended for
#' small data sets. `method='Rle'` does result in small numerical
#' differences versus `method='regular'`.
#'
#' Overall `method='Matrix'` is faster than the other options and requires
#' less memory than `method='regular'`. With tiny example data sets,
#' `method='Matrix'` can be slower than `method='regular'` because the
#' coercion step is slower.
#'
#' In derfinder versions <= 0.0.62, `method='regular'` was the only option
#' available.
#'
#' @return A numeric Rle with the F-statistics per base for the chunk in
#' question.
#'
#' @author Leonardo Collado-Torres, Jeff Leek
#' @export
#' @importFrom S4Vectors Rle
#' @importMethodsFrom S4Vectors as.numeric Reduce sapply
#' @importMethodsFrom IRanges as.data.frame as.matrix ncol nrow which '['
#' unlist
#' @importFrom Matrix sparseMatrix
#' @importMethodsFrom Matrix '%*%' drop as.matrix
#' @import IRanges
#' @importFrom methods is
#'
#' @examples
#' ## Create some toy data
#' library("IRanges")
#' toyData <- DataFrame(
#'     "sample1" = Rle(sample(0:10, 1000, TRUE)),
#'     "sample2" = Rle(sample(0:10, 1000, TRUE)),
#'     "sample3" = Rle(sample(0:10, 1000, TRUE)),
#'     "sample4" = Rle(sample(0:10, 1000, TRUE))
#' )
#'
#' ## Create the model matrices
#' group <- c("A", "A", "B", "B")
#' mod.toy <- model.matrix(~group)
#' mod0.toy <- model.matrix(~ 0 + rep(1, 4))
#'
#' ## Get the F-statistics
#' fstats <- fstats.apply(
#'     data = toyData, mod = mod.toy, mod0 = mod0.toy,
#'     scalefac = 1
#' )
#'
#'
#' ## Example with data from derfinder package
#' \dontrun{
#' ## Load the data
#' library("derfinder")
#'
#' ## Create the model matrices
#' mod <- model.matrix(~ genomeInfo$pop)
#' mod0 <- model.matrix(~ 0 + rep(1, nrow(genomeInfo)))
#'
#' ## Run the function
#' system.time(fstats.Matrix <- fstats.apply(
#'     data = genomeData$coverage, mod = mod,
#'     mod0 = mod0, method = "Matrix", scalefac = 1
#' ))
#' fstats.Matrix
#'
#' ## Compare methods
#' system.time(fstats.regular <- fstats.apply(
#'     data = genomeData$coverage,
#'     mod = mod, mod0 = mod0, method = "regular"
#' ))
#' system.time(fstats.Rle <- fstats.apply(
#'     data = genomeData$coverage, mod = mod,
#'     mod0 = mod0, method = "Rle"
#' ))
#'
#' ## Small numerical differences can occur
#' summary(fstats.regular - fstats.Matrix)
#' summary(fstats.regular - fstats.Rle)
#'
#' ## You can make the effect negligible by appropriately rounding
#' ## findRegions(cutoff) so the DERs will be the same regardless of the method
#' ## used.
#'
#' ## Extra comparison, although the method to compare against is 'regular'
#' summary(fstats.Rle - fstats.Matrix)
#' }
#'
fstats.apply <- function(
        index = Rle(TRUE, nrow(data)), data, mod, mod0,
        adjustF = 0, lowMemDir = NULL, method = "Matrix", scalefac = 32) {
    ## Check for valid method
    stopifnot(method %in% c("Matrix", "Rle", "regular"))
    stopifnot(scalefac >= 0)

    # A function for calculating F-statistics
    # on the rows of dat, comparing the models
    # mod (alternative) and mod0 (null).

    ## Load the chunk file
    if (!is.null(lowMemDir)) {
        data <- .loadChunk(lowMemDir = lowMemDir, index = index)
    } else {
        if (!all(index)) {
            ##  Subset the DataFrame to the current chunk
            data <- data[index, ]
        }
    }

    ## General setup
    n <- ncol(data)
    m <- nrow(data)
    Id <- diag(n)
    df1 <- ncol(mod)
    df0 <- ncol(mod0)

    ## Get projection matrices
    P1 <- (Id - mod %*% solve(t(mod) %*% mod) %*% t(mod))
    P0 <- (Id - mod0 %*% solve(t(mod0) %*% mod0) %*% t(mod0))

    ## Determine which method to use
    useMethod <- method
    if (useMethod == "Matrix") {
        useMethod <- ifelse(all(sapply(list(P0, P1), function(x) {
            round(max(rowSums(x)), 4) == 0
        })), "Matrix", "regular")
        if (useMethod == "regular") {
            warning("Switching to method 'regular' because the row sums of the projection matrices are not 0. This can happen when a model matrix does not have an intercept term.")
        }
    } else if (useMethod == "Rle") {
        if (n > 40) {
            warning("Let n be the number of samples in the data. The implementation of method='Rle' requires n(n + 1) operations and thus gets considerably slower as n increases. Consider using chunks and method='Matrix'")
        }
    }

    ## Transform data
    if (useMethod == "Matrix") {
        if (!is(data, "dgCMatrix")) {
            data <- .transformSparseMatrix(data = data, scalefac = scalefac)
        }
    } else if (useMethod == "regular") {
        ##  Transform to a regular matrix
        if (!is(data, "dgCMatrix")) {
            data <- as.matrix(as.data.frame(data))
        } else {
            data <- as.matrix(data)
        }
    }

    ## How to calculate RSS and F-stats
    calculateMethod <- useMethod == "Matrix" | useMethod == "regular"

    ## Calculate RSS
    if (calculateMethod) {
        rss1 <- .calcRSS(data = data, P = P1, n = n)
        rss0 <- .calcRSS(data = data, P = P0, n = n)
    } else {
        rss1 <- .calcRSSRle(data = data, P = P1, n = n)
        rss0 <- .calcRSSRle(data = data, P = P0, n = n)
    }

    ## Get the F-stats
    if (calculateMethod) {
        fstats <- Rle(drop(((rss0 - rss1) / (df1 - df0)) / (adjustF + rss1 /
            (n - df1))))
    } else {
        fstats <- ((rss0 - rss1) / (df1 - df0)) / (adjustF + rss1 / (n - df1))
    }

    ## Done
    return(fstats)
}

## Load chunk
.loadChunk <- function(lowMemDir, index) {
    chunkProcessed <- NULL
    load(file.path(lowMemDir, paste0("chunk", index, ".Rdata")))
    return(chunkProcessed)
}

## Coerce to sparseMatrix
.transformSparseMatrix <- function(data, scalefac) {
    scalefac.log2 <- ifelse(scalefac <= 0, 0, log2(scalefac))

    ## Build Matrix object from a DataFrame
    i.list <- sapply(data, function(x) {
        which(x > scalefac.log2)
    },
    simplify = FALSE
    )
    i <- unlist(i.list, use.names = FALSE)
    j <- rep(seq_len(ncol(data)), sapply(i.list, length))
    ll <- unlist(data, use.names = FALSE)
    x <- as.numeric(ll[ll > scalefac.log2]) - scalefac.log2

    ## Build final object
    sparseMatrix(i = i, j = j, x = x, dims = c(nrow(data), ncol(data)), giveCsparse = TRUE, symmetric = FALSE, index1 = TRUE)
}

## Calculate RSS
.calcRSS <- function(data, P, n) {
    resid <- data %*% P
    (resid * resid) %*% rep(1L, n)
}
.calcRSSRle <- function(data, P, n) {
    Reduce("+", lapply(.residRle(P = P, n = n, data = data), "^", 2))
}

## Calculating residuals in Rle form
.residRle <- function(P, n = n, data) {
    ## This is a matrix multiplication done manually
    lapply(seq_len(n), function(i) {
        Reduce("+", mapply(function(rle, p) {
            rle * p
        }, data, P[, i]))
    })
}
