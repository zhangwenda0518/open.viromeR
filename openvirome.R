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
  "htmlwidgets", "gplots", "reshape2", "jsonlite", "httr", "base64enc", "ggrepel"
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

# ---- Local polyfills for open.viromeR functions (API mode / no package) ----
# Define regardless of package availability to be safe
makeTop10 <- function(invec, top.n = 10, rename = "Other") {
  invec <- as.character(invec)
  t10 <- table(invec)
  t10 <- t10[rev(order(t10))]
  t10_entries <- rownames(t10)[1:min(top.n, nrow(t10))]
  invec2 <- invec
  invec2[!(invec2 %in% t10_entries)] <- rename
  factor(invec2, levels = c(t10_entries, rename))
}

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
  # Auto-set genus_filter to genus_match_term to exclude non-target genera
  if (p$genus_filter == '') p$genus_filter <- p$genus_match_term
  # KEY FINDING: ov_identifiers.organism stores FULL species names (e.g.
  # "Lycium barbarum"), NOT genus-level "Lycium". We must iterate over each
  # species returned by /counts to get identifiers for each one.
  p$api_proxy <- Sys.getenv("OV_API_PROXY")
  API_BASE <- if (p$api_proxy != "") p$api_proxy else
    "https://zrdbegawce.execute-api.us-east-1.amazonaws.com/prod"
  cat("  Using web API (openvirome.com database)\n")

  api_identifiers <- function(species, palmprint) {
    body_json <- sprintf(
      '{"filters":[{"filterType":"label","filterKey":"organism","filterValue":"%s","groupByKey":"organism"}],"palmprintOnly":%s}',
      species, ifelse(palmprint, "true", "false"))
    resp <- httr::POST(paste0(API_BASE, "/identifiers"),
      httr::add_headers("Content-Type" = "application/json"),
      body = body_json, encode = "raw", httr::timeout(30))
    if (httr::status_code(resp) != 200) return(list(run = list(single = list(), totalCount = 0)))
    parse_api_response(resp, simplify = FALSE)
  }

  api_results_call <- function(ids, table, cols) {
    if (length(ids) == 0) return(data.frame())
    # Match exactly the working curl format: omit pageStart/columns, use pageEnd=1000
    body <- list(ids = as.list(ids), idColumn = "run_id",
                 table = table, pageEnd = 1000)
    resp <- httr::POST(paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(body, auto_unbox = TRUE), encode = "raw",
      httr::timeout(60))
    sc <- httr::status_code(resp)
    if (sc != 200) {
      cat(sprintf("  [DEBUG] /results failed: HTTP %d for table=%s with %d ids (size=%d)\n",
                  sc, table, length(ids), nchar(jsonlite::toJSON(body, auto_unbox = TRUE))))
      return(data.frame())
    }
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

    # Genus filter: skip species that don't start with the target genus
    # (e.g. Gymnocalycium, Aethionema — picked up by LIKE search)
    if (p$genus_filter != '') {
      if (!grepl(paste0('^', p$genus_filter), sp, ignore.case = TRUE)) next
    }

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
    # Fallback: build virome-like df from species identifiers alone
    cat("  WARNING: No palm_virome results from /results endpoint.\n")
    cat("  Using /counts data instead for summary-level analysis.\n")
    # Build minimal virome.df: one row per virus run with species name
    sp_names <- names(species_vir)
    sp_counts <- as.integer(species_vir)
    virome.df <- data.frame(
      run = paste0("run_", seq_len(sum(sp_counts))),
      scientific_name = rep(sp_names, sp_counts),
      bio_project = "", bio_sample = "", sotu = "unknown",
      gb_acc = "", gb_pid = 0, tax_species = "", tax_family = "",
      stringsAsFactors = FALSE)
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

  # Species breakdown (API mode — one concise table)
  cat("\n  Species breakdown:\n")
  cat(sprintf("  %-45s %6s %6s %6s\n", "Species", "Total", "Virus+", "Virus-"))
  for (i in seq_len(nrow(api_counts))) {
    sp <- api_counts$name[i]; n_all <- api_counts$count[i]
    virus_idx <- match(sp, api_vir_counts$name)
    n_vir <- if (!is.na(virus_idx)) api_vir_counts$count[virus_idx] else 0
    cat(sprintf("  %-45s %6d %6d %6d\n", sp, n_all, n_vir, n_all - n_vir))
  }
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

cat(sprintf("  Total runs: %d | Virus-positive: %d\n",
            length(unique(all.runs)), length(unique(virome.df$run))))

# ---- Species-Level Summary (non-API mode only) -----------------------------
if (!isTRUE(api_skip_db)) {
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
}

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
cat(sprintf("  Filtered: %d rows (%d removed)\n",
            nrow(virome.df), n_before - nrow(virome.df)))

# Standard cleaning
if ("taxid" %in% colnames(virome.df)) {
  colnames(virome.df)[colnames(virome.df) == "taxid"] <- "Taxid"
}

# Melt virome data.frame, group by sOTU
if (isTRUE(api_skip_db)) {
  # API mode: local melt (no open.viromeR dependency)
  virx.df <- dplyr::count(virome.df, sotu, sort = TRUE)
  meta_keys <- c("sotu", "nickname", "gb_acc", "gb_pid", "gb_eval", "tax_species", "tax_family")
  meta_keys <- intersect(meta_keys, colnames(virome.df))
  meta <- virome.df[!duplicated(virome.df$sotu), meta_keys, drop = FALSE]
  virx.df <- merge(virx.df, meta, by = "sotu", all.x = TRUE)
  # Ensure numeric columns
  if ("gb_pid" %in% colnames(virx.df)) virx.df$gb_pid <- as.numeric(virx.df$gb_pid)
  virx.df$gb_pid[is.na(virx.df$gb_pid)] <- 0
  virx.df$mean_coverage <- 1  # placeholder to avoid log(0)
  virx.df$max_coverage  <- 1
  if (!("tax_species" %in% colnames(virx.df))) virx.df$tax_species <- ""
  if (!("tax_family" %in% colnames(virx.df))) virx.df$tax_family <- ""
} else {
  virx.df <- melt.virome(virome.df)
}

cat(sprintf("  Virus runs: %d | sOTUs: %d\n",
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
  if (!isTRUE(api_skip_db) && p$doControl)
    cat(sprintf("  Control set: active (%s)\n", p$control_type))

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

# ---- Visual Theme (SCI publication style, Nature/Cell journal) -------------
# Nature Communications style: white bg, minimal grid, journal typography
ov_colors <- c(
  "Virus+"    = "#D55E00",   # Nature-style orange-red
  "Virus-"    = "#56B4E9",   # Nature-style sky blue
  "Target"    = "#0072B2",   # deep blue
  "Control"   = "#999999",   # gray
  "All"       = "#000000",   # black
  "Family"    = "#009E73",   # green
  "Tissue"    = "#CC79A7",   # pink
  "Disease"   = "#E69F00",   # gold
  "Organism"  = "#56B4E9",   # sky blue
  "Sex"       = "#F0E442"    # yellow
)
# SCI journal qualitative palette (colorblind-friendly, 10+ categories)
sci_pal <- c("#0072B2","#D55E00","#009E73","#CC79A7","#E69F00","#56B4E9","#F0E442","#000000","#999999","#882255")
theme_ov <- function(base_size = 11) {
  theme_classic(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", size = base_size + 2, color = "#000000"),
      plot.subtitle = element_text(color = "#555555", size = base_size - 1),
      axis.title   = element_text(color = "#000000", size = base_size),
      axis.text    = element_text(color = "#333333", size = base_size - 1),
      axis.line    = element_line(color = "#000000", linewidth = 0.4),
      axis.ticks   = element_line(color = "#000000", linewidth = 0.3),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.text  = element_text(size = base_size - 1, color = "#333333"),
      strip.background = element_rect(fill = "#F2F2F2", color = NA),
      strip.text   = element_text(face = "bold", size = base_size, color = "#000000"),
      plot.margin  = margin(10, 10, 10, 10)
    )
}
# Standard PNG dimensions
OV_W <- 1000; OV_H <- 650; OV_W_SM <- 800; OV_H_SM <- 500

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
    geom_bar(stat = "identity", position = "stack", width = 0.7) +
    geom_text(data = subset(sp_long, count > 0),
              aes(label = count), position = position_stack(vjust = 0.5),
              size = 3, color = "white", fontface = "bold") +
    scale_fill_manual(values = ov_colors) +
    labs(title = sprintf("%s: SRA Runs by Species", p$genus_match_term),
         subtitle = sprintf("Total: %d | Virus+: %d (%.1f%%)",
                            sum(species_combined$total), sum(species_combined$virus),
                            100 * sum(species_combined$virus) / sum(species_combined$total)),
         x = "Number of SRA Runs", y = "") +
    theme_ov()

  png(paste0(p$output.path, p$analysis_name, '_01_species_stacked.png'), width = OV_W, height = OV_H)
  print(plot.stacked); invisible(dev.off())
  write.csv(species_combined, paste0(p$output.path, p$analysis_name, '_01_species_combined.csv'), row.names = FALSE)

  # ---- Run Technology Polar Bar (matching web frontend) ----------------------
  if (exists("sra_table") && is.data.frame(sra_table) && nrow(sra_table) > 0) {
    assay_df <- as.data.frame(table(sra_table$assay_type))
    colnames(assay_df) <- c("Type", "Count")
    assay_df$Pct <- round(100 * assay_df$Count / sum(assay_df$Count), 1)
    p_polar <- ggplot(assay_df, aes(x = Type, y = Count, fill = Type)) +
      geom_bar(stat = "identity", width = 0.8) +
      coord_polar(theta = "x", start = 0) +
      geom_text(aes(label = paste0(Count, "\n(", Pct, "%)")),
                position = position_stack(vjust = 0.5), size = 3, color = "white", fontface = "bold") +
      scale_fill_manual(values = rep(sci_pal, length.out = nrow(assay_df))) +
      labs(title = "Run Technology (Assay Type)", subtitle = "Virus-positive runs", x = "", y = "") +
      theme_ov() + theme(aspect.ratio = 1, axis.text.x = element_text(size = 9))
    png(paste0(p$output.path, p$analysis_name, '_01_run_technology.png'), width = 600, height = 600)
    print(p_polar); invisible(dev.off())
  }

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
    geom_bar(stat = 'identity', width = 0.5) +
    geom_text(aes(label = Count), vjust = -0.5, size = 4.5, fontface = "bold") +
    scale_fill_manual(values = c("All SRA Runs" = "#2c3e50", "Virus-Positive Runs" = "#e74c3c")) +
    labs(title = sprintf("%s: SRA Run Overview", p$analysis_name),
         x = "", y = "Number of Runs") +
    theme_ov() + theme(legend.position = "none")
  png(paste0(p$output.path, p$analysis_name, '_01_run_summary.png'), width = OV_W_SM, height = OV_H_SM)
  print(plot.run.summary); invisible(dev.off())

  vorgx.df <- virome.df2 %>%
    dplyr::count(scientific_name, tax_family, node_qc, sort = TRUE)
  vorgx.df$node_qc[is.na(vorgx.df$node_qc)] <- FALSE
  colnames(vorgx.df) <- c('scientific_name', 'tax_family', 'vRNA', 'n')
  vorgx.df$scientific_name <- factor(vorgx.df$scientific_name,
    levels = rev(levels(virome.df2$scientific_name)))
  vorgx.df$tax_family <- factor(vorgx.df$tax_family, levels = levels(virome.df2$tax_family))
  plot.virome.org <- ggplot(vorgx.df, aes(scientific_name, n, fill = vRNA)) +
    geom_bar(stat = 'identity', width = 0.7) + coord_flip() +
    geom_text(aes(label = n), hjust = -0.2, size = 3) +
    facet_wrap(~vRNA) + scale_fill_manual(values = ov_colors) +
    labs(title = "Virus-Positive Runs by Species", x = "", y = "Runs (count)") +
    theme_ov()
  png(paste0(p$output.path, p$analysis_name, '_01_run_barplot.png'), width = OV_W, height = OV_H)
  print(plotly::hide_legend(plot.virome.org)); invisible(dev.off())
}

# ---- SECTION 2: Virus Family Summary ---------------------------------------
cat("Generating Virus Family Summary...\n")

virFam.nrun <- virome.df[, c('tax_family', 'run')]
virFam.nrun$tax_family <- makeTop10(virFam.nrun$tax_family, top.n = 20)
virFam.nrun <- unique(virFam.nrun[, c('tax_family', 'run')]) %>% count(tax_family)
virFam.nrun$set <- 'Runs'
virFam.sotu <- virome.df[, c('tax_family', 'sotu')]
virFam.sotu$tax_family <- makeTop10(virFam.sotu$tax_family, top.n = 20)
virFam.sotu <- unique(virFam.sotu[, c('tax_family', 'sotu')]) %>% count(tax_family)
virFam.sotu$set <- 'sOTUs'
virFam.df <- rbind(virFam.nrun, virFam.sotu); rm(virFam.nrun, virFam.sotu)

plot.virFam.n <- ggplot(virFam.df, aes(tax_family, n, fill = set)) +
  geom_bar(stat = 'identity', position = "dodge", width = 0.7) +
  geom_text(aes(label = n), position = position_dodge(0.7), hjust = -0.2, size = 3) +
  coord_flip() + scale_x_discrete(limits = rev) +
  scale_fill_manual(values = c("Runs" = "#3498db", "sOTUs" = "#e67e22")) +
  labs(title = "Virus Family Distribution", subtitle = "Top 20 families by SRA runs and unique sOTUs",
       x = "Taxonomic Family", y = "Count") + theme_ov()

png(paste0(p$output.path, p$analysis_name, '_02_family_counts.png'), width = OV_W, height = OV_H)
print(plot.virFam.n); invisible(dev.off())

virFam.nrun2 <- unique(virome.df[, c('tax_family', 'run')]) %>% count(tax_family)
colnames(virFam.nrun2) <- c("tax_family", "n_run")
virFam.sotu2 <- unique(virome.df[, c('tax_family', 'sotu')]) %>% count(tax_family)
colnames(virFam.sotu2) <- c("tax_family", "n_sotu")
virFam.df2 <- merge(virFam.nrun2, virFam.sotu2, by = "tax_family")
rm(virFam.nrun2, virFam.sotu2)

plot.virFam.xy <- ggplot(virFam.df2, aes(n_run, n_sotu)) +
  geom_point(aes(color = n_run), size = 4, alpha = 0.8) +
  scale_color_viridis(option = "D") +
  labs(title = "Runs vs sOTUs per Family", x = "Runs", y = "sOTUs") +
  theme_ov() + theme(legend.position = "none")

png(paste0(p$output.path, p$analysis_name, '_02_family_scatter.png'), width = OV_W_SM, height = OV_H_SM)
print(plotly::hide_legend(plot.virFam.xy)); invisible(dev.off())

# Family vs BioProject Heatmap
if (exists("sra.df") && is.data.frame(sra.df)) {
  bp.total.n2 <- sra.df %>% count(bioproject, sort = TRUE)
  virFam.bp <- virome.df[, c('tax_family', 'bio_project')]
  virFam.bp$tax_family <- makeTop10(virFam.bp$tax_family, top.n = 20)
  virFam.bp <- table(virFam.bp)
  bpTop   <- colnames(virFam.bp)
  bpTop.n <- as.numeric(bp.total.n2$n[match(bpTop, bp.total.n2$bioproject, nomatch = NA)])
  bpTop.n <- bpTop.n[!is.na(bpTop.n)]
  virFam.bp <- t(t(virFam.bp) / bpTop.n); virFam.bp <- round(100 * virFam.bp, 2); virFam.bp <- as.matrix(virFam.bp)
  rm(bpTop, bpTop.n, bp.total.n2)
  if (length(virFam.bp[1, ]) > 1) {
    png(paste0(p$output.path, p$analysis_name, '_02_family_heatmap.png'), width = OV_W, height = 600)
    gplots::heatmap.2(virFam.bp, trace = "none",
      breaks = c(0, 1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100),
      density.info = "none", col = c("black", viridis::viridis(10, option = "A")),
      key.title = "", key.xlab = "% BioProject Virus+", margins = c(10, 10), sepcolor = NULL)
    invisible(dev.off())
  }
}

# Per-species tax family polar distribution
vorgx.df2 <- virome.df2[virome.df2$node_qc, ] %>% count(scientific_name, tax_family, sort = TRUE)
vorgx.df2$scientific_name <- factor(vorgx.df2$scientific_name,
  levels = rev(levels(virome.df2$scientific_name)))
vorgx.df2$tax_family <- factor(vorgx.df2$tax_family, levels = levels(virome.df2$tax_family))
vorgx.df2 <- vorgx.df2[!is.na(vorgx.df2$scientific_name), ]
virome2.org <- ggplot(vorgx.df2, aes(x = tax_family, n, fill = tax_family)) +
  geom_bar(stat = 'identity') + coord_polar("x", start = 0) +
  scale_fill_viridis(discrete = TRUE, option = "D") +
  labs(title = "Taxonomic Distribution per Species") +
  theme_ov() + theme(aspect.ratio = 1, legend.position = "none") +
  facet_wrap(~scientific_name, ncol = 4)

png(paste0(p$output.path, p$analysis_name, '_02_label_summary.png'), width = OV_W, height = OV_H)
print(virome2.org); invisible(dev.off())

# ---- SECTION 3: Virus Family Expression Summary (replaces sOTU) ------------
cat("Generating Virus Family Expression Summary...\n")
# Focus on Virus Family level, not sOTU (matches web frontend approach)
virFam.summary <- virome.df %>%
  dplyr::group_by(tax_family) %>%
  dplyr::summarise(
    n_runs = n_distinct(run),
    n_sotus = n_distinct(sotu),
    mean_gb_pid = mean(gb_pid, na.rm = TRUE),
    .groups = "drop") %>%
  dplyr::arrange(desc(n_runs))
virFam.summary$tax_family <- makeTop10(virFam.summary$tax_family)

# Family prevalence across runs (horizontal bar)
p_fam_expr <- ggplot(head(virFam.summary, 15), aes(n_runs, reorder(tax_family, n_runs), fill = n_runs)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_text(aes(label = n_runs), hjust = -0.2, size = 3.5) +
  scale_fill_gradient(low = "#56B4E9", high = "#D55E00") +
  labs(title = "Virus Family Distribution by Run Count", x = "Number of Runs", y = "") +
  theme_ov() + theme(legend.position = "none")
png(paste0(p$output.path, p$analysis_name, '_03_family_expression.png'), width = OV_W, height = OV_H)
print(p_fam_expr); invisible(dev.off())

# Family: sOTU diversity vs GB identity scatter
p_fam_scatter <- ggplot(virFam.summary, aes(n_sotus, mean_gb_pid, size = n_runs)) +
  geom_point(aes(color = n_runs), alpha = 0.8) +
  geom_hline(yintercept = 90, color = "#D55E00", linetype = "dashed", linewidth = 0.4) +
  scale_color_gradient(low = "#56B4E9", high = "#D55E00") +
  geom_text_repel(aes(label = tax_family), size = 3, max.overlaps = 8) +
  labs(title = "Family sOTU Diversity vs GenBank Identity",
       subtitle = "Dashed line = 90% species threshold. Size = number of runs.",
       x = "sOTU Diversity", y = "Mean GenBank Identity (%)") +
  theme_ov()
png(paste0(p$output.path, p$analysis_name, '_03_family_diversity.png'), width = OV_W, height = OV_H_SM)
print(p_fam_scatter); invisible(dev.off())

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

# Bipartite network plot — colored by Virus Family (like web frontend)
if (length(V(vir.g)) < 2000 & length(E(vir.g)) < 5000) {
  # Assign colors to nodes: Runs = gray, sOTUs = color by family
  fam_levels <- unique(na.omit(virome.df$tax_family))
  fam_colors <- setNames(sci_pal[1:min(length(fam_levels), length(sci_pal))], fam_levels[1:min(length(fam_levels), length(sci_pal))])
  node_cols <- rep("#CCCCCC", vcount(vir.g))
  for (i in seq_len(vcount(vir.g))) {
    if (V(vir.g)$type[i]) {
      fam <- V(vir.g)$tax_family[i]
      if (fam != "NA" && fam %in% names(fam_colors)) {
        node_cols[i] <- fam_colors[fam]
      } else {
        node_cols[i] <- "#333333"
      }
    }
  }
  png(paste0(p$output.path, p$analysis_name, '_05_virome_network.png'), width = OV_W, height = OV_W)
  set.seed(42)
  plot.igraph(vir.g, layout = layout_with_fr(vir.g),
    vertex.size = ifelse(V(vir.g)$type, 7, 3),
    vertex.label = NA,
    vertex.color = node_cols,
    vertex.frame.color = NA,
    edge.color = "#ecf0f1", edge.width = 0.5,
    arrow.mode = "-", main = "Bipartite Run-sOTU Network")
  legend("topright", legend = c("sOTU", "SRA Run"), col = c("#e74c3c", "#3498db"),
         pch = 19, pt.cex = 1.5, bty = "n")
  invisible(dev.off())
}

# Component stats (Bizard-style 2x2 grid with unified theme)
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
  cs$component <- factor(cs$component); return(cs)
}
cs.df <- component.stats(vir.g); rm(component.stats)
cs.df$n_nodes <- cs.df$n_sotu + cs.df$n_run
netlim  <- c(1, max(with(cs.df, c(n_nodes, n_edge))))
nodelim <- c(0, max(with(cs.df, c(n_sotu, n_run))))
dlim    <- range(with(cs.df, c(D_sotu, D_run)))

p1 <- ggplot(cs.df, aes(n_nodes, n_edge, color = n_sotu, size = n_edge)) +
  geom_point(alpha = 0.85) + geom_abline(slope = 1, intercept = 0, color = "gray70", lty = 2) +
  scale_x_log10() + scale_y_log10() + scale_color_viridis(option = "D") +
  coord_cartesian(xlim = netlim, ylim = netlim) +
  labs(title = "Nodes vs Edges", x = "Nodes", y = "Edges") + theme_ov()
p2 <- ggplot(cs.df, aes(n_run, n_sotu, color = n_edge, size = n_edge)) +
  geom_point(alpha = 0.85) + geom_abline(slope = 1, intercept = 0, color = "gray70", lty = 2) +
  scale_color_viridis(option = "B") +
  coord_cartesian(xlim = nodelim, ylim = nodelim) +
  labs(title = "Runs vs sOTUs", x = "Runs", y = "sOTUs") + theme_ov()
p3 <- ggplot(cs.df, aes(n_sotu, Vrich, color = n_edge, size = n_edge)) +
  geom_point(alpha = 0.85) + scale_color_viridis(option = "C") +
  coord_cartesian(xlim = nodelim, ylim = nodelim) +
  labs(title = "sOTUs vs Enrichment", x = "sOTUs", y = "V. Enrichment") + theme_ov()
p4 <- ggplot(cs.df, aes(D_sotu, D_run, color = n_edge, size = n_edge)) +
  geom_point(alpha = 0.85) + geom_abline(slope = 1, intercept = 0, color = "gray70", lty = 2) +
  scale_color_viridis(option = "A") +
  coord_cartesian(xlim = dlim, ylim = dlim) +
  labs(title = "Degree: sOTU vs Run", x = "Mean deg/sOTU", y = "Mean deg/Run") + theme_ov()
rm(netlim, nodelim, dlim)

png(paste0(p$output.path, p$analysis_name, '_05_component_stats.png'), width = OV_W, height = 900)
gridExtra::grid.arrange(p1, p2, p3, p4, ncol = 2)
invisible(dev.off())

# sOTU Ranking — Lollipop chart (Bizard-style, replaces overcrowded scatter)
i.sotu <- V(vir.g)$type
vrank.df <- data.frame(
  sotu   = V(vir.g)$name[i.sotu],
  vrich  = V(vir.g)$vrich[i.sotu],
  pr     = V(vir.g)$pr[i.sotu],
  vrank  = V(vir.g)$vrank[i.sotu],
  nruns  = degree(vir.g)[i.sotu])
rm(i.sotu)
vrank.df <- vrank.df[order(vrank.df$vrank, decreasing = TRUE), ]
top_sotus <- head(vrank.df, 20)
top_sotus$sotu_label <- factor(top_sotus$sotu, levels = rev(top_sotus$sotu))

plot.vrank <- ggplot(top_sotus, aes(vrank, sotu_label)) +
  geom_segment(aes(xend = 0, yend = sotu_label), color = "#bdc3c7", linewidth = 1) +
  geom_point(aes(size = nruns, color = vrank), alpha = 0.9) +
  scale_color_viridis(option = "plasma") +
  scale_size_continuous(range = c(2, 8)) +
  labs(title = "Top 20 sOTUs by Virome Rank",
       subtitle = "vrank = PageRank × V-enrichment. Size = number of runs.",
       x = "Virome Rank", y = "") + theme_ov()

png(paste0(p$output.path, p$analysis_name, '_05_sotu_vrank.png'), width = OV_W_SM, height = OV_H_SM)
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

# ---- SECTION 5b: Ecology / Geography Analysis (Top Biomes & Countries) -----
if (isTRUE(api_skip_db) && exists("eco_table") && is.data.frame(eco_table) && nrow(eco_table) > 0) {
  cat("Generating Ecology/Geography plots...\n")

  # Top Countries horizontal bar
  countries <- sort(table(as.character(eco_table$country)), decreasing = TRUE)
  if (length(countries) > 0) {
    ctry_df <- data.frame(Country = names(head(countries, 12)),
                          Count = as.integer(head(countries, 12)))
    ctry_df$Country <- factor(ctry_df$Country, levels = rev(ctry_df$Country))
    p_ctry <- ggplot(ctry_df, aes(Count, Country)) +
      geom_bar(stat = "identity", fill = "#0072B2", width = 0.7) +
      geom_text(aes(label = Count), hjust = -0.2, size = 3.5) +
      labs(title = "Top Countries", x = "Number of records", y = "") +
      theme_ov() + xlim(0, max(ctry_df$Count) * 1.15)
    png(paste0(p$output.path, p$analysis_name, '_05_top_countries.png'), width = OV_W_SM, height = OV_H_SM)
    print(p_ctry); invisible(dev.off())
  }

  # Top Biomes horizontal bar
  biomes <- sort(table(as.character(eco_table$biome)), decreasing = TRUE)
  if (length(biomes) > 0) {
    bm_df <- data.frame(Biome = names(head(biomes, 10)),
                        Count = as.integer(head(biomes, 10)))
    bm_df$Biome <- factor(bm_df$Biome, levels = rev(bm_df$Biome))
    p_bm <- ggplot(bm_df, aes(Count, Biome)) +
      geom_bar(stat = "identity", fill = "#009E73", width = 0.7) +
      geom_text(aes(label = Count), hjust = -0.2, size = 3.5) +
      labs(title = "Top Biomes", x = "Number of records", y = "") +
      theme_ov() + xlim(0, max(bm_df$Count) * 1.15)
    png(paste0(p$output.path, p$analysis_name, '_05_top_biomes.png'), width = OV_W_SM, height = OV_H_SM)
    print(p_bm); invisible(dev.off())
  }
}

# ---- SECTION 5c: Host / Tissue Analysis ------------------------------------
if (isTRUE(api_skip_db) && exists("host_table") && is.data.frame(host_table) && nrow(host_table) > 0) {
  cat("Generating Host/Tissue plots...\n")

  # Tissue horizontal bar
  tissues <- sort(table(as.character(host_table$tissue)), decreasing = TRUE)
  if (length(tissues) > 0) {
    tis_df <- data.frame(Tissue = names(head(tissues, 12)),
                         Count = as.integer(head(tissues, 12)))
    tis_df$Tissue <- factor(tis_df$Tissue, levels = rev(tis_df$Tissue))
    p_tis <- ggplot(tis_df, aes(Count, Tissue)) +
      geom_bar(stat = "identity", fill = sci_pal[4], width = 0.7) +
      geom_text(aes(label = Count), hjust = -0.2, size = 3.5) +
      labs(title = "Tissue Distribution", x = "Number of records", y = "") +
      theme_ov() + xlim(0, max(tis_df$Count) * 1.15)
    png(paste0(p$output.path, p$analysis_name, '_05_tissue_distribution.png'), width = OV_W_SM, height = OV_H_SM)
    print(p_tis); invisible(dev.off())
  }

  # Source text classification horizontal bar
  texts <- sort(table(as.character(host_table$text)), decreasing = TRUE)
  if (length(texts) > 0) {
    txt_df <- data.frame(Source = names(head(texts, 12)),
                         Count = as.integer(head(texts, 12)))
    txt_df$Source <- factor(txt_df$Source, levels = rev(txt_df$Source))
    p_txt <- ggplot(txt_df, aes(Count, Source)) +
      geom_bar(stat = "identity", fill = sci_pal[5], width = 0.7) +
      geom_text(aes(label = Count), hjust = -0.2, size = 3.5) +
      labs(title = "Sample Source / Description", x = "Count", y = "") +
      theme_ov() + xlim(0, max(txt_df$Count) * 1.15)
    png(paste0(p$output.path, p$analysis_name, '_05_host_source.png'), width = OV_W_SM, height = OV_H_SM)
    print(p_txt); invisible(dev.off())
  }
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

# Embed DT tables directly into the main HTML report (no standalone files)
dt_full_html  <- paste(capture.output(print(dt_full)), collapse = "\n")
dt_summary_html <- paste(capture.output(print(dt_summary)), collapse = "\n")

# ---- Export SRA / Host / Ecology tables (web-style naming) ------------------
if (isTRUE(api_skip_db)) {
  # API mode: fetch these tables from the web API
  biosample_ids_all <- unique(na.omit(virome.df$bio_sample))

  # SRA table
  cat("  Fetching SRA metadata...\n")
  tryCatch({
    sra_resp <- httr::POST(paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(ids = as.list(virome.runs), idColumn = "run_id",
        table = "sra", columns = "acc,assay_type,center_name,organism,bioproject,mbytes,mbases,librarylayout,instrument",
        pageEnd = 1000), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
    if (httr::status_code(sra_resp) == 200) {
      sra_table <- parse_api_response(sra_resp)
      write.csv(sra_table, paste0(p$output.path, "open-virome-Sra.csv"), row.names = FALSE)
    }
  }, error = function(e) NULL)

  # Host table
  if (length(biosample_ids_all) > 0) {
    cat("  Fetching host/tissue metadata...\n")
    tryCatch({
      host_resp <- httr::POST(paste0(API_BASE, "/results"),
        httr::add_headers("Content-Type" = "application/json"),
        body = jsonlite::toJSON(list(ids = as.list(biosample_ids_all), idColumn = "biosample_id",
          table = "biosample_tissue", columns = "biosample_id,text,tissue,bto_id",
          pageEnd = 1000), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
      if (httr::status_code(host_resp) == 200) {
        host_table <- parse_api_response(host_resp)
        write.csv(host_table, paste0(p$output.path, "open-virome-Host.csv"), row.names = FALSE)
      }
    }, error = function(e) NULL)
  }

  # Ecology table
  if (length(biosample_ids_all) > 0) {
    cat("  Fetching ecology/geography metadata...\n")
    tryCatch({
      eco_resp <- httr::POST(paste0(API_BASE, "/results"),
        httr::add_headers("Content-Type" = "application/json"),
        body = jsonlite::toJSON(list(ids = as.list(biosample_ids_all[1:min(500, length(biosample_ids_all))]),
          idColumn = "accession", table = "bgl_gm4326_gp4326",
          columns = "accession,attribute_name,attribute_value,country,biome,elevation",
          pageEnd = 1000), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
      if (httr::status_code(eco_resp) == 200) {
        eco_table <- parse_api_response(eco_resp)
        write.csv(eco_table, paste0(p$output.path, "open-virome-Ecology.csv"), row.names = FALSE)
      }
    }, error = function(e) NULL)
  }
}

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
  "_03_"  = "Virus Family Expression",
  "_04_"  = "Geographical Distribution",
  "_05_network"  = "Virome Network",
  "_05_top"  = "Ecology / Geography",
  "_05_tissue"  = "Host / Tissue",
  "_05_host"  = "Host / Source",
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

# ---- LLM-Powered Analysis Summary (matching web-style prompts) -------------
llm_bioproject <- ""; llm_virome <- ""; llm_ecology <- ""; llm_host <- ""; llm_network <- ""

if (use_llm && nrow(virome.df) > 0) {
  cat("Generating LLM analysis summaries...\n")

  # Helper: extract bioproject IDs from API results
  bp_ids <- character(0)
  if (exists("sra_table") && is.data.frame(sra_table) && "bioproject" %in% colnames(sra_table)) {
    bp_tbl <- sort(table(as.character(sra_table$bioproject)), decreasing = TRUE)
    bp_ids <- unique(names(bp_tbl))
  }
  if (length(bp_ids) == 0 && "bio_project" %in% colnames(virome.df)) {
    bp_tbl <- sort(table(as.character(virome.df$bio_project)), decreasing = TRUE)
    bp_ids <- unique(names(bp_tbl[bp_tbl > 0]))
  }
  bp_context <- if (length(bp_ids) > 0) paste(sprintf("BioProjects: %s", paste(bp_ids, collapse = ", "))) else ""
  bp_limit_note <- "**Do not list more than 5 bioprojects in a single reference**."

  # ---- 1. SRA / BioProject Summary (always runs, even without BioProject IDs) ----
  cat("  [LLM] 1/5 SRA / Data summary...\n")
  sra_desc <- if (exists("sra_table") && is.data.frame(sra_table)) {
    at <- sort(table(sra_table$assay_type), decreasing = TRUE)
    sprintf("Assay types: %s. Total Gbp: %.1f. Instruments: %s.",
            paste(names(at), at, sep = "=", collapse = ", "),
            sum(as.numeric(sra_table$mbases), na.rm = TRUE)/1e9,
            paste(names(sort(table(sra_table$instrument), decreasing = TRUE)[1:3]), collapse = ", "))
  } else ""
  llm_bioproject <- ds_chat(
    "You are a bioinformatics research assistant. Provide a concise one-paragraph summary of the SRA sequencing run metadata for this plant virome study. Cover: total runs, assay types, sequencing centers, total Gbp, and the BioProjects involved. Use ** for key terms. ONLY use provided data.",
    sprintf("Search genus: %s\nTotal runs: %d\nVirus-positive: %d\nVirus families: %d\n%s\n%s",
            p$genus_match_term, length(unique(all.runs)), length(unique(virome.runs)),
            length(unique(virome.df$tax_family)), sra_desc, bp_context))
  if (nchar(llm_bioproject) < 10) {
    llm_bioproject <- sprintf("SRA summary: %d total runs, %d virus-positive, %d virus families detected in genus %s.",
                              length(unique(all.runs)), length(unique(virome.runs)),
                              length(unique(virome.df$tax_family)), p$genus_match_term)
  }
  cat(sprintf("  [LLM] SRA/BioProject: %d chars\n", nchar(llm_bioproject)))

  # ---- 2. Virome Summarization (matching getViromeSummarizationPrompt) ----
  cat("  [LLM] 2/5 Virome summary...\n")
  virome_data <- list(
    genus = p$genus_match_term,
    total_runs_all = length(unique(all.runs)),
    total_runs_virus = length(unique(virome.runs)),
    total_families = length(unique(virome.df$tax_family)),
    top_families = as.data.frame(sort(table(as.character(virome.df$tax_family)), decreasing = TRUE)[1:10]),
    components = as.list(cs.df[1:min(5, nrow(cs.df)), c("component", "n_sotu", "n_run", "n_edge")]),
    bioprojects = bp_ids
  )
  virome_json <- jsonlite::toJSON(virome_data, auto_unbox = TRUE, pretty = TRUE)

  llm_virome <- ds_chat(
    paste0(
      "---Role---\n\n",
      "You are a helpful bioinformatics research assistant being used to ",
      "summarize virome data for a research paper.\n\n",
      "---Goal---\n\n",
      "Follow the instructions to summarize virome data:\n",
      "1. Start with a concise, factual overview of the virome data based only ",
      "on the provided bioprojects.\n",
      "2. Progressively incorporate inferred insights by identifying patterns, ",
      "trends, or broader implications of the virome data while staying within ",
      "the given bioproject context.\n",
      "3. For each overarching topic in the summarization, cite all relevant ",
      "bioproject ID(s).\n",
      "4. DO NOT reference any bioprojects that aren't given in the list.\n",
      "5. ONLY use the information provided in the virome data and bioproject ",
      "data to generate the summary.\n",
      "6. Avoid using any external information or knowledge.\n",
      "7. Focus on virome data and only use the provided bioproject context to ",
      "guide the summarization and insights.\n\n",
      "--- Inference Guidelines ---\n\n",
      "Start by reporting observed data directly.\n\n",
      "As the summary progresses, highlight trends, correlations, or significant ",
      "findings that emerge.\n\n",
      "End with a higher-level insight that connects findings to broader ",
      "implications in virology, ecology, or host-pathogen interactions, while ",
      "staying grounded in the provided data.\n\n",
      "---Target response length and format---\n\n",
      "One paragraph\n\n",
      "Use standard markdown delimiter ** to surround/highlight important topics ",
      "or keywords in the virome data, DO NOT ADD THEM TO BIOPROJECT IDs.\n\n",
      "DO NOT use any other delimiter in your summary, unless it is part of ",
      "the virome data.\n",
      bp_limit_note, "\n\n---\n"
    ), virome_json)
  cat(sprintf("  [LLM] Virome: %d chars\n", nchar(llm_virome)))

  # ---- 3. Ecology / Geography Summarization (matching getEcologySummarizationPrompt) ----
  if (exists("eco_table") && is.data.frame(eco_table) && nrow(eco_table) > 0) {
    cat("  [LLM] 3/5 Ecology summary...\n")
    eco_data <- list(
      total_records = nrow(eco_table),
      countries = as.list(sort(table(as.character(eco_table$country)), decreasing = TRUE)[1:10]),
      biomes = as.list(sort(table(as.character(eco_table$biome)), decreasing = TRUE)[1:8]),
      bioprojects = bp_ids
    )
    eco_json <- jsonlite::toJSON(eco_data, auto_unbox = TRUE, pretty = TRUE)
    llm_ecology <- ds_chat(
      paste0(
        "---Role---\n\n",
        "You are a helpful bioinformatics research assistant being used to ",
        "summarize geographical data for a research paper.\n\n",
        "---Goal---\n\n",
        "Follow the instructions to summarize ecological data:\n",
        "1. Start with a concise, factual overview of the geographical data ",
        "based only on the provided bioprojects.\n",
        "2. Progressively incorporate inferred insights by identifying patterns, ",
        "trends, or broader implications of the geography data while staying ",
        "within the given bioproject context.\n",
        "3. For each overarching topic in the summarization, cite all relevant ",
        "bioproject ID(s).\n",
        "4. DO NOT reference any bioprojects that aren't given in the list.\n",
        "5. DO NOT reference biosamples (items start with 'SAMN'), only reference ",
        "bioprojects (items start with 'PRJNA').\n",
        "6. ONLY use the information provided in the geography data and bioproject ",
        "data to generate the summary.\n",
        "7. Avoid using any external information or knowledge.\n",
        "8. Focus on geographical data and making connections based on the ",
        "geographical data to the provided bioproject context to guide the ",
        "summarization and insights.\n",
        "9. Try to discuss any geological patterns or trends among the provided data.\n",
        "10. Avoid mentioning summarizations of bioprojects or virome data.\n",
        "11. When naming locations, avoid using latitude, longitude and elevation, ",
        "instead use the location name.\n\n",
        "--- Inference Guidelines ---\n\n",
        "Start by reporting observed data directly.\n\n",
        "As the summary progresses, highlight trends, correlations, or significant ",
        "findings that emerge.\n\n",
        "End with a higher-level insight that connects findings to broader ",
        "implications in virology, geological, or host-pathogen interactions, ",
        "while staying grounded in the provided data.\n\n",
        "---Target response length and format---\n\n",
        "One paragraph\n\n",
        bp_limit_note, "\n\n---\n"
      ), eco_json)
    cat(sprintf("  [LLM] Ecology: %d chars\n", nchar(llm_ecology)))
  }

  # ---- 4. Host / Tissue Summarization (matching getHostSummarizationPrompt) ----
  if (exists("host_table") && is.data.frame(host_table) && nrow(host_table) > 0) {
    cat("  [LLM] 4/5 Host summary...\n")
    host_data <- list(
      total_biosamples = nrow(host_table),
      tissues = as.list(sort(table(as.character(host_table$tissue)), decreasing = TRUE)[1:10]),
      bioprojects = bp_ids
    )
    host_json <- jsonlite::toJSON(host_data, auto_unbox = TRUE, pretty = TRUE)
    llm_host <- ds_chat(
      paste0(
        "---Role---\n\n",
        "You are a helpful bioinformatics research assistant being used to ",
        "summarize host data for a research paper.\n\n",
        "---Goal---\n\n",
        "Follow the instructions to summarize host data:\n",
        "1. Start with a concise, factual overview of the host/tissue data based ",
        "only on the provided bioprojects.\n",
        "2. Progressively incorporate inferred insights by identifying patterns, ",
        "trends, or broader implications of the host/tissue data while staying ",
        "within the given bioproject context.\n",
        "3. For each overarching topic in the summarization, cite all relevant ",
        "bioproject ID(s).\n",
        "4. DO NOT reference any bioprojects that aren't given in the list.\n",
        "5. ONLY use the information provided in the host/tissue data and bioproject ",
        "data to generate the summary.\n",
        "6. Avoid using any external information or knowledge.\n",
        "7. Focus on host/tissue and only use the provided bioproject context to ",
        "guide the summarization and insights.\n\n",
        "--- Inference Guidelines ---\n\n",
        "Start by reporting observed data directly.\n\n",
        "As the summary progresses, highlight trends, correlations, or significant ",
        "findings that emerge.\n\n",
        "End with a higher-level insight that connects findings to broader ",
        "implications in virology, ecology, or host-pathogen interactions, while ",
        "staying grounded in the provided data.\n\n",
        "---Target response length and format---\n\n",
        "One paragraph\n\n",
        "Use standard markdown delimiter ** to surround/highlight important topics ",
        "or keywords in the host data, DO NOT ADD THEM TO BIOPROJECT IDs.\n\n",
        "DO NOT use any other delimiter in your summary, unless it is part of ",
        "the host data.\n",
        bp_limit_note, "\n\n---\n"
      ), host_json)
    cat(sprintf("  [LLM] Host: %d chars\n", nchar(llm_host)))
  }

  # ---- 5. Network Analysis Interpretation ----
  cat("  [LLM] 5/5 Network summary...\n")
  net_data <- list(
    total_nodes = length(V(vir.g)),
    total_edges = length(E(vir.g)),
    n_components = nrow(cs.df),
    largest_component = if (nrow(cs.df) > 0) as.list(cs.df[1, c("n_sotu", "n_run", "n_edge")]) else NULL,
    top_sotus = head(vrank.df[, c("sotu", "nruns", "vrank")], 10)
  )
  net_json <- jsonlite::toJSON(net_data, auto_unbox = TRUE, pretty = TRUE)
  llm_network <- ds_chat(
    paste0(
      "---Role---\n\n",
      "You are a bioinformatics specialist interpreting viral network analysis ",
      "results from a plant virome study.\n\n",
      "---Goal---\n\n",
      "Interpret the bipartite Run-sOTU network:\n",
      "1. Explain what the component structure reveals about virus-host ",
      "associations and community organization.\n",
      "2. Describe what high vrank sOTUs mean biologically — these are sOTUs ",
      "with high network centrality (PageRank) weighted by virus enrichment.\n",
      "3. Connect findings to the bioproject context where possible.\n",
      "4. Cite relevant BioProject IDs.\n",
      "5. ONLY use the information provided. Avoid external knowledge.\n\n",
      "---Target response length and format---\n\n",
      "One to two paragraphs.\n",
      bp_limit_note, "\n\n---\n"
    ), net_json)
  cat(sprintf("  [LLM] Network: %d chars\n", nchar(llm_network)))
}

# ---- Insert LLM summaries into HTML ----
if (nchar(llm_bioproject) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #9b59b6;">',
    '<h2>AI: BioProject / SRA Overview</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_bioproject)), '</div>', '')
}
if (nchar(llm_virome) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #3498db;">',
    '<h2>AI: Virome Analysis</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_virome)), '</div>', '')
}
if (nchar(llm_ecology) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #1abc9c;">',
    '<h2>AI: Ecology / Geography</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_ecology)), '</div>', '')
}
if (nchar(llm_host) > 0) {
  html_lines <- c(html_lines,
    '<div class="section" style="border-left: 4px solid #e74c3c;">',
    '<h2>AI: Host / Tissue</h2>',
    sprintf('<div class="llm">%s</div>', gsub("\n", "<br>", llm_host)), '</div>', '')
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
      '<div class="figure">',
      '<div class="figure-title">Full Virome Table</div>',
      if (exists("dt_full_html")) dt_full_html else "",
      '</div>',
      '<div class="figure">',
      '<div class="figure-title">Summary Virome Table</div>',
      if (exists("dt_summary_html")) dt_summary_html else "",
      '</div>')
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
