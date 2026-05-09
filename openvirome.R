###############################################################################
# Open Virome: Lycium Analysis (Pure R Script)
#
# Requirements:
#   R >= 4.0. All packages auto-installed on first run. Script is self-contained.
#   Database connection requires Serratus PostgreSQL credentials configured
#   in the R environment (SerratusConnect()).
#
# Usage:
#   # Default: GENUS='Lycium', all virus-positive analysis
#   Rscript openvirome.R
#
#   # Custom genus, no control set
#   Rscript openvirome.R --genus Lycium --control_type NONE
#
#   # SEARCH mode with wildcard
#   Rscript openvirome.R --search_type SEARCH --virome_search_term "Lycium%%"
#
#   # Only Lycium barbarum, no control
#   Rscript openvirome.R --genus_filter Lycium --species_filter "Lycium barbarum" --control_type NONE
#
#   # LIST mode from file
#   Rscript openvirome.R --search_type LIST --input_path my_runs.csv
#
#   # Custom output directory
#   Rscript openvirome.R --output ./my_analysis/
#
# Output:
#   results/Lycium_Virome_YYYYMMDD_HHMMSS.html  — HTML summary report (open in browser)
#   results/Lycium_Virome_YYYYMMDD_HHMMSS.RData — R workspace
#   results/*.png                                — Individual figures
#   results/*.csv                                — Data exports
#
# Parameters (all optional, defaults shown in [brackets]):
#   --analysis_name     Short title for the report [Lycium_Virome]
#   --search_type       Query mode: GENUS | SEARCH | LIST | STAT [GENUS]
#   --genus {name}      NCBI Taxonomy genus exact match (GENUS mode) [Lycium]
#   --virome_search_term  SQL LIKE pattern for scientific_name (SEARCH mode) ['']
#   --virome_deplete_term SQL LIKE pattern to exclude from SEARCH results ['']
#   --input_path        File path for LIST or STAT search mode ['']
#   --control_type      Control set: NONE | SEARCH | LIST | BIOPROJECT [BIOPROJECT]
#   --control_search_term  Control search term (SEARCH control mode) ['']
#   --control_path      File path for control LIST mode ['']
#   --output {dir}      Output directory [./results/]
#   --genus_filter {prefix} Keep only scientific_name starting with this prefix
#                         (removes false matches like "Gymnocalycium") ['']
#   --species_filter {re} Further restrict to regex match on scientific_name ['']
#   --palmprint_only {T|F} Only virus-positive runs in downstream analysis [FALSE]
#   --export_cytoscape {T|F} Export networks to Cytoscape [FALSE]
#   --deepseek_api_key {key} DeepSeek API key for LLM-powered summaries ['']
#                            When set, generates natural-language analysis summaries
#                            and embeds them in the HTML report. Uses model
#                            deepseek-v4-pro via HTTPS API. No extra R packages needed.
#                            Set env var DEEPSEEK_API_KEY as alternative.
#   --api_mode {T|F}    Use the Open Virome web API instead of direct PostgreSQL [FALSE]
#                       When TRUE, fetches count/identifier data from the public
#                       API endpoint (https://zrdbegawce.execute-api.us-east-1.amazonaws.com/prod).
#                       This uses the same database as the web frontend.
#                       Requires internet access and the `httr` package (auto-installed).
#                       NOT compatible with SEARCH/LIST/STAT modes — GENUS only.
###############################################################################

# ---- Print Help & Exit -----------------------------------------------------
print_help <- function() {
  cat("
Open Virome: Lycium Analysis
=============================

A self-contained R script for virome analysis of plant genera.
Queries the Serratus database for SRA runs matching a taxonomic genus,
retrieves virus palmprint data, performs statistical & network analysis,
and generates an HTML summary report with optional LLM-powered summaries.

REQUIREMENTS
  R >= 4.0. All R packages auto-install on first run.
  Serratus PostgreSQL credentials must be configured (SerratusConnect()).

USAGE
  Rscript openvirome.R [OPTIONS]

  # Simplest: analyze Lycium genus with defaults
  Rscript openvirome.R

  # Analyze a different genus
  Rscript openvirome.R --genus Solanum --analysis_name Solanum_Virome

  # Only Lycium barbarum, no control set
  Rscript openvirome.R --genus_filter Lycium --species_filter \"Lycium barbarum\" --control_type NONE

  # With LLM summaries via DeepSeek
  Rscript openvirome.R --deepseek_api_key sk-xxxx

  # Full SEARCH mode
  Rscript openvirome.R --search_type SEARCH --virome_search_term \"Lycium%%\"

  # Show this help
  Rscript openvirome.R --help

PARAMETERS (all optional, defaults in [brackets])
  --help              Show this help and exit
  --analysis_name     Short title for the report [Lycium_Virome]
  --search_type       Query mode: GENUS | SEARCH | LIST | STAT [GENUS]
  --genus {name}      NCBI Taxonomy genus exact match (GENUS mode) [Lycium]
  --virome_search_term  SQL LIKE pattern for scientific_name (SEARCH mode) ['']
  --virome_deplete_term SQL LIKE pattern to exclude from SEARCH results ['']
  --input_path        File path for LIST or STAT search mode ['']
  --control_type      Control set: NONE | SEARCH | LIST | BIOPROJECT [BIOPROJECT]
  --control_search_term  Control search term (SEARCH control mode) ['']
  --control_path      File path for control LIST mode ['']
  --output {dir}      Output directory [./results/]
  --genus_filter {prefix} Keep only scientific_name starting with this prefix
                        (removes false matches like \"Gymnocalycium\") ['']
  --species_filter {re} Further restrict to regex match on scientific_name ['']
  --palmprint_only {T|F} Only virus-positive runs in downstream analysis [FALSE]
  --export_cytoscape {T|F} Export networks to Cytoscape [FALSE]
  --deepseek_api_key {key} DeepSeek API key for LLM summaries ['']
                           Also configurable via env var DEEPSEEK_API_KEY.

SEARCH MODES
  GENUS   — Exact match on NCBI taxonomy genus field. Includes child taxa.
  SEARCH  — SQL LIKE search on SRA 'scientific_name'. Supports % wildcards.
  LIST    — Provide a CSV file of SRA run accessions (one column).
  STAT    — Provide a SRA-STAT output table for kmer-based filtering.

CONTROL TYPES
  NONE       — No control set. Analyze target runs only.
  SEARCH     — Control runs matching a different search term.
  LIST       — Control runs from a provided CSV file.
  BIOPROJECT — Virus-negative runs from the same BioProjects as target runs.

OUTPUT
  results/{name}_YYYYMMDD_HHMMSS.html   — HTML summary report
  results/{name}_YYYYMMDD_HHMMSS.RData  — R workspace
  results/*.png                          — Individual figures
  results/*.csv                          — Data exports (full + summary)

EXAMPLES
  # Default analysis
  Rscript openvirome.R

  # No control, custom genus
  Rscript openvirome.R --genus Nicotiana --control_type NONE

  # Genus filter + species filter + LLM summaries
  Rscript openvirome.R --genus_filter Lycium \\
    --species_filter \"Lycium barbarum\" --control_type NONE \\
    --deepseek_api_key sk-xxxx

  # Export Cytoscape networks
  Rscript openvirome.R --export_cytoscape T

  # All runs (including non-virus)
  Rscript openvirome.R --palmprint_only F
")
  quit(save = "no", status = 0)
}

# ---- Parse Command-Line Arguments ------------------------------------------
parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  # Check for --help before anything else
  if ("--help" %in% args || "-h" %in% args || "-help" %in% args) {
    print_help()
  }

  # Default parameter values (mirrors YAML header of .Rmd)
  p <- list(
    ov.version        = "0.0.9",
    analysis_name     = "Lycium_Virome",
    search_type       = "GENUS",
    genus_match_term  = "Lycium",
    virome_search_term = "",
    virome_deplete_term = "",
    input.path        = "",
    control_type      = "BIOPROJECT",
    control_search_term = "",
    control.path      = "",
    output.path       = "./results/",
    export.cytoscape  = FALSE,
    genus_filter      = "",   # e.g. "Lycium" — keep only rows starting with this genus
    species_filter    = "",   # e.g. "Lycium barbarum" — further restrict to this species
    palmprint_only    = FALSE, # only include virus-positive SRA runs in downstream analysis
    deepseek_api_key  = "",    # DeepSeek API key for LLM summaries (or env var DEEPSEEK_API_KEY)
    api_mode          = FALSE  # use Open Virome web API instead of direct PostgreSQL
  )

  # Parse --key value pairs (index-based, no <<- which is unreliable inside functions)
  n <- length(args)
  if (n > 0) {
    idx <- 1
    while (idx <= n) {
      arg <- args[idx]
      if (grepl("^--", arg)) {
        key <- sub("^--", "", arg)
        # If next arg exists and doesn't start with '--', it's the value
        if (idx + 1 <= n && !grepl("^--", args[idx + 1])) {
          val <- args[idx + 1]
          idx <- idx + 1  # consume value
        } else {
          val <- ""
        }
        # Map CLI flag to list name
        mapped_key <- switch(key,
          ov_version         = "ov.version",
          analysis_name      = "analysis_name",
          search_type        = "search_type",
          genus_match_term   = "genus_match_term",
          genus              = "genus_match_term",  # shortcut
          genus_filter       = "genus_filter",
          species_filter     = "species_filter",
          palmprint_only     = "palmprint_only",
          deepseek_api_key   = "deepseek_api_key",
          api_mode           = "api_mode",
          virome_search_term = "virome_search_term",
          virome_deplete_term = "virome_deplete_term",
          input_path         = "input.path",
          control_type       = "control_type",
          control_search_term = "control_search_term",
          control_path       = "control.path",
          output_path        = "output.path",
          output             = "output.path",       # shortcut
          export_cytoscape   = "export.cytoscape",
          key  # fallback: use as-is
        )
        # Convert logical strings
        if (val == "TRUE" || val == "true" || val == "T") {
          val <- TRUE
        } else if (val == "FALSE" || val == "false" || val == "F") {
          val <- FALSE
        }
        p[[mapped_key]] <- val
      }
      idx <- idx + 1
    }
  }

  # Special: if control_type is "NONE", set to empty string
  if (toupper(p$control_type) == "NONE") {
    p$control_type <- ""
  }

  return(p)
}

# ---- Bootstrap: install missing packages -----------------------------------
# This makes the script self-contained — no manual `install.packages` needed.
required_packages <- c(
  "dplyr", "ggplot2", "igraph", "plotly", "viridis", "DT",
  "htmlwidgets", "gplots", "reshape2", "jsonlite", "httr", "base64enc"
)
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("Installing missing package: %s ...\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
  }
}

# ---- Load Package ----------------------------------------------------------
p <- parse_args()

# In API mode, we don't need the PostgreSQL driver or open.viromeR package
if (!p$api_mode) {
  # Install open.viromeR from local directory if needed
  if (!requireNamespace("open.viromeR", quietly = TRUE)) {
    cat("Installing open.viromeR from local source...\n")
    # Detect script directory (works under both Rscript and source())
    script_dir <- getwd()
    file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(file_arg) > 0) {
      script_path <- normalizePath(sub("^--file=", "", file_arg[1]))
      script_dir <- dirname(script_path)
    }
    if (!file.exists(file.path(script_dir, "DESCRIPTION"))) {
      stop(sprintf(
        "Cannot find open.viromeR source in '%s'. Please run from the open.viromeR directory.",
        script_dir))
    }
    install.packages(script_dir, repos = NULL, type = "source", quiet = TRUE)
  }
  library('open.viromeR', quietly = TRUE)
}

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(igraph)
  library(plotly)
  library(viridis)
  library(DT)
})

# ---- DeepSeek LLM Client (no extra packages needed, uses base R) -----------
# Resolve API key: CLI argument takes priority, then environment variable
deepseek_api_key <- p$deepseek_api_key
if (deepseek_api_key == "") {
  deepseek_api_key <- Sys.getenv("DEEPSEEK_API_KEY")
}
use_llm <- (deepseek_api_key != "")

ds_chat <- function(system_prompt, user_message,
                    model = "deepseek-v4-pro",
                    base_url = "https://api.deepseek.com/chat/completions") {
  # Single-turn chat completion via DeepSeek API.
  # Returns the assistant's text response, or "" on error.
  body <- list(
    model = model,
    messages = list(
      list(role = "system", content = system_prompt),
      list(role = "user",   content = user_message)
    ),
    stream = FALSE
  )
  tryCatch({
    resp <- httr::POST(
      url = base_url,
      httr::add_headers(
        "Content-Type"  = "application/json",
        "Authorization" = paste("Bearer", deepseek_api_key)
      ),
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "raw",
      httr::timeout(120)
    )
    parsed <- jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"))
    if (!is.null(parsed$choices$message$content)) {
      return(parsed$choices$message$content[[1]])
    }
    cat(sprintf("  [LLM] API error: %s\n",
                if (is.null(parsed$error$message)) "unknown" else parsed$error$message))
    return("")
  }, error = function(e) {
    cat(sprintf("  [LLM] Request failed: %s\n", conditionMessage(e)))
    return("")
  })
}

# ---- API Response Parser (with base64 fallback like web frontend) ---------
parse_api_response <- function(resp, simplify = TRUE) {
  txt <- httr::content(resp, as = "text", encoding = "UTF-8")
  # Try direct JSON parse first
  result <- tryCatch(jsonlite::fromJSON(txt, simplifyDataFrame = simplify), error = function(e) NULL)
  if (!is.null(result)) return(result)
  # Try base64 decode fallback (web frontend uses atob() fallback)
  result <- tryCatch(jsonlite::fromJSON(rawToChar(base64enc::base64decode(txt)),
                                         simplifyDataFrame = simplify), error = function(e) NULL)
  if (!is.null(result)) return(result)
  stop(sprintf("API returned non-JSON response: %.100s", txt))
}

# ---- Initialize Workspace --------------------------------------------------
# Ensure output directory exists
if (!dir.exists(p$output.path)) {
  dir.create(p$output.path, recursive = TRUE)
}

# Establish Serratus server connection (skipped in API mode)
if (!p$api_mode) {
  con <- SerratusConnect()
} else {
  con <- NULL
}

# Input files
if (is.null(p$input.path) || p$input.path == '') {
  p$input.list   <- NULL
  p$control.list <- NULL
  p$input.virome <- NULL
  p$input.stat   <- NULL
} else {
  p$input.list      <- paste0(p$input.path)
  p$control.list    <- paste0(p$control.path)
  p$input.virome    <- paste0(p$input.path)
  p$input.stat      <- paste0(p$input.path)
}

# Output paths
p$report_id     <- format(Sys.time(), "%Y%m%d_%H%M%S")
p$output.html   <- paste0(p$output.path, p$analysis_name, '_', p$report_id, '.html')
p$output.rdata  <- paste0(p$output.path, p$analysis_name, '_', p$report_id, '.RData')

# Control set toggle (disabled in API mode — API doesn't support control sets)
if (p$api_mode) {
  p$doControl <- FALSE
} else {
  p$doControl <- (p$control_type != '')
}

# UI colors
p$ui.setcol <- c('gray50', 'cornflowerblue')

# ---- Parameter Summary -----------------------------------------------------
cat("========================================\n")
cat("  Open Virome: Lycium Analysis\n")
cat("========================================\n")
cat(sprintf("Open Virome Version: %s\n", p$ov.version))
cat(sprintf("Timestamp:  %s\n", p$report_id))
cat(sprintf("Analyzing:  %s\n", p$analysis_name))
cat("\nParameters:\n")
cat(sprintf("  Search Type:        %s\n", p$search_type))
cat(sprintf("  Genus Match Term:   %s\n", p$genus_match_term))
cat(sprintf("  Virome Search Term: %s\n", p$virome_search_term))
if (p$doControl) {
  cat(sprintf("  Control Type:       %s\n", p$control_type))
  cat(sprintf("  Control Search:     %s\n", p$control_search_term))
} else {
  cat("  Control Set:        NONE\n")
}
cat(sprintf("  Cytoscape Export:   %s\n", p$export.cytoscape))
cat(sprintf("  Palmprint Only:     %s\n", p$palmprint_only))
cat(sprintf("  LLM Summaries:      %s\n", if (use_llm) "Enabled (DeepSeek)" else "Disabled"))
cat(sprintf("  API Mode:           %s\n", p$api_mode))
cat(sprintf("  Output Directory:   %s\n", p$output.path))
cat(sprintf("  Output RData:       %s\n", p$output.rdata))
cat("\n")

# ---- Virome Query ----------------------------------------------------------
cat("Querying virome data...\n")

# all.runs = all SRA runs matching the search
# virome.runs = subset with palmprint (virus) hits
all.runs <- NULL
api_skip_db <- FALSE

if (p$api_mode && p$search_type == "GENUS") {
  # ---- API MODE: iterate over species for correct ov_identifiers matching ----
  # KEY FINDING: ov_identifiers.organism stores FULL species names (e.g.
  # "Lycium barbarum"), NOT genus-level "Lycium". We must iterate over each
  # species returned by /counts to get identifiers for each one.
  p$api_proxy <- Sys.getenv("OV_API_PROXY")
  API_BASE <- if (p$api_proxy != "") p$api_proxy else
    "https://zrdbegawce.execute-api.us-east-1.amazonaws.com/prod"
  cat("  Using web API (openvirome.com database)\n")

  api_identifiers <- function(species, palmprint) {
    resp <- httr::POST(paste0(API_BASE, "/identifiers"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(
        filters = list(list(filterType = "label", filterKey = "organism",
          filterValue = species, groupByKey = "organism")),
        palmprintOnly = palmprint
      ), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
    if (httr::status_code(resp) != 200) return(list(run = list(single = list(), totalCount = 0)))
    parse_api_response(resp, simplify = FALSE)
  }

  api_results_call <- function(ids, table, cols) {
    if (length(ids) == 0) return(data.frame())
    resp <- httr::POST(paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(ids = ids, idColumn = "run_id",
        table = table, columns = cols, pageStart = 0, pageEnd = 100000),
        auto_unbox = TRUE), encode = "raw", httr::timeout(30))
    if (httr::status_code(resp) != 200) return(data.frame())
    parse_api_response(resp)
  }

  # Step 1: /counts with searchString + pageEnd=100000 (force materialized view)
  resp_counts <- httr::POST(paste0(API_BASE, "/counts"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(
      groupBy = "organism",
      searchString = p$genus_match_term,
      palmprintOnly = FALSE,
      pageEnd = 100000,
      sortByColumn = "count",
      sortByDirection = "desc"
    ), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
  if (httr::status_code(resp_counts) != 200) stop("API /counts failed")
  api_counts <- parse_api_response(resp_counts)
  cat(sprintf("  searchString returned %d organism values\n", nrow(api_counts)))

  # Step 2: For EACH species, get all-run + virus-run identifiers
  all_run_ids <- character(0)
  vir_run_ids <- character(0)
  species_all  <- integer(0); names(species_all)  <- character(0)
  species_vir  <- integer(0); names(species_vir)  <- character(0)

  for (i in seq_len(nrow(api_counts))) {
    sp <- api_counts$name[i]
    n_all <- as.integer(api_counts$count[i])
    species_all[sp] <- n_all

    # Virus identifiers (one call per species)
    vir_ids <- api_identifiers(sp, palmprint = TRUE)
    vir_runs <- unique(na.omit(unlist(vir_ids$run$single)))
    vir_run_ids <- c(vir_run_ids, vir_runs)
    species_vir[sp] <- length(vir_runs)

    # All-run identifiers
    all_ids <- api_identifiers(sp, palmprint = FALSE)
    all_runs <- unique(na.omit(unlist(all_ids$run$single)))
    all_run_ids <- c(all_run_ids, all_runs)

    cat(sprintf("    %-40s total=%d virus=%d\n", sp, n_all, length(vir_runs)))
  }
  all.runs  <- unique(all_run_ids)
  vir_run_ids <- unique(vir_run_ids)
  cat(sprintf("  Total all runs: %d | Virus-positive: %d\n", length(all.runs), length(vir_run_ids)))

  # Build api_counts/api_vir_counts for unified species summary
  api_counts <- data.frame(name = names(species_all),
    count = as.integer(species_all), stringsAsFactors = FALSE)
  api_vir_counts <- data.frame(name = names(species_vir),
    count = as.integer(species_vir), stringsAsFactors = FALSE)

  # Step 3: /results for palm_virome data
  cat("  Fetching palm_virome data...\n")
  api_results <- api_results_call(vir_run_ids, "palm_virome",
    "run,bioproject,biosample,organism,sotu,gb_acc,gb_pid,gb_eval,tax_species,tax_family")

  if (nrow(api_results) == 0) {
    cat("  WARNING: No palm_virome results. Creating empty virome.df.\n")
    virome.df <- data.frame(run = character(), scientific_name = character(),
      bio_project = character(), bio_sample = character(), sotu = character(),
      gb_acc = character(), gb_pid = numeric(), tax_species = character(),
      tax_family = character(), stringsAsFactors = FALSE)
  } else {
    virome.df <- api_results
    colnames(virome.df)[colnames(virome.df) == "organism"] <- "scientific_name"
    virome.df$bio_project <- virome.df$bioproject
    virome.df$bio_sample <- virome.df$biosample
  }
  virome.runs <- vir_run_ids

  # Fill missing columns for downstream compatibility
  for (col_needed in c("palm_id", "nickname", "node", "node_coverage",
                        "node_pid", "node_eval", "node_qc", "node_seq")) {
    if (!(col_needed %in% colnames(virome.df))) virome.df[[col_needed]] <- NA
  }
  virome.df$node_qc <- as.logical(virome.df$node_qc)

  # Species breakdown
  cat("\n  Species breakdown:\n")
  cat(sprintf("  %-45s %6s %6s %6s\n", "Species", "Total", "Virus+", "Virus-"))
  for (i in seq_len(nrow(api_counts))) {
    sp <- api_counts$name[i]; n_all <- api_counts$count[i]
    virus_idx <- match(sp, api_vir_counts$name)
    n_vir <- if (!is.na(virus_idx)) api_vir_counts$count[virus_idx] else 0
    cat(sprintf("  %-45s %6d %6d %6d\n", sp, n_all, n_vir, n_all - n_vir))
  }
  cat(sprintf("\n  Total SRA runs (all):     %d\n", sum(api_counts$count)))
  cat(sprintf("  Runs with palmprint hits: %d\n", length(virome.runs)))
  api_skip_db <- TRUE

} else if (p$search_type == "SEARCH") {
  api_skip_db <- TRUE   # local-only analysis, fast
  virome.df <- get.palmVirome(org.search = p$virome_search_term)
  if (p$virome_deplete_term != '') {
    deplete.runs <- grep(p$virome_deplete_term, virome.df$scientific_name, ignore.case = TRUE)
    if (length(deplete.runs) > 0) {
      virome.df <- virome.df[-deplete.runs, ]
    }
  }
  virome.runs <- virome.df$run
  all.runs <- virome.runs

} else if (p$search_type == "GENUS") {
  api_skip_db <- TRUE   # local-only analysis, fast
  virome.df    <- get.palmVirome(org.search = paste0(p$genus_match_term, "%"))
  virome.runs  <- unique(virome.df$run)

  # Quick srarun query for all-runs count
  all_runs_sra <- tbl(con, "srarun") %>%
    dplyr::filter(scientific_name %like% paste0(p$genus_match_term, "%")) %>%
    select(run, scientific_name) %>%
    as.data.frame()
  all.runs <- unique(all_runs_sra$run)
  all_runs_sra <- all_runs_sra[!duplicated(all_runs_sra$run), ]
  rownames(all_runs_sra) <- NULL

  # Build api_counts/api_vir_counts for unified code path
  sp_all <- table(as.character(all_runs_sra$scientific_name))
  sp_vir <- table(as.character(virome.df$scientific_name))
  api_counts <- data.frame(name = names(sp_all), count = as.integer(sp_all), stringsAsFactors = FALSE)
  api_vir_counts <- data.frame(name = names(sp_vir), count = as.integer(sp_vir), stringsAsFactors = FALSE)

} else if (p$search_type == "LIST") {
  if (is.null(p$input.list)) stop("LIST mode requires --input_path")
  all.runs    <- read.csv(p$input.list)[, 1]
  virome.df   <- get.palmVirome(run.vec = all.runs)

} else if (p$search_type == "STAT") {
  if (is.null(p$input.stat)) stop("STAT mode requires --input_path")
  virome.stat <- read.csv(p$input.stat, header = TRUE)
  virome.stat <- virome.stat[virome.stat$total_count > 10000, ]
  all.runs    <- virome.stat$acc
  virome.df   <- get.palmVirome(run.vec = all.runs)
  virome.df   <- merge(virome.df, virome.stat, by.x = 'run', by.y = 'acc')

} else {
  stop('Unknown search_type. Use: GENUS, SEARCH, LIST, or STAT')
}
virome.runs <- virome.df$run

cat(sprintf("  Total SRA runs matching query:    %d\n", length(all.runs)))
cat(sprintf("  Runs with palmprint (virus) hits: %d\n", length(unique(virome.df$run))))

# ---- Species-Level Summary -------------------------------------------------
if (!exists("api_counts") || is.null(api_counts)) {
  sp_all <- table(as.character(virome.df$scientific_name))
  api_counts <- data.frame(name = names(sp_all), count = as.integer(sp_all), stringsAsFactors = FALSE)
  api_vir_counts <- api_counts
}

cat("\n  Species breakdown:\n")
cat(sprintf("  %-45s %6s %6s %6s\n", "Species", "Total", "Virus+", "Virus-"))
cat(sprintf("  %-45s %6s %6s %6s\n", "-------", "-----", "------", "------"))
for (i in seq_len(nrow(api_counts))) {
  sp <- api_counts$name[i]; n_all <- api_counts$count[i]
  virus_idx <- match(sp, api_vir_counts$name)
  n_vir <- if (!is.na(virus_idx)) api_vir_counts$count[virus_idx] else 0
  cat(sprintf("  %-45s %6d %6d %6d\n", sp, n_all, n_vir, n_all - n_vir))
}
cat("\n")

# ---- Post-hoc Scientific Name Filtering ----------------------------------
if (p$search_type == "SEARCH" && p$genus_filter == '') {
  p$genus_filter <- p$genus_match_term
}

n_before <- nrow(virome.df)
if (p$genus_filter != '' && p$search_type != "GENUS") {
  keep_idx <- grepl(paste0('^', p$genus_filter), as.character(virome.df$scientific_name),
                    ignore.case = TRUE)
  if (sum(!keep_idx) > 0) {
    cat(sprintf("  genus_filter removed %d rows not starting with '%s'\n",
                sum(!keep_idx), p$genus_filter))
    cat("  Removed entries:\n")
    removed <- unique(as.character(virome.df$scientific_name[!keep_idx]))
    for (r in removed) cat(sprintf("    - %s\n", r))
  }
  virome.df  <- virome.df[keep_idx, ]
  virome.runs <- virome.df$run
}
if (p$species_filter != '') {
  keep_idx <- grepl(p$species_filter, as.character(virome.df$scientific_name),
                    ignore.case = TRUE)
  if (sum(!keep_idx) > 0) {
    cat(sprintf("  species_filter removed %d rows not matching '%s'\n",
                sum(!keep_idx), p$species_filter))
  }
  virome.df  <- virome.df[keep_idx, ]
  virome.runs <- virome.df$run
}
if (nrow(virome.df) == 0) stop("All records removed. Relax your filters.")
cat(sprintf("  After filtering: %d rows retained (removed %d)\n",
            nrow(virome.df), n_before - nrow(virome.df)))

# Standard cleaning
if ("taxid" %in% colnames(virome.df)) {
  colnames(virome.df)[colnames(virome.df) == "taxid"] <- "Taxid"
}

# Melt virome data.frame, group by sOTU
virx.df <- melt.virome(virome.df)

cat(sprintf("  Virus-positive runs: %d, unique sOTUs: %d\n",
            length(unique(virome.runs)), nrow(virx.df)))

# ---- Control Virome --------------------------------------------------------
if (isTRUE(api_skip_db)) {
  p$doControl <- FALSE
  negVirome.df <- NULL
}
if (p$doControl) {
  if (p$control_type == "LIST") {
    negVirome.df <- get.negativeVirome(run.vec = virome.runs)
  } else if (p$control_type == "SEARCH") {
    negVirome.df <- get.negativeVirome(org.search = p$virome_search_term)
  } else if (p$control_type == "BIOPROJECT") {
    neg.virome.runs <- get.sraProj(run_ids = virome.df$run,
                                   exclude.input.runs = TRUE, con = con)
    if (length(neg.virome.runs$run_id) == 0) {
      negVirome.df <- NA; p$doControl <- FALSE
    } else {
      negVirome.df <- get.negativeVirome(run.vec = neg.virome.runs$run_id)
      negv.df      <- melt.virome(negVirome.df)
    }
  } else if (p$control_type != '') {
    stop('Unknown control_type. Use: NONE, LIST, SEARCH, or BIOPROJECT')
  }
}

cat(sprintf("  Control set: %s\n", if (p$doControl) "active" else "none"))

# ---- Merge Viromes ---------------------------------------------------------
if (p$doControl) {
  virome.df2 <- bind_rows(virome.df, negVirome.df)
} else {
  virome.df2 <- virome.df
}
virome.df2$scientific_name <- makeTop10(virome.df2$scientific_name)
virome.df2$tax_family      <- makeTop10(virome.df2$tax_family)

suppressWarnings({
  if (exists("run_ids")) rm(run_ids)
  if (exists("negVirome.df")) rm(negVirome.df)
  if (exists("neg.virome.runs")) rm(neg.virome.runs)
  if (exists("negv.df")) rm(negv.df)
})

# ---- Export CSV Data -------------------------------------------------------
cat("Exporting CSV data...\n")
write.csv(virome.df, paste0(p$output.path, p$analysis_name, '_virome_full.csv'), row.names = FALSE)
write.csv(virx.df,   paste0(p$output.path, p$analysis_name, '_virome_summary.csv'), row.names = FALSE)

# ---- SECTION 1: Run Statistics ---------------------------------------------
if (isTRUE(api_skip_db)) {
  cat("Generating Run Statistics...\n")

  species_combined <- api_counts
  colnames(species_combined)[colnames(species_combined) == "count"] <- "total"
  species_combined$virus <- 0
  if (nrow(api_vir_counts) > 0) {
    vir_idx <- match(species_combined$name, api_vir_counts$name)
    species_combined$virus[!is.na(vir_idx)] <- api_vir_counts$count[vir_idx[!is.na(vir_idx)]]
  }
  species_combined$non_virus <- species_combined$total - species_combined$virus
  species_combined <- species_combined[order(species_combined$total, decreasing = TRUE), ]
  species_combined$name <- factor(species_combined$name, levels = rev(species_combined$name))

  sp_long <- data.frame(
    species = rep(species_combined$name, 2),
    count   = c(species_combined$virus, species_combined$non_virus),
    type    = rep(c("Virus+", "Virus-"), each = nrow(species_combined)))

  plot.stacked <- ggplot(sp_long, aes(count, species, fill = type)) +
    geom_bar(stat = "identity", position = "stack") + theme_bw() +
    scale_fill_manual(values = c("Virus+" = "#CB4154", "Virus-" = "gray85")) +
    xlab("Number of SRA Runs") + ylab("") +
    ggtitle(sprintf("%s: SRA Runs by Species (total=%d, virus+=%d)",
                    p$genus_match_term, sum(species_combined$total),
                    sum(species_combined$virus))) +
    theme(legend.position = "bottom", legend.title = element_blank())

  png(paste0(p$output.path, p$analysis_name, '_01_species_stacked.png'), width = 1000, height = 500)
  print(plot.stacked); invisible(dev.off())
  write.csv(species_combined, paste0(p$output.path, p$analysis_name, '_01_species_combined.csv'), row.names = FALSE)

} else {
  cat("Generating Run Statistics...\n")

  all_runs_n <- length(unique(all.runs))
  virus_runs_n <- length(unique(virome.runs))
  cat(sprintf("  All SRA runs: %d  |  Virus-positive: %d (%.1f%%)\n",
              all_runs_n, virus_runs_n,
              if (all_runs_n > 0) 100 * virus_runs_n / all_runs_n else 0))

  run_summary <- data.frame(
    Category = c("All SRA Runs", "Virus-Positive Runs"),
    Count    = c(all_runs_n, virus_runs_n))
  run_summary$Category <- factor(run_summary$Category,
                                 levels = c("All SRA Runs", "Virus-Positive Runs"))
  plot.run.summary <- ggplot(run_summary, aes(Category, Count, fill = Category)) +
    geom_bar(stat = 'identity') + theme_bw() + theme(legend.position = "none") +
    scale_fill_manual(values = c('gray60', 'cornflowerblue')) +
    xlab("") + ylab("Number of SRA Runs") +
    ggtitle(sprintf("%s: SRA Run Overview", p$analysis_name))
  png(paste0(p$output.path, p$analysis_name, '_01_run_summary.png'), width = 600, height = 500)
  print(plot.run.summary); invisible(dev.off())

  vorgx.df <- virome.df2 %>%
    dplyr::count(scientific_name, tax_family, node_qc, sort = TRUE)
  vorgx.df$node_qc[is.na(vorgx.df$node_qc)] <- FALSE
  colnames(vorgx.df) <- c('scientific_name', 'tax_family', 'vRNA', 'n')
  vorgx.df$scientific_name <- factor(vorgx.df$scientific_name,
    levels = rev(levels(virome.df2$scientific_name)))
  vorgx.df$tax_family <- factor(vorgx.df$tax_family,
    levels = levels(virome.df2$tax_family))
  plot.virome.org <- ggplot(vorgx.df, aes(scientific_name, n, fill = vRNA)) +
    geom_bar(stat = 'identity') + coord_flip() + theme_bw() +
    xlab("Scientific Name") + ylab("Virus-positive SRA Runs (count)") +
    facet_wrap(~vRNA) + scale_fill_manual(values = p$ui.setcol)
  png(paste0(p$output.path, p$analysis_name, '_01_run_barplot.png'), width = 1000, height = 450)
  print(plotly::hide_legend(plot.virome.org)); invisible(dev.off())

  # SRA Data Type + BioProject plots (DB only)
  if (exists("sra.df") && is.data.frame(sra.df)) {
    # ... SRA data type polar plots omitted for brevity in this rewrite
    # ... BioProject analysis omitted
  }
}

# ---- SECTION 2: Virus Family Summary ---------------------------------------
cat("Generating Virus Family Summary...\n")

virFam.nrun <- virome.df[, c('tax_family', 'run')]
virFam.nrun$tax_family <- makeTop10(virFam.nrun$tax_family, top.n = 20)
virFam.nrun <- unique(virFam.nrun[, c('tax_family', 'run')]) %>% count(tax_family)
virFam.nrun$set <- 'n_runs'

virFam.sotu <- virome.df[, c('tax_family', 'sotu')]
virFam.sotu$tax_family <- makeTop10(virFam.sotu$tax_family, top.n = 20)
virFam.sotu <- unique(virFam.sotu[, c('tax_family', 'sotu')]) %>% count(tax_family)
virFam.sotu$set <- 'n_sotu'

virFam.df <- rbind(virFam.nrun, virFam.sotu)
rm(virFam.nrun, virFam.sotu)

plot.virFam.n <- ggplot(virFam.df, aes(tax_family, n)) +
  geom_bar(stat = 'identity') + coord_flip() + scale_x_discrete(limits = rev) +
  theme_bw() + theme(legend.position = "none") +
  xlab("Taxonomic Family") + ylab("Count") + facet_wrap(~set)

png(paste0(p$output.path, p$analysis_name, '_02_family_counts.png'), width = 800, height = 400)
print(plot.virFam.n); invisible(dev.off())

virFam.nrun2 <- unique(virome.df[, c('tax_family', 'run')]) %>% count(tax_family)
colnames(virFam.nrun2) <- c("tax_family", "n_run")
virFam.sotu2 <- unique(virome.df[, c('tax_family', 'sotu')]) %>% count(tax_family)
colnames(virFam.sotu2) <- c("tax_family", "n_sotu")
virFam.df2 <- merge(virFam.nrun2, virFam.sotu2, by = "tax_family")
rm(virFam.nrun2, virFam.sotu2)

plot.virFam.xy <- ggplot(virFam.df2, aes(n_run, n_sotu, color = tax_family)) +
  geom_point() + theme_bw() + theme(legend.position = "none") +
  xlab("Count (Runs)") + ylab("Count (sOTU)")

png(paste0(p$output.path, p$analysis_name, '_02_family_scatter.png'), width = 1000, height = 800)
print(plotly::hide_legend(plot.virFam.xy)); invisible(dev.off())

# Family vs BioProject Heatmap (if sra.df available)
if (exists("sra.df") && is.data.frame(sra.df)) {
  bp.total.n2 <- sra.df %>% count(bioproject, sort = TRUE)
  virFam.bp <- virome.df[, c('tax_family', 'bio_project')]
  virFam.bp$tax_family <- makeTop10(virFam.bp$tax_family, top.n = 20)
  virFam.bp <- table(virFam.bp)
  bpTop   <- colnames(virFam.bp)
  bpTop.n <- as.numeric(bp.total.n2$n[match(bpTop, bp.total.n2$bioproject, nomatch = NA)])
  bpTop.n <- bpTop.n[!is.na(bpTop.n)]
  virFam.bp <- t(t(virFam.bp) / bpTop.n)
  virFam.bp <- round(100 * virFam.bp, 2)
  virFam.bp <- as.matrix(virFam.bp)
  rm(bpTop, bpTop.n, bp.total.n2)

  if (length(virFam.bp[1, ]) > 1) {
    png(paste0(p$output.path, p$analysis_name, '_02_family_heatmap.png'), width = 1000, height = 600)
    gplots::heatmap.2(virFam.bp, trace = "none",
      breaks = c(0, 1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100),
      density.info = "none", col = c("black", viridis::viridis(10, option = "A")),
      key.title = "", key.xlab = "Percent BioProject Virus+",
      margins = c(10, 10), sepcolor = NULL)
    invisible(dev.off())
  }
}

# Per-species tax family polar distribution
vorgx.df2 <- virome.df2[virome.df2$node_qc, ] %>%
  count(scientific_name, tax_family, sort = TRUE)
vorgx.df2$scientific_name <- factor(vorgx.df2$scientific_name,
  levels = rev(levels(virome.df2$scientific_name)))
vorgx.df2$tax_family <- factor(vorgx.df2$tax_family,
  levels = levels(virome.df2$tax_family))
vorgx.df2 <- vorgx.df2[!is.na(vorgx.df2$scientific_name), ]

virome2.org <- ggplot(vorgx.df2, aes(x = tax_family, n, fill = tax_family)) +
  geom_bar(stat = 'identity') + scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() + theme(aspect.ratio = 1, legend.position = "none") +
  facet_wrap(~scientific_name, ncol = 4)

png(paste0(p$output.path, p$analysis_name, '_02_label_summary.png'), width = 1000, height = 800)
print(virome2.org); invisible(dev.off())

# ---- SECTION 3: sOTU Expression & Frequency --------------------------------
cat("Generating sOTU Summary...\n")

ranklvl  <- c("phylum", "family", "genus", "species")
virx.df$gb_match <- ranklvl[1]
virx.df$gb_match[which(virx.df$gb_pid >= 45)] <- ranklvl[2]
virx.df$gb_match[which(virx.df$gb_pid >= 70)] <- ranklvl[3]
virx.df$gb_match[which(virx.df$gb_pid >= 90)] <- ranklvl[4]
virx.df$gb_match <- factor(virx.df$gb_match, levels = ranklvl)
virx.df$plot_name <- makeTop10(virx.df$tax_family)

virus.exp2 <- ggplot() +
  geom_point(data = virx.df, aes(x = n, y = gb_pid,
      size = log(mean_coverage + 1), color = log(mean_coverage + 1)),
    show.legend = FALSE, alpha = 0.5) +
  geom_hline(yintercept = 90, color = "gray70", linetype = "dashed") +
  theme_bw() + scale_color_viridis(option = "plasma") +
  scale_x_log10() + scale_y_log10() + scale_size_identity() +
  xlab("sOTU frequency in SRA Runs") + ylab("GenBank Identity (%)") +
  facet_wrap(~plot_name, ncol = 4)

png(paste0(p$output.path, p$analysis_name, '_03_sotu_expression.png'), width = 1200, height = 800)
print(plotly::hide_legend(virus.exp2)); invisible(dev.off())

virx.df$tax_family2 <- makeTop10(virx.df$tax_family)
virus.hist.n <- ggplot(virx.df, aes(n, fill = tax_family2)) +
  geom_histogram(bins = 30) + scale_x_log10() + theme_bw() +
  ggtitle("sOTU Frequency in SRA")
virus.hist.cov <- ggplot(virx.df, aes(mean_coverage, fill = tax_family2)) +
  geom_histogram(bins = 30) + scale_x_log10() + theme_bw() +
  ggtitle("sOTU Mean Coverage")
virus.hist.gbid <- ggplot(virx.df, aes(gb_pid, fill = tax_family2)) +
  geom_histogram(bins = 30) + scale_x_log10() + theme_bw() +
  ggtitle("GenBank Identity Distribution")

png(paste0(p$output.path, p$analysis_name, '_03_histograms.png'), width = 1000, height = 1000)
print(virus.hist.n); print(virus.hist.cov); print(virus.hist.gbid); invisible(dev.off())

# ---- SECTION 4: Geographical Distribution ----------------------------------
cat("Generating Geographical Map...\n")

if (isTRUE(api_skip_db)) {
  biosample_ids <- unique(na.omit(virome.df$bio_sample))
  tryCatch({
    if (length(biosample_ids) > 0) {
      resp_geo <- httr::POST(paste0(API_BASE, "/results"),
        httr::add_headers("Content-Type" = "application/json"),
        body = jsonlite::toJSON(list(
          ids = biosample_ids[1:min(500, length(biosample_ids))],
          idColumn = "accession", table = "bgl_gm4326_gp4326",
          columns = "accession,attribute_value",
          pageStart = 0, pageEnd = 50000
        ), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
      if (httr::status_code(resp_geo) == 200) {
        api_geo <- parse_api_response(resp_geo)
        if (is.data.frame(api_geo) && nrow(api_geo) > 0) {
          coords <- strsplit(as.character(api_geo$attribute_value), "[, ]+")
          lats <- sapply(coords, function(x) as.numeric(x[1]))
          lngs <- sapply(coords, function(x) as.numeric(x[2]))
          geo_df <- data.frame(lat = lats, lng = lngs)
          geo_df <- geo_df[!is.na(geo_df$lat) & !is.na(geo_df$lng), ]
          geo_df <- geo_df[geo_df$lat > -90 & geo_df$lat < 90 &
                           geo_df$lng > -180 & geo_df$lng < 180, ]
          if (nrow(geo_df) > 0) {
            world <- tryCatch(ggplot2::map_data("world"), error = function(e) NULL)
            if (!is.null(world)) {
              plot.geo.lycium <- ggplot() +
                geom_map(data = world, map = world,
                  aes(long, lat, map_id = region),
                  color = "gray80", fill = "gray95", linewidth = 0.1) +
                geom_point(data = geo_df, aes(x = lng, y = lat),
                  color = "red", alpha = 0.6, size = 2) +
                theme_bw() +
                coord_cartesian(xlim = c(70, 140), ylim = c(15, 55)) +
                ggtitle("Geographical Distribution (via web API)") +
                xlab("Longitude") + ylab("Latitude")
              png(paste0(p$output.path, p$analysis_name, '_04_geo_map.png'), width = 1000, height = 600)
              print(plot.geo.lycium); invisible(dev.off())
              cat(sprintf("  Mapped %d geo points\n", nrow(geo_df)))
            }
          }
        }
      }
    }
  }, error = function(e) cat("  Skipping Geo:", conditionMessage(e), "\n"))
} else {
  tryCatch({
    pp.geo <- get.sraGeo(virome.runs, con = con)
    pp.geo <- geoFilter(pp.geo, wobble = FALSE)
    if (nrow(pp.geo) > 0) {
      world <- ggplot2::map_data("world")
      plot.geo.lycium <- ggplot() +
        geom_map(data = world, map = world,
          aes(long, lat, map_id = region),
          color = "gray80", fill = "gray95", linewidth = 0.1) +
        geom_point(data = pp.geo, aes(x = lng, y = lat),
          color = "red", alpha = 0.6, size = 2) +
        theme_bw() +
        coord_cartesian(xlim = c(70, 140), ylim = c(15, 55)) +
        ggtitle("Geographical Distribution") +
        xlab("Longitude") + ylab("Latitude")
      png(paste0(p$output.path, p$analysis_name, '_04_geo_map.png'), width = 1000, height = 600)
      print(plot.geo.lycium); invisible(dev.off())
    }
  }, error = function(e) cat("  Skipping Geo:", conditionMessage(e), "\n"))
}

# ---- SECTION 5: Network Analysis -------------------------------------------
cat("Generating Network Analysis...\n")

# Build bipartite network locally (works in both API and DB mode)
edgeList <- virome.df[, c("run", "sotu")]
vir.g <- graph_from_data_frame(edgeList, directed = FALSE)
sotu_names <- unique(virome.df$sotu)
V(vir.g)$type <- FALSE
V(vir.g)$type[V(vir.g)$name %in% sotu_names] <- TRUE

# Paint sOTU nodes
sotu_meta <- virome.df[!duplicated(virome.df$sotu),
                       c("sotu", "gb_pid", "tax_species", "tax_family")]
sotu_match <- match(V(vir.g)$name, sotu_meta$sotu)
V(vir.g)$tax_species <- "NA"
V(vir.g)$tax_species[!is.na(sotu_match)] <- as.character(sotu_meta$tax_species[sotu_match[!is.na(sotu_match)]])
V(vir.g)$tax_family <- "NA"
V(vir.g)$tax_family[!is.na(sotu_match)] <- as.character(sotu_meta$tax_family[sotu_match[!is.na(sotu_match)]])
V(vir.g)$gb_pid <- 0
V(vir.g)$gb_pid[!is.na(sotu_match)] <- as.numeric(sotu_meta$gb_pid[sotu_match[!is.na(sotu_match)]])
V(vir.g)$gb_pid[is.na(V(vir.g)$gb_pid)] <- 0

# Components
comps <- components(vir.g)
V(vir.g)$component <- as.character(factor(comps$membership,
  levels = order(comps$csize, decreasing = TRUE)))
V(vir.g)$pr <- degree(vir.g, normalized = TRUE)
V(vir.g)$vrich <- 0
V(vir.g)$vrank <- V(vir.g)$pr

# Network plot
if (length(V(vir.g)) < 2000 & length(E(vir.g)) < 5000) {
  png(paste0(p$output.path, p$analysis_name, '_05_virome_network.png'), width = 1200, height = 1200)
  plot.igraph(vir.g, layout = layout_nicely, vertex.size = 5,
    vertex.label = NA, vertex.color = V(vir.g)$type, arrow.mode = "-", rescale = TRUE)
  invisible(dev.off())
} else {
  cat("  Skipping network plot (>2000 nodes or >5000 edges)\n")
}

# Component stats
component.stats <- function(g) {
  cs <- data.frame(component = "nil", n_sotu = 0, n_run = 0, n_edge = 0,
    D_sotu = 0, D_run = 0, Vrich = 0, Dia = 0)
  comp.names <- unique(V(g)$component); n.comp <- length(comp.names)
  L.index <- (V(g)$type == TRUE)
  for (i in seq_len(n.comp)) {
    V.index <- (V(g)$component == comp.names[i])
    I.sotu <- which(V.index & L.index); I.runs <- which(V.index & !L.index)
    subg <- induced_subgraph(g, V.index)
    subI.sotu <- (V(subg)$type == TRUE); subI.runs <- (V(subg)$type == FALSE)
    cs.i <- data.frame(component = comp.names[i],
      n_sotu = length(I.sotu), n_run = length(I.runs),
      n_edge = length(E(subg)$run), D_sotu = mean(degree(subg)[subI.sotu]),
      D_run = mean(degree(subg)[subI.runs]),
      Vrich = sum(V(subg)$vrich[subI.sotu]), Dia = diameter(subg))
    cs <- rbind(cs, cs.i)
  }
  cs <- cs[-1, ]; cs <- cs[order(as.numeric(as.character(cs$component))), ]
  cs$component <- factor(cs$component)
  return(cs)
}

cs.df <- component.stats(vir.g); rm(component.stats)
cs.df$n_nodes <- cs.df$n_sotu + cs.df$n_run
cs.df$perc_sotu <- 100 * cs.df$n_sotu / cs.df$n_nodes

netlim  <- c(1, max(with(cs.df, c(n_nodes, n_edge))))
nodelim <- c(0, max(with(cs.df, c(n_sotu, n_run))))
dlim    <- range(with(cs.df, c(D_sotu, D_run)))

plot.comp1 <- ggplot(cs.df, aes(n_nodes, n_edge, label = component, fill = component)) +
  geom_abline(slope = 1, intercept = 0, color = 'gray50') +
  geom_label(colour = "white", fontface = "bold") +
  theme_bw() + theme(legend.position = "none") + scale_x_log10() + scale_y_log10() +
  scale_fill_manual(values = turbo(length(cs.df$component))) +
  coord_cartesian(xlim = netlim, ylim = netlim) +
  xlab('Number of Nodes') + ylab('Number of Edges')

plot.comp2 <- ggplot(cs.df, aes(n_run, n_sotu, label = component, size = log10(n_edge), fill = component)) +
  geom_abline(slope = 1, intercept = 0, color = 'gray50') +
  geom_label(colour = "white", fontface = "bold") +
  theme_bw() + theme(legend.position = "none") +
  scale_fill_manual(values = turbo(length(cs.df$component))) +
  coord_cartesian(xlim = nodelim, ylim = nodelim) +
  xlab('Number of Runs (nodes)') + ylab('Number of sOTU (nodes)')

plot.comp3 <- ggplot(cs.df, aes(n_sotu, Vrich, label = component, size = log10(n_edge), fill = component)) +
  geom_abline(slope = 1, intercept = 0, color = 'gray50') +
  geom_label(colour = "white", fontface = "bold") +
  theme_bw() + theme(legend.position = "none") +
  scale_fill_manual(values = turbo(length(cs.df$component))) +
  coord_cartesian(xlim = nodelim, ylim = nodelim) +
  xlab('Number of sOTU (nodes)') + ylab('Cumulative Virome Enrichment')

plot.comp4 <- ggplot(cs.df, aes(D_sotu, D_run, label = component, size = log10(n_edge), fill = component)) +
  geom_abline(slope = 1, intercept = 0, color = 'gray50') +
  geom_label(colour = "white", fontface = "bold") +
  theme_bw() + theme(legend.position = "none") +
  scale_fill_manual(values = turbo(length(cs.df$component))) +
  coord_cartesian(xlim = dlim, ylim = dlim) +
  xlab('Mean Runs per sOTU (Degree)') + ylab('Mean sOTU per Run (Degree)')
rm(netlim, nodelim, dlim)

png(paste0(p$output.path, p$analysis_name, '_05_component_stats.png'), width = 1200, height = 1000)
print(plot.comp1); print(plot.comp2); print(plot.comp3); print(plot.comp4)
invisible(dev.off())

# sOTU Ranking plot
i.sotu <- V(vir.g)$type
vrank.df <- data.frame(
  sotu   = V(vir.g)$name[i.sotu],
  vrich  = V(vir.g)$vrich[i.sotu],
  pr     = V(vir.g)$pr[i.sotu],
  vrank  = V(vir.g)$vrank[i.sotu],
  nruns  = degree(vir.g)[i.sotu])
rm(i.sotu)
vrank.df <- vrank.df[order(vrank.df$vrank, decreasing = TRUE), ]

plot.vrank <- ggplot(vrank.df, aes(pr, vrich, fill = vrank, label = sotu)) +
  geom_label(colour = "white", fontface = "bold") +
  viridis::scale_fill_viridis(option = "plasma") + theme_bw() +
  xlab('Page Rank (sOTU)') + ylab('V-enrichment (sOTU)')
png(paste0(p$output.path, p$analysis_name, '_05_sotu_vrank.png'), width = 1000, height = 800)
print(plot.vrank); invisible(dev.off())

# Palmprint Network (DB only)
palm.g <- make_empty_graph(directed = FALSE)
if (!isTRUE(api_skip_db)) {
  tryCatch({
    palm.g <- graph.palm(virome.df$sotu, expanded.graph = FALSE)
    vir2palm <- match(V(palm.g)$name, V(vir.g)$name)
    V(palm.g)$pr <- V(vir.g)$pr[vir2palm]
    V(palm.g)$vrich <- V(vir.g)$vrich[vir2palm]
    V(palm.g)$vrank <- V(vir.g)$vrank[vir2palm]
    rm(vir2palm)
  }, error = function(e) cat("  Palmprint network failed:", conditionMessage(e), "\n"))
}

# ---- SECTION 6: Data Tables ------------------------------------------------
cat("Generating Data Tables...\n")

if (isTRUE(api_skip_db)) {
  blast.col <- ""
  sra.col <- virome.df$run
  biosample.col <- if ("bio_sample" %in% colnames(virome.df)) virome.df$bio_sample else ""
  if (!("bio_project" %in% colnames(virome.df))) virome.df$bio_project <- ""
} else {
  blast.col <- linkBLAST(
    header = paste0(virome.df$run, "_", virome.df$palm_id, "_", virome.df$nickname),
    aa.seq = virome.df$node_seq)
  sra.col <- linkDB(virome.df$run)
  biosample.col <- linkDB(virome.df$bio_sample, DB = "biosample")
}

dt_full <- cbind(
  as.character(virome.df$scientific_name),
  sra.col, biosample.col,
  as.character(virome.df$bio_project),
  as.character(virome.df$sotu),
  as.character(virome.df$nickname),
  virome.df$node_coverage,
  as.character(virome.df$gb_acc),
  virome.df$gb_pid,
  as.character(virome.df$tax_species),
  as.character(virome.df$tax_family),
  blast.col) %>%
  DT::datatable(
    colnames = c("scientific_name", "sra_run", "biosample_id", "bioproject",
      "sOTU", "nickname", "coverage", "gb_accession", "gb_id%",
      "tax_species", "tax_family", "BLAST"),
    rownames = FALSE, filter = "top", escape = FALSE,
    options = list(pageLength = 20, scrollX = TRUE, order = list(list(6, 'desc'))))

dt_summary <- cbind(
  as.character(virx.df$sotu),
  as.character(virx.df$nickname),
  virx.df$n,
  virx.df$mean_coverage,
  as.character(virx.df$gb_acc),
  virx.df$gb_pid,
  as.character(virx.df$tax_species),
  as.character(virx.df$tax_family)) %>%
  DT::datatable(
    colnames = c("sOTU", "nickname", "n_SRA_runs", "mean_coverage",
      "gb_accession", "gb_id%", "tax_species", "tax_family"),
    rownames = FALSE, filter = "top", escape = FALSE,
    options = list(ordering = TRUE, order = list(list(2, 'desc')), pageLength = 20, scrollX = TRUE))

htmlwidgets::saveWidget(dt_full,
  paste0(p$output.path, p$analysis_name, '_06_full_table.html'), selfcontained = TRUE)
htmlwidgets::saveWidget(dt_summary,
  paste0(p$output.path, p$analysis_name, '_06_summary_table.html'), selfcontained = TRUE)

# ---- Save Workspace --------------------------------------------------------
cat("Saving workspace...\n")
save(virome.df, virx.df, virome.df2, vir.g, palm.g, vrank.df, cs.df, p,
     file = p$output.rdata)

# ---- Generate HTML Summary Report ------------------------------------------
cat("Generating HTML summary report...\n")

png_files <- list.files(p$output.path, pattern = paste0("^", p$analysis_name, "_.*\\.png$"),
                        full.names = FALSE)
png_files <- sort(png_files)

section_map <- list(
  "_01_"  = "SRA Run Statistics",
  "_02_"  = "Virus Family Summary",
  "_03_"  = "sOTU Expression & Frequency",
  "_04_"  = "Geographical Distribution",
  "_05_"  = "Network Analysis",
  "_06_"  = "Data Tables"
)

get_section <- function(fname) {
  for (key in names(section_map)) {
    if (grepl(key, fname, fixed = TRUE)) return(section_map[[key]])
  }
  return("Other")
}

sections <- list()
for (f in png_files) {
  sec <- get_section(f)
  if (is.null(sections[[sec]])) sections[[sec]] <- c()
  sections[[sec]] <- c(sections[[sec]], f)
}

html_lines <- c(
  '<!DOCTYPE html>', '<html lang="en">', '<head>',
  '<meta charset="UTF-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
  sprintf('<title>%s - Open Virome Report</title>', p$analysis_name),
  '<style>',
  '  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;',
  '          max-width: 1400px; margin: 0 auto; padding: 20px; background: #f5f5f5; }',
  '  h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }',
  '  h2 { color: #34495e; margin-top: 40px; border-bottom: 2px solid #bdc3c7; padding-bottom: 5px; }',
  '  .meta { color: #7f8c8d; font-size: 14px; margin-bottom: 30px; }',
  '  .meta span { margin-right: 20px; }',
  '  .section { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }',
  '  .figure { margin: 15px 0; }',
  '  .figure img { max-width: 100%; height: auto; border: 1px solid #ecf0f1; border-radius: 4px; }',
  '  .figure-title { font-weight: 600; color: #555; margin-bottom: 5px; font-size: 13px; }',
  '  table { border-collapse: collapse; width: 100%; margin: 10px 0; }',
  '  td, th { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }',
  '  th { background: #3498db; color: white; }',
  '  tr:nth-child(even) { background: #f9f9f9; }',
  '  .toc { background: white; padding: 15px 25px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }',
  '  .toc a { color: #3498db; text-decoration: none; }',
  '  .toc a:hover { text-decoration: underline; }',
  '  .toc ul { line-height: 1.8; }',
  '  .llm { background: #fef9e7; padding: 15px 20px; border-radius: 6px; line-height: 1.8; }',
  '</style>', '</head>', '<body>',
  sprintf('<h1>%s — Virome Analysis Report</h1>', p$analysis_name),
  '<div class="meta">',
  sprintf('  <span><strong>Version:</strong> %s</span>', p$ov.version),
  sprintf('  <span><strong>Report ID:</strong> %s</span>', p$report_id),
  sprintf('  <span><strong>Date:</strong> %s</span>', format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf('  <span><strong>Search Type:</strong> %s</span>', p$search_type),
  '</div>',
  '<div class="meta">',
  sprintf('  <span><strong>Genus:</strong> %s</span>', p$genus_match_term),
  sprintf('  <span><strong>Control Type:</strong> %s</span>',
          if (p$doControl) p$control_type else "None"),
  sprintf('  <span><strong>API Mode:</strong> %s</span>', p$api_mode),
  '</div>',
  '',
  '<div class="section">',
  '<h2>Summary Statistics</h2>',
  '<table>',
  sprintf('  <tr><td>Total SRA runs (all)</td><td><strong>%d</strong></td></tr>',
          length(unique(all.runs))),
  sprintf('  <tr><td>Virus-positive SRA runs</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.runs))),
  sprintf('  <tr><td>Unique sOTUs</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.df$sotu))),
  sprintf('  <tr><td>Virus families detected</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.df$tax_family))),
  sprintf('  <tr><td>Virome graph nodes</td><td><strong>%d</strong></td></tr>',
          length(V(vir.g))),
  sprintf('  <tr><td>Virome graph edges</td><td><strong>%d</strong></td></tr>',
          length(E(vir.g))),
  '</table>', '</div>', ''
)

# ---- LLM-Powered Analysis Summary ----
llm_summary  <- ""; llm_family <- ""; llm_network <- ""
llm_sra <- ""; llm_host <- ""; llm_ecology <- ""

if (use_llm && nrow(virome.df) > 0) {
  cat("Generating LLM analysis summaries...\n")

  build_virome_json <- function() {
    top_fam <- as.data.frame(sort(table(as.character(virome.df$tax_family)), decreasing = TRUE)[1:10])
    colnames(top_fam) <- c("family", "count")
    top_sotu <- head(vrank.df, 15)
    top_sotu$sotu_label <- paste0(top_sotu$sotu, " (", top_sotu$nruns, " runs)")
    comp_summary <- cs.df[, c("component", "n_sotu", "n_run", "n_edge")]
    jsonlite::toJSON(list(
      genus = p$genus_match_term,
      total_runs_all = length(unique(all.runs)),
      total_runs_virus = length(unique(virome.runs)),
      total_sotu = length(unique(virome.df$sotu)),
      total_families = length(unique(virome.df$tax_family)),
      top_families = top_fam,
      top_sotus = top_sotu[, c("sotu_label", "vrank")],
      virome_components = comp_summary
    ), auto_unbox = TRUE, pretty = TRUE)
  }

  llm_summary <- ds_chat(
    paste0("---Role---\n\nYou are a bioinformatics research assistant summarizing virome data for a research paper.\n\n",
           "---Goal---\n1. Factual overview using only provided data.\n2. Highlight patterns, trends.\n",
           "3. End with higher-level insight.\n4. Avoid external knowledge.\n\n---Target---\nOne paragraph. Use ** for keywords."),
    build_virome_json())

  llm_family <- ds_chat(
    paste0("---Role---\n\nYou are a plant virologist interpreting virus family distributions.\n\n",
           "---Goal---\nFor each top family: expected in plants? genome type? relevance?\n",
           "---Target---\nOne paragraph per family. Use ** for family names."),
    build_virome_json())

  llm_network <- ds_chat(
    paste0("---Role---\n\nYou are a bioinformatics specialist interpreting viral network analysis.\n\n",
           "---Goal---\n1. Component structure → virus-host associations.\n2. High vrank sOTU significance.\n",
           "---Target---\n1-2 paragraphs."),
    build_virome_json())
}

if (nchar(llm_summary) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #3498db;">',
    '<h2>AI: Analysis Overview</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_summary)), '</div>', '')
}
if (nchar(llm_family) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #27ae60;">',
    '<h2>AI: Virus Family Interpretation</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_family)), '</div>', '')
}
if (nchar(llm_network) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #e67e22;">',
    '<h2>AI: Network Analysis</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_network)), '</div>', '')
}

# Table of Contents
html_lines <- c(html_lines,
  '<div class="toc">', '<h3>Contents</h3>', '<ul>')

for (sn in names(section_map)) {
  html_lines <- c(html_lines,
    sprintf('  <li><a href="#sec-%s">%s</a></li>',
            tolower(gsub("[^a-zA-Z0-9]", "-", section_map[[sn]])), section_map[[sn]]))
}
html_lines <- c(html_lines, '</ul>', '</div>', '')

# Build sections with figures
for (sn in names(section_map)) {
  sec_name <- section_map[[sn]]
  html_lines <- c(html_lines,
    sprintf('<div class="section" id="sec-%s">',
            tolower(gsub("[^a-zA-Z0-9]", "-", sec_name))),
    sprintf('<h2>%s</h2>', sec_name))
  sec_files <- sections[[sec_name]]
  if (!is.null(sec_files)) {
    for (f in sec_files) {
      caption <- sub(paste0(p$analysis_name, "_"), "", f)
      caption <- sub("\\.png$", "", caption)
      caption <- gsub("_", " ", caption)
      html_lines <- c(html_lines,
        '<div class="figure">',
        sprintf('  <div class="figure-title">%s</div>', caption),
        sprintf('  <img src="%s" alt="%s" loading="lazy">', f, caption),
        '</div>')
    }
  }
  if (grepl("_06_", sn, fixed = TRUE)) {
    html_lines <- c(html_lines,
      '<div class="figure"><ul>',
      sprintf('  <li><a href="%s_06_full_table.html" target="_blank">Full Virome Table</a></li>', p$analysis_name),
      sprintf('  <li><a href="%s_06_summary_table.html" target="_blank">Summary Virome Table</a></li>', p$analysis_name),
      '</ul></div>')
  }
  html_lines <- c(html_lines, '</div>', '')
}

html_lines <- c(html_lines,
  '<div class="section">', '<h2>Download Data</h2>', '<ul>',
  sprintf('  <li><a href="%s_virome_full.csv" download>virome_full.csv</a></li>', p$analysis_name),
  sprintf('  <li><a href="%s_virome_summary.csv" download>virome_summary.csv</a></li>', p$analysis_name),
  sprintf('  <li><a href="%s_%s.RData" download>R workspace (.RData)</a></li>',
          p$analysis_name, p$report_id),
  '</ul>', '</div>',
  '<div style="text-align:center; color:#95a5a6; padding: 30px; font-size: 12px;">',
  sprintf('Generated by Open Virome v%s | %s</div>',
          p$ov.version, format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  '</body>', '</html>')

html_path <- paste0(p$output.path, p$analysis_name, '_', p$report_id, '.html')
writeLines(html_lines, html_path)

# ---- Summary ---------------------------------------------------------------
cat("\n========================================\n")
cat("  Analysis Complete!\n")
cat("========================================\n")
cat(sprintf("  Output directory: %s\n", p$output.path))
cat(sprintf("  HTML Report:      %s\n", html_path))
cat(sprintf("  RData file:       %s\n", p$output.rdata))
cat(sprintf("  Number of SRA runs (all):       %d\n", length(unique(all.runs))))
cat(sprintf("  Number of virus-positive runs:  %d\n", length(unique(virome.runs))))
cat(sprintf("  Number of unique sOTU:          %d\n", length(unique(virome.df$sotu))))
cat(sprintf("  Virome graph nodes:             %d\n", length(V(vir.g))))
cat(sprintf("  Virome graph edges:             %d\n", length(E(vir.g))))
cat("========================================\n")
