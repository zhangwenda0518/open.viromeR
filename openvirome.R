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
#   Rscript openvirome_Lycium.R
#
#   # Custom genus, no control set
#   Rscript openvirome_Lycium.R --genus Lycium --control_type NONE
#
#   # SEARCH mode with wildcard
#   Rscript openvirome_Lycium.R --search_type SEARCH --virome_search_term "Lycium%%"
#
#   # Only Lycium barbarum, no control
#   Rscript openvirome_Lycium.R --genus_filter Lycium --species_filter "Lycium barbarum" --control_type NONE
#
#   # LIST mode from file
#   Rscript openvirome_Lycium.R --search_type LIST --input_path my_runs.csv
#
#   # Custom output directory
#   Rscript openvirome_Lycium.R --output ./my_analysis/
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
  Rscript openvirome_Lycium.R [OPTIONS]

  # Simplest: analyze Lycium genus with defaults
  Rscript openvirome_Lycium.R

  # Analyze a different genus
  Rscript openvirome_Lycium.R --genus Solanum --analysis_name Solanum_Virome

  # Only Lycium barbarum, no control set
  Rscript openvirome_Lycium.R --genus_filter Lycium --species_filter \"Lycium barbarum\" --control_type NONE

  # With LLM summaries via DeepSeek
  Rscript openvirome_Lycium.R --deepseek_api_key sk-xxxx

  # Full SEARCH mode
  Rscript openvirome_Lycium.R --search_type SEARCH --virome_search_term \"Lycium%%\"

  # Show this help
  Rscript openvirome_Lycium.R --help

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
  Rscript openvirome_Lycium.R

  # No control, custom genus
  Rscript openvirome_Lycium.R --genus Nicotiana --control_type NONE

  # Genus filter + species filter + LLM summaries
  Rscript openvirome_Lycium.R --genus_filter Lycium \\
    --species_filter \"Lycium barbarum\" --control_type NONE \\
    --deepseek_api_key sk-xxxx

  # Export Cytoscape networks
  Rscript openvirome_Lycium.R --export_cytoscape T

  # All runs (including non-virus)
  Rscript openvirome_Lycium.R --palmprint_only F
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
  "htmlwidgets", "gplots", "reshape2", "jsonlite", "httr"
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

# ---- Initialize Workspace --------------------------------------------------
# Ensure output directory exists
if (!dir.exists(p$output.path)) {
  dir.create(p$output.path, recursive = TRUE)
}

# Establish Serratus server connection (skipped in API mode)
if (!p$api_mode) {
  con <- SerratusConnect()
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
  cat("  Note: API mode active — control sets disabled, palmprint_only forced TRUE\n")
  p$palmprint_only <- TRUE
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
cat(sprintf("  Output Directory:   %s\n", p$output.path))
cat(sprintf("  Output RData:       %s\n", p$output.rdata))
cat("\n")

# ---- Virome Query ----------------------------------------------------------
cat("Querying virome data...\n")

# all.runs = all SRA runs matching the search (GENUS/LIST/SEARCH/STAT)
# virome.runs = subset of all.runs that have palmprint (virus) hits
all.runs <- NULL
api_skip_db <- FALSE

if (p$api_mode && p$search_type == "GENUS") {
  # ---- API MODE: use Open Virome public web API ----
  # Exact match of web frontend API call flow:
  #   /identifiers → get run IDs → /counts with those IDs + groupBy (column name)

  API_BASE <- "https://zrdbegawce.execute-api.us-east-1.amazonaws.com/prod"
  cat("  Using web API (same database as openvirome.com)\n")

  # Step 1: /identifiers (all runs, no palmprint filter)
  resp_ids <- httr::POST(
    paste0(API_BASE, "/identifiers"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(
      filters = list(list(filterType = "label", filterKey = "organism",
        filterValue = p$genus_match_term, groupByKey = "organism")),
      palmprintOnly = FALSE
    ), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
  if (httr::status_code(resp_ids) != 200) stop("API /identifiers failed: ", httr::status_code(resp_ids))
  api_ids <- jsonlite::fromJSON(httr::content(resp_ids, as = "text", encoding = "UTF-8"), simplifyDataFrame = FALSE)
  all_run_ids <- unique(na.omit(unlist(api_ids$run$single)))
  all.runs <- all_run_ids

  # Step 2: /counts (all runs, groupBy="organism", using ids from step 1)
  resp_counts <- httr::POST(paste0(API_BASE, "/counts"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(idColumn = "run", ids = all_run_ids,
      groupBy = "organism", palmprintOnly = FALSE), auto_unbox = TRUE),
    encode = "raw", httr::timeout(30))
  if (httr::status_code(resp_counts) != 200) stop("API /counts (all) failed: ", httr::status_code(resp_counts))
  api_counts <- jsonlite::fromJSON(httr::content(resp_counts, as = "text", encoding = "UTF-8"))

  # Step 3: /identifiers (virus-positive only)
  resp_vir_ids <- httr::POST(paste0(API_BASE, "/identifiers"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(filters = list(list(filterType = "label",
      filterKey = "organism", filterValue = p$genus_match_term, groupByKey = "organism")),
      palmprintOnly = TRUE), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
  if (httr::status_code(resp_vir_ids) != 200) stop("API /identifiers (virus) failed: ", httr::status_code(resp_vir_ids))
  api_vir_ids <- jsonlite::fromJSON(httr::content(resp_vir_ids, as = "text", encoding = "UTF-8"), simplifyDataFrame = FALSE)
  vir_run_ids <- unique(na.omit(unlist(api_vir_ids$run$single)))

  # Step 4: /counts (virus-positive only)
  resp_vir_counts <- httr::POST(paste0(API_BASE, "/counts"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(idColumn = "run", ids = vir_run_ids,
      groupBy = "organism", palmprintOnly = TRUE), auto_unbox = TRUE),
    encode = "raw", httr::timeout(30))
  api_vir_counts <- if (httr::status_code(resp_vir_counts) == 200) {
    jsonlite::fromJSON(httr::content(resp_vir_counts, as = "text", encoding = "UTF-8"))
  } else data.frame(name = character(), count = integer())

  # Step 5: /results (palm_virome data for virus runs)
  resp_results <- httr::POST(paste0(API_BASE, "/results"),
    httr::add_headers("Content-Type" = "application/json"),
    body = jsonlite::toJSON(list(ids = vir_run_ids, idColumn = "run_id",
      table = "palm_virome", columns = "run,bioproject,biosample,organism,sotu,gb_acc,gb_pid,gb_eval,tax_species,tax_family",
      pageStart = 0, pageEnd = 100000), auto_unbox = TRUE), encode = "raw", httr::timeout(30))
  if (httr::status_code(resp_results) != 200) stop("API /results failed: ", httr::status_code(resp_results))
  api_results <- jsonlite::fromJSON(httr::content(resp_results, as = "text", encoding = "UTF-8"))

  # Build virome.df
  virome.df <- api_results
  colnames(virome.df)[colnames(virome.df) == "organism"] <- "scientific_name"
  virome.df$bio_project <- virome.df$bioproject
  virome.df$bio_sample <- virome.df$biosample
  for (col_needed in c("palm_id", "nickname", "node", "node_coverage",
                        "node_pid", "node_eval", "node_qc", "node_seq")) {
    if (!(col_needed %in% colnames(virome.df))) virome.df[[col_needed]] <- NA
  }
  virome.df$node_qc <- as.logical(virome.df$node_qc)
  virome.runs <- vir_run_ids

  # Species breakdown: match all-runs counts with virus counts
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
  # For SEARCH mode, all.runs is not directly available; set to virome.runs
  all.runs <- virome.runs

} else if (p$search_type == "GENUS") {
  api_skip_db <- TRUE   # local-only analysis, fast
  # Fast path: single DB query, all analysis local (same speed as web)
  virome.df    <- get.palmVirome(org.search = paste0(p$genus_match_term, "%"))
  virome.runs  <- unique(virome.df$run)
  all.runs     <- virome.runs  # use virus runs as all-runs (fast, srarun is incomplete anyway)
  # Species breakdown from virome.df directly
  sp_breakdown <- sort(table(as.character(virome.df$scientific_name)), decreasing = TRUE)
  cat("\n  Species breakdown (virus-positive runs):\n")
  for (i in seq_along(sp_breakdown)) {
    cat(sprintf("    %-40s %5d\n", names(sp_breakdown)[i], sp_breakdown[i]))
  }

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
# Fetch scientific_name for all matched runs — prefer in-memory if available
all_orgn <- if (exists("all_runs_sra") && !is.null(all_runs_sra) &&
                ncol(all_runs_sra) >= 2) {
  data.frame(run = all_runs_sra$run, scientific_name = all_runs_sra$scientific_name,
             stringsAsFactors = FALSE)
} else {
  tryCatch({
    orgn_vec <- get.sraOrgn(all.runs, con = con, ordinal = TRUE)
    data.frame(run = all.runs, scientific_name = orgn_vec, stringsAsFactors = FALSE)
  }, error = function(e) NULL)
}
if (!is.null(all_orgn) && nrow(all_orgn) > 0) {
  # Virus-positive runs from virome.df
  virus_df <- unique(virome.df[, c("run", "scientific_name")])
  virus_df$has_virus <- TRUE

  # Merge: all runs vs virus-positive
  sp_summary <- merge(all_orgn, virus_df, by = "run", all.x = TRUE)
  sp_summary$has_virus[is.na(sp_summary$has_virus)] <- FALSE
  sp_summary$species <- ifelse(is.na(sp_summary$scientific_name.y) | sp_summary$scientific_name.y == "",
                               as.character(sp_summary$scientific_name.x),
                               as.character(sp_summary$scientific_name.y))

  sp_counts <- table(sp_summary$species, sp_summary$has_virus)
  sp_df <- data.frame(
    species = rownames(sp_counts),
    total_runs = as.integer(rowSums(sp_counts)),
    virus_positive = as.integer(sp_counts[, "TRUE"]),
    virus_negative = as.integer(sp_counts[, "FALSE"]),
    row.names = NULL
  )
  sp_df <- sp_df[order(sp_df$total_runs, decreasing = TRUE), ]

  cat("\n  Species breakdown:\n")
  cat(sprintf("  %-45s %6s %6s %6s\n", "Species", "Total", "Virus+", "Virus-"))
  cat(sprintf("  %-45s %6s %6s %6s\n", "-------", "-----", "------", "------"))
  for (i in seq_len(nrow(sp_df))) {
    cat(sprintf("  %-45s %6d %6d %6d\n",
                sp_df$species[i], sp_df$total_runs[i],
                sp_df$virus_positive[i], sp_df$virus_negative[i]))
  }
  cat("\n")
}

cat(sprintf("  After filtering: %d rows retained\n", nrow(virome.df)))

# ---- Post-hoc Scientific Name Filtering ----------------------------------
# GENUS mode uses exact tax_genus match — no false positives expected.
# SEARCH mode with SQL LIKE can match genus names appearing in species
# epithets (e.g. "Aethionema lycium"). genus_filter catches these.
# Automatically sets genus_filter = genus_match_term for SEARCH mode.
if (p$search_type == "SEARCH" && p$genus_filter == '') {
  p$genus_filter <- p$genus_match_term
}

n_before <- nrow(virome.df)

# Filter: keep only rows where scientific_name starts with genus_filter
if (p$genus_filter != '' && p$search_type != "GENUS") {
  keep_idx <- grepl(paste0('^', p$genus_filter), as.character(virome.df$scientific_name),
                    ignore.case = TRUE)
  if (sum(!keep_idx) > 0) {
    cat(sprintf("  genus_filter removed %d rows not starting with '%s'\n",
                sum(!keep_idx), p$genus_filter))
    cat("  Removed entries:\n")
    removed <- unique(as.character(virome.df$scientific_name[!keep_idx]))
    for (r in removed) {
      cat(sprintf("    - %s\n", r))
    }
  }
  virome.df  <- virome.df[keep_idx, ]
  virome.runs <- virome.df$run
}

# Filter: further restrict to specific species (regex match on scientific_name)
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

if (nrow(virome.df) == 0) {
  stop("All records removed by genus_filter/species_filter. Relax your filters.")
}

n_after <- nrow(virome.df)
cat(sprintf("  After filtering: %d rows retained (removed %d)\n", n_after, n_before - n_after))

# After filtering virome.df, also narrow all.runs to matching scientific names
# so the "all runs" count reflects the same genus/species filter scope
if ((p$genus_filter != '' || p$species_filter != '') && !is.null(all.runs)) {
  filtered_runs <- unique(virome.df$run)
  all.runs <- intersect(all.runs, filtered_runs)
  # For a true "all runs" count at this filter scope, we should re-query sra_tax
  # but that's expensive. Instead we note the virus runs count and proceed.
}

# Standard cleaning: capitalize taxid -> Taxid for Polars compatibility
if ("taxid" %in% colnames(virome.df)) {
  colnames(virome.df)[colnames(virome.df) == "taxid"] <- "Taxid"
}

# Melt virome data.frame, group by sOTU
virx.df <- melt.virome(virome.df)

cat(sprintf("  Virus-positive runs: %d, unique sOTUs: %d\n",
            length(unique(virome.runs)), nrow(virx.df)))

# ---- Control Virome --------------------------------------------------------
if (!isTRUE(api_skip_db) && p$doControl) {
  if (p$control_type == "LIST") {
    negVirome.df <- get.negativeVirome(run.vec = virome.runs)

  } else if (p$control_type == "SEARCH") {
    negVirome.df <- get.negativeVirome(org.search = p$virome_search_term)

  } else if (p$control_type == "BIOPROJECT") {
    neg.virome.runs <- get.sraProj(run_ids = virome.df$run,
                                   exclude.input.runs = TRUE,
                                   con = con)
    if (length(neg.virome.runs$run_id) == 0) {
      negVirome.df <- NA
      p$doControl <- FALSE
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

# Clean up control intermediates (keep virome.runs for geo-plot)
rm(run_ids)
if (exists("negVirome.df")) rm(negVirome.df)
if (exists("neg.virome.runs")) rm(neg.virome.runs)
if (exists("negv.df")) rm(negv.df)

# ---- Export CSV Data -------------------------------------------------------
cat("Exporting CSV data...\n")
write.csv(virome.df, paste0(p$output.path, p$analysis_name, '_virome_full.csv'), row.names = FALSE)
write.csv(virx.df,   paste0(p$output.path, p$analysis_name, '_virome_summary.csv'), row.names = FALSE)

# ---- SECTION 1: Run Statistics ---------------------------------------------
if (isTRUE(api_skip_db)) {
  cat("Generating Run Statistics (API mode)...\n")

  # ---- Build combined species data: All vs Virus+ in one stacked bar ----
  # api_counts = all runs per species (not only palmprint)
  # api_vir_counts = virus-positive runs per species (only palmprint)
  # Merge into one data.frame with species | all | virus | non_virus
  species_combined <- api_counts
  colnames(species_combined)[colnames(species_combined) == "count"] <- "total"
  species_combined$virus <- 0
  if (nrow(api_vir_counts) > 0) {
    vir_idx <- match(species_combined$name, api_vir_counts$name)
    species_combined$virus[!is.na(vir_idx)] <- api_vir_counts$count[vir_idx[!is.na(vir_idx)]]
  }
  species_combined$non_virus <- species_combined$total - species_combined$virus

  # Sort by total descending
  species_combined <- species_combined[order(species_combined$total, decreasing = TRUE), ]
  species_combined$name <- factor(species_combined$name, levels = rev(species_combined$name))

  # Reshape for stacked bar (ggplot long format)
  sp_long <- data.frame(
    species = rep(species_combined$name, 2),
    count   = c(species_combined$virus, species_combined$non_virus),
    type    = rep(c("Virus+", "Virus-"), each = nrow(species_combined))
  )

  plot.stacked <- ggplot(sp_long, aes(count, species, fill = type)) +
    geom_bar(stat = "identity", position = "stack") +
    theme_bw() +
    scale_fill_manual(values = c("Virus+" = "#CB4154", "Virus-" = "gray85")) +
    xlab("Number of SRA Runs") + ylab("") +
    ggtitle(sprintf("%s: SRA Runs by Species (total=%d, virus+=%d)",
                    p$genus_match_term, sum(species_combined$total),
                    sum(species_combined$virus))) +
    theme(legend.position = "bottom", legend.title = element_blank())

  png(paste0(p$output.path, p$analysis_name, '_01_species_stacked.png'), width = 1000, height = 500)
  print(plot.stacked); invisible(dev.off())

  # Also output the combined species table as CSV
  write.csv(species_combined, paste0(p$output.path, p$analysis_name, '_01_species_combined.csv'), row.names = FALSE)

} else {
  cat("Generating Run Statistics...\n")

# 1a. SRA Run Count Summary — outputs TWO sets:
#     (A) All runs matching query
#     (B) Only runs with palmprint (virus) hits
all_runs_n <- length(unique(all.runs))
virus_runs_n <- length(unique(virome.runs))
cat(sprintf("  All SRA runs: %d  |  Virus-positive: %d (%.1f%%)\n",
            all_runs_n, virus_runs_n,
            if (all_runs_n > 0) 100 * virus_runs_n / all_runs_n else 0))

# Build a summary data.frame for the bar plot
run_summary <- data.frame(
  Category = c("All SRA Runs", "Virus-Positive Runs"),
  Count    = c(all_runs_n, virus_runs_n)
)
run_summary$Category <- factor(run_summary$Category,
                               levels = c("All SRA Runs", "Virus-Positive Runs"))

plot.run.summary <- ggplot(run_summary, aes(Category, Count, fill = Category)) +
  geom_bar(stat = 'identity') +
  theme_bw() + theme(legend.position = "none") +
  scale_fill_manual(values = c('gray60', 'cornflowerblue')) +
  xlab("") + ylab("Number of SRA Runs") +
  ggtitle(sprintf("%s: SRA Run Overview", p$analysis_name))

png(paste0(p$output.path, p$analysis_name, '_01_run_summary.png'), width = 600, height = 500)
print(plot.run.summary)
invisible(dev.off())

# 1b. Scientific Name Bar Plot (virus-positive runs with target/control split)
vorgx.df <- virome.df2 %>%
  dplyr::count(scientific_name, tax_family, node_qc, sort = TRUE)
vorgx.df$node_qc[is.na(vorgx.df$node_qc)] <- FALSE
colnames(vorgx.df) <- c('scientific_name', 'tax_family', 'vRNA', 'n')
vorgx.df$scientific_name <- factor(vorgx.df$scientific_name,
  levels = rev(levels(virome.df2$scientific_name)))
vorgx.df$tax_family <- factor(vorgx.df$tax_family,
  levels = levels(virome.df2$tax_family))

plot.virome.org <- ggplot(vorgx.df, aes(scientific_name, n, fill = vRNA)) +
  geom_bar(stat = 'identity') +
  coord_flip() + theme_bw() +
  xlab("Scientific Name") + ylab("Virus-positive SRA Runs (count)") +
  facet_wrap(~vRNA) +
  scale_fill_manual(values = p$ui.setcol)

png(paste0(p$output.path, p$analysis_name, '_01_run_barplot.png'), width = 1000, height = 450)
print(plotly::hide_legend(plot.virome.org))
invisible(dev.off())

# 1c. SRA Data Type Summary (Polar) — two sets: all runs + virus-only
# Use all.runs for the "All" summary, virome.df2 runs for the target/control split
sra_all.df <- get.sraMeta(all.runs, con = con, ordinal = TRUE)

# All runs summary
sra_all.data <- sra_all.df %>%
  count(library_strategy)
sra_all.nt <- aggregate(bases ~ library_strategy, sra_all.df, sum)
sra_all.data$Gbp <- (sra_all.nt$bases) / 1e9
sra_all.data$set <- "All SRA Runs"

# Virus-positive + control summary
sra.df <- get.sraMeta(virome.df2$run, con = con, ordinal = TRUE)
sra.df$vRNA <- "Control"
sra.df$vRNA[(sra.df$run_id %in% virome.df$run)] <- "Target"

sra.data <- sra.df %>%
  count(vRNA, library_strategy)
sra.data.nt <- aggregate(bases ~ vRNA + library_strategy, sra.df, sum)
sra.data    <- sra.data[order(sra.data$vRNA, sra.data$library_strategy), ]
sra.data.nt <- sra.data.nt[order(sra.data.nt$vRNA, sra.data.nt$library_strategy), ]
sra.data$Gbp <- (sra.data.nt$bases) / 1e9

# Plot A: All runs data types
plot.sra.all.count <- ggplot(sra_all.data, aes(x = library_strategy, n)) +
  geom_bar(stat = 'identity', fill = 'gray60') +
  geom_text(aes(label = paste0(n, " runs")), vjust = 1.5, colour = "black") +
  scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() + ggtitle("All SRA Runs — Count") +
  theme(aspect.ratio = 1)

plot.sra.all.gbp <- ggplot(sra_all.data, aes(x = library_strategy, Gbp)) +
  geom_bar(stat = 'identity', fill = 'gray60') +
  geom_text(aes(label = paste0(round(Gbp, 1), " Gbp")), vjust = 1.5, colour = "black") +
  scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() + ggtitle("All SRA Runs — Gbp") +
  theme(aspect.ratio = 1)

# Plot B: Virus-positive target/control data types
plot.sra.count <- ggplot(sra.data, aes(x = library_strategy, n, fill = vRNA)) +
  geom_bar(stat = 'identity') +
  scale_fill_manual(values = p$ui.setcol) +
  geom_text(aes(label = paste0(n, " runs")), vjust = 1.5, colour = "black") +
  scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() + ggtitle("Virus-Positive Runs — Count") +
  theme(aspect.ratio = 1, legend.position = "none") +
  facet_wrap(~vRNA, ncol = 2)

plot.sra.gbp <- ggplot(sra.data, aes(x = library_strategy, Gbp, fill = vRNA)) +
  geom_bar(stat = 'identity') +
  scale_fill_manual(values = p$ui.setcol) +
  geom_text(aes(label = paste0(round(Gbp, 1), " Gbp")), vjust = 1.5, colour = "black") +
  scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() + ggtitle("Virus-Positive Runs — Gbp") +
  theme(aspect.ratio = 1, legend.position = "none") +
  facet_wrap(~vRNA, ncol = 2)

png(paste0(p$output.path, p$analysis_name, '_01_sra_datatypes.png'), width = 1000, height = 800)
print(plot.sra.all.count)
print(plot.sra.all.gbp)
print(plot.sra.count)
print(plot.sra.gbp)
invisible(dev.off())

rm(sra_all.data, sra_all.nt, sra_all.df, sra.data, sra.data.nt)

# 1d. BioProject Analysis (virus-positive runs)
bp.target.n <- sra.df %>%
  count(vRNA, bioproject, sort = TRUE) %>%
  filter(vRNA == 'Target')
bp.total.n <- sra.df %>%
  count(bioproject, sort = TRUE)
bp.df <- merge(bp.total.n, bp.target.n[, c('bioproject', 'n')], all.x = TRUE, by = 'bioproject')
colnames(bp.df) <- c('bioproject', 'bp_n', 'target_n')
bp.df$target_n[is.na(bp.df$target_n)] <- 0
bp.df$perc_target <- 100 * bp.df$target_n / bp.df$bp_n
rm(bp.target.n, bp.total.n)

bp.size <- ggplot(bp.df, aes(x = bp_n, perc_target, bp = bioproject, color = perc_target)) +
  geom_jitter(width = 0, height = 2, alpha = 0.5) +
  theme_bw() + scale_x_log10() +
  scale_colour_continuous(type = "gradient") +
  ggtitle("Runs (N) per BioProject vs. Virus-positive Runs (%)") +
  xlab('BioProject Size (n runs)') + ylab('BioProject Virus-Positive (%)') +
  theme(legend.position = "none")

bp.hist <- ggplot(bp.df, aes(x = bp_n)) +
  geom_histogram(bins = 60) +
  theme_bw() + scale_x_log10() +
  ggtitle("BioProject Size Distribution") +
  xlab('(n runs)') + ylab('count') +
  theme(aspect.ratio = 0.6, legend.position = "none")

png(paste0(p$output.path, p$analysis_name, '_01_bioproject.png'), width = 1000, height = 800)
print(bp.size)
print(bp.hist)
invisible(dev.off())

} # End of else block for non-API-mode SECTION 1

# ---- SECTION 2: Virus Family Summary ---------------------------------------
cat("Generating Virus Family Summary...\n")

# 2a. Family count bar plot
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
  geom_bar(stat = 'identity') +
  coord_flip() + scale_x_discrete(limits = rev) +
  theme_bw() + theme(legend.position = "none") +
  xlab("Taxonomic Family") + ylab("Count") +
  facet_wrap(~set)

png(paste0(p$output.path, p$analysis_name, '_02_family_counts.png'), width = 800, height = 400)
print(plot.virFam.n)
invisible(dev.off())

# 2b. Family scatter plot (runs vs sOTU)
virFam.nrun2 <- unique(virome.df[, c('tax_family', 'run')]) %>% count(tax_family)
colnames(virFam.nrun2) <- c("tax_family", "n_run")
virFam.sotu2 <- unique(virome.df[, c('tax_family', 'sotu')]) %>% count(tax_family)
colnames(virFam.sotu2) <- c("tax_family", "n_sotu")
virFam.df2 <- merge(virFam.nrun2, virFam.sotu2, by = "tax_family")
rm(virFam.nrun2, virFam.sotu2)

plot.virFam.xy <- ggplot(virFam.df2, aes(n_run, n_sotu, color = tax_family)) +
  geom_point() +
  theme_bw() + theme(legend.position = "none") +
  xlab("Count (Runs)") + ylab("Count (sOTU)")

png(paste0(p$output.path, p$analysis_name, '_02_family_scatter.png'), width = 1000, height = 800)
print(plotly::hide_legend(plot.virFam.xy))
invisible(dev.off())

# 2c. Family vs BioProject Heatmap
bp.total.n2 <- sra.df %>%
  count(bioproject, sort = TRUE)
virFam.bp <- virome.df[, c('tax_family', 'bio_project')]
virFam.bp$tax_family <- makeTop10(virFam.bp$tax_family, top.n = 20)
virFam.bp <- table(virFam.bp)
bpTop   <- colnames(virFam.bp)
bpTop.n <- as.numeric(bp.total.n2$n[match(bpTop, bp.total.n2$bioproject, nomatch = NA)])
bpTop.n <- bpTop.n[!is.na(bpTop.n)]
virFam.bp <- t(t(virFam.bp) / bpTop.n)
virFam.bp <- round(100 * virFam.bp, 2)
virFam.bp <- as.matrix(virFam.bp)
rm(bpTop, bpTop.n, bp.df, bp.total.n2)

if (length(virFam.bp[1, ]) > 1) {
  png(paste0(p$output.path, p$analysis_name, '_02_family_heatmap.png'), width = 1000, height = 600)
  gplots::heatmap.2(virFam.bp, trace = "none",
    breaks = c(0, 1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100),
    density.info = "none",
    col = c("black", viridis::viridis(10, option = "A")),
    key.title = "",
    key.xlab = "Percent BioProject Virus+",
    margins = c(10, 10), sepcolor = NULL)
  invisible(dev.off())
}

# 2d. Per-species tax family polar distribution
vorgx.df2 <- virome.df2[virome.df2$node_qc, ] %>%
  count(scientific_name, tax_family, sort = TRUE)
vorgx.df2$scientific_name <- factor(vorgx.df2$scientific_name,
  levels = rev(levels(virome.df2$scientific_name)))
vorgx.df2$tax_family <- factor(vorgx.df2$tax_family,
  levels = levels(virome.df2$tax_family))
vorgx.df2 <- vorgx.df2[!is.na(vorgx.df2$scientific_name), ]

virome2.org <- ggplot(vorgx.df2, aes(x = tax_family, n, fill = tax_family)) +
  geom_bar(stat = 'identity') +
  scale_y_log10() + coord_polar("x", start = 0) +
  theme_bw() +
  theme(aspect.ratio = 1, legend.position = "none") +
  facet_wrap(~scientific_name, ncol = 4)

png(paste0(p$output.path, p$analysis_name, '_02_label_summary.png'), width = 1000, height = 800)
print(virome2.org)
invisible(dev.off())

# ---- SECTION 3: sOTU Expression & Frequency --------------------------------
cat("Generating sOTU Summary...\n")

ranklvl  <- c("phylum", "family", "genus", "species")
rankcols <- c("phylum" = "#9f62a1", "family" = "#00cc07",
              "genus" = "#ff9607", "species" = "#ff2a24")

virx.df$gb_match <- ranklvl[1]
virx.df$gb_match[which(virx.df$gb_pid >= 45)] <- ranklvl[2]
virx.df$gb_match[which(virx.df$gb_pid >= 70)] <- ranklvl[3]
virx.df$gb_match[which(virx.df$gb_pid >= 90)] <- ranklvl[4]
virx.df$gb_match <- factor(virx.df$gb_match, levels = ranklvl)

virx.df$plot_name <- makeTop10(virx.df$tax_family)

virus.exp2 <- ggplot() +
  geom_point(data = virx.df, aes(x = n, y = gb_pid,
      size = log(mean_coverage + 1),
      color = log(mean_coverage + 1)),
    show.legend = FALSE, alpha = 0.5) +
  geom_hline(yintercept = 90, color = "gray70", linetype = "dashed") +
  theme_bw() +
  scale_color_viridis(option = "plasma") +
  scale_x_log10() + scale_y_log10() + scale_size_identity() +
  xlab("sOTU frequency in SRA Runs") +
  ylab("GenBank Identity (%)") +
  facet_wrap(~plot_name, ncol = 4)

png(paste0(p$output.path, p$analysis_name, '_03_sotu_expression.png'), width = 1200, height = 800)
print(plotly::hide_legend(virus.exp2))
invisible(dev.off())

# Histograms
virx.df$tax_family2 <- makeTop10(virx.df$tax_family)

virus.hist.n <- ggplot(virx.df, aes(n, fill = tax_family2)) +
  geom_histogram() + scale_x_log10() + theme_bw() +
  ggtitle("sOTU Frequency in SRA")

virus.hist.cov <- ggplot(virx.df, aes(mean_coverage, fill = tax_family2)) +
  geom_histogram() + scale_x_log10() + theme_bw() +
  ggtitle("sOTU Mean Coverage")

virus.hist.gbid <- ggplot(virx.df, aes(gb_pid, fill = tax_family2)) +
  geom_histogram() + scale_x_log10() + theme_bw() +
  ggtitle("GenBank Identity Distribution")

png(paste0(p$output.path, p$analysis_name, '_03_histograms.png'), width = 1000, height = 1000)
print(virus.hist.n)
print(virus.hist.cov)
print(virus.hist.gbid)
invisible(dev.off())

# ---- SECTION 4: Geographical Distribution ----------------------------------
cat("Generating Geographical Map...\n")

if (isTRUE(api_skip_db)) {
  # API mode: fetch geo data via /results from bgl_gm4326_gp4326 table
  # using biosample IDs from the virus-positive results
  biosample_ids <- unique(na.omit(virome.df$bio_sample))
  if (length(biosample_ids) > 500) {
    biosample_ids <- biosample_ids[1:500]  # limit to avoid huge request
  }

  tryCatch({
    resp_geo <- httr::POST(
      paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(
        table = "bgl_gm4326_gp4326",
        columns = "accession,attribute_value",
        ids = biosample_ids,
        idColumn = "accession",
        pageStart = 0,
        pageEnd = 50000
      ), auto_unbox = TRUE),
      encode = "raw"
    )
    if (httr::status_code(resp_geo) == 200) {
      api_geo <- jsonlite::fromJSON(httr::content(resp_geo, as = "text", encoding = "UTF-8"))
      if (is.data.frame(api_geo) && nrow(api_geo) > 0) {
        # Extract lat/lon from attribute_value (format: "lat,lon" or PostGIS POINT)
        coords <- strsplit(as.character(api_geo$attribute_value), "[, ]+")
        lats <- sapply(coords, function(x) as.numeric(x[1]))
        lngs <- sapply(coords, function(x) as.numeric(x[2]))
        geo_df <- data.frame(lat = lats, lng = lngs, stringsAsFactors = FALSE)
        geo_df <- geo_df[!is.na(geo_df$lat) & !is.na(geo_df$lng), ]
        geo_df <- geo_df[geo_df$lat > -90 & geo_df$lat < 90 & geo_df$lng > -180 & geo_df$lng < 180, ]

        if (nrow(geo_df) > 0) {
          world <- tryCatch(ggplot2::map_data("world"),
                           error = function(e) NULL)
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
            print(plot.geo.lycium)
            invisible(dev.off())
            cat(sprintf("  Mapped %d geo points\n", nrow(geo_df)))
          }
        }
      }
    }
  }, error = function(e) {
    cat("  Skipping Geo Mapping (API):", conditionMessage(e), "\n")
  })

} else {
  # DB mode: use get.sraGeo
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
        ggtitle("Geographical Distribution of Lycium SRA Runs (East Asia Focus)") +
        xlab("Longitude") + ylab("Latitude")

      png(paste0(p$output.path, p$analysis_name, '_04_geo_map.png'), width = 1000, height = 600)
      print(plot.geo.lycium)
      invisible(dev.off())
    }
  }, error = function(e) {
    cat("  Skipping Geo Mapping:", conditionMessage(e), "\n")
  })
}

# ---- SECTION 5: Network Analysis -------------------------------------------
cat("Generating Network Analysis...\n")

if (!isTRUE(api_skip_db)) {
  # DB mode: full network with statistics from palm_virome_count
  vir.g <- graph.virome2(virome.df)
  palm.g_full <- graph.palm(virome.df$sotu, expanded.graph = FALSE)
  palm_ctrl_ok <- TRUE
} else {
  # API mode: build bipartite network locally from virome.df
  edgeList <- virome.df[, c("run", "sotu")]
  vir.g <- graph_from_data_frame(edgeList, directed = FALSE)

  # Node types: sOTU = TRUE, Run = FALSE
  sotu_names <- unique(virome.df$sotu)
  run_names <- unique(virome.df$run)
  V(vir.g)$type <- FALSE
  V(vir.g)$type[V(vir.g)$name %in% sotu_names] <- TRUE

  # Paint sOTU nodes with metadata
  sotu_meta <- virome.df[!duplicated(virome.df$sotu),
                         c("sotu", "gb_pid", "gb_acc", "tax_species", "tax_family")]
  sotu_match <- match(V(vir.g)$name, sotu_meta$sotu)
  V(vir.g)$nickname <- "NA"
  V(vir.g)$nickname[!is.na(sotu_match)] <- as.character(sotu_meta$sotu[sotu_match[!is.na(sotu_match)]])
  V(vir.g)$tax_species <- "NA"
  V(vir.g)$tax_species[!is.na(sotu_match)] <- as.character(sotu_meta$tax_species[sotu_match[!is.na(sotu_match)]])
  V(vir.g)$tax_family <- "NA"
  V(vir.g)$tax_family[!is.na(sotu_match)] <- as.character(sotu_meta$tax_family[sotu_match[!is.na(sotu_match)]])
  V(vir.g)$gb_pid <- 0
  V(vir.g)$gb_pid[!is.na(sotu_match)] <- as.numeric(sotu_meta$gb_pid[sotu_match[!is.na(sotu_match)]])
  V(vir.g)$gb_pid[is.na(V(vir.g)$gb_pid)] <- 0

  # Simplified stats (no DB-backed vrich calculation)
  comps <- components(vir.g)
  V(vir.g)$component <- as.character(factor(comps$membership,
    levels = order(comps$csize, decreasing = TRUE)))
  V(vir.g)$vrich <- 0
  V(vir.g)$v.exact <- 0
  V(vir.g)$v.or <- 0
  V(vir.g)$pr <- degree(vir.g, normalized = TRUE)
  V(vir.g)$vrank <- V(vir.g)$pr
  V(vir.g)$lpa.label <- V(vir.g)$tax_family

  palm.g_full <- NULL
  palm_ctrl_ok <- FALSE
  cat("  API mode: using simplified network stats (degree as vrank)\n")
}

library(igraph)
vir.g <- graph.virome2(virome.df)

# 5a. Bipartite network plot
if (length(V(vir.g)) < 2000 & length(E(vir.g)) < 5000) {
  png(paste0(p$output.path, p$analysis_name, '_05_virome_network.png'), width = 1200, height = 1200)
  plot.igraph(vir.g,
    layout = layout_nicely,
    vertex.size = 5,
    vertex.label = NA,
    vertex.color = V(vir.g)$type,
    arrow.mode = "-",
    rescale = TRUE)
  invisible(dev.off())

  if (p$export.cytoscape) {
    tryCatch({
      RCy3::createNetworkFromIgraph(vir.g,
        paste0("Virome - ", p$analysis_name, ":", p$report_id))
      RCy3::setVisualStyle("ov001 virome")
      cat("  Exported to Cytoscape.\n")
    }, error = function(e) {
      cat("  Cytoscape export failed:", conditionMessage(e), "\n")
    })
  }
} else {
  cat("  Skipping network plot (>2000 nodes or >5000 edges)\n")
}

# 5b. Component Statistics
component.stats <- function(g) {
  cs <- data.frame(component = "nil",
    n_sotu = 0, n_run = 0, n_edge = 0,
    D_sotu = 0, D_run = 0, Vrich = 0, Dia = 0)

  comp.names <- unique(V(g)$component)
  n.comp <- length(comp.names)
  L.index <- (V(g)$type == TRUE)

  for (i in seq_len(n.comp)) {
    V.index <- (V(g)$component == comp.names[i])
    I.sotu <- which(V.index & L.index)
    I.runs <- which(V.index & !L.index)
    subg <- induced_subgraph(g, V.index)
    subI.sotu <- (V(subg)$type == TRUE)
    subI.runs <- (V(subg)$type == FALSE)

    cs.i <- data.frame(
      component = comp.names[i],
      n_sotu = length(I.sotu),
      n_run  = length(I.runs),
      n_edge = length(E(subg)$run),
      D_sotu = mean(degree(subg)[subI.sotu]),
      D_run  = mean(degree(subg)[subI.runs]),
      Vrich  = sum(V(subg)$vrich[subI.sotu]),
      Dia    = diameter(subg))
    cs <- rbind(cs, cs.i)
  }

  cs <- cs[-1, ]
  cs <- cs[order(as.numeric(as.character(cs$component))), ]
  cs$component <- factor(cs$component)
  return(cs)
}

cs.df <- component.stats(vir.g)
rm(component.stats)

cs.df$n_nodes   <- cs.df$n_sotu + cs.df$n_run
cs.df$perc_sotu <- 100 * cs.df$n_sotu / cs.df$n_nodes

netlim  <- c(1, max(with(cs.df, c(n_nodes, n_edge))))
nodelim <- c(0, max(with(cs.df, c(n_sotu, n_run))))
dlim    <- range(with(cs.df, c(D_sotu, D_run)))

plot.comp1 <- ggplot(cs.df, aes(n_nodes, n_edge, label = component, fill = component)) +
  geom_abline(slope = 1, intercept = 0, color = 'gray50') +
  geom_label(colour = "white", fontface = "bold") +
  theme_bw() + theme(legend.position = "none") +
  scale_x_log10() + scale_y_log10() +
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
print(plot.comp1)
print(plot.comp2)
print(plot.comp3)
print(plot.comp4)
invisible(dev.off())

# 5c. sOTU Ranking plot
i.sotu <- V(vir.g)$type
vrank.df <- data.frame(
  sotu   = V(vir.g)$name[i.sotu],
  vrich  = V(vir.g)$vrich[i.sotu],
  pr     = V(vir.g)$pr[i.sotu],
  vrank  = V(vir.g)$vrank[i.sotu],
  vexact = V(vir.g)$v.exact[i.sotu],
  nruns  = degree(vir.g)[i.sotu])
rm(i.sotu)
vrank.df <- vrank.df[order(vrank.df$vrank, decreasing = TRUE), ]

plot.vrank <- ggplot(vrank.df, aes(pr, vrich, fill = vrank, label = sotu)) +
  geom_label(colour = "white", fontface = "bold") +
  viridis::scale_fill_viridis(option = "plasma") +
  theme_bw() +
  xlab('Page Rank (sOTU)') + ylab('V-enrichment (sOTU)')

png(paste0(p$output.path, p$analysis_name, '_05_sotu_vrank.png'), width = 1000, height = 800)
print(plot.vrank)
invisible(dev.off())

# 5d. Palmprint Network (API mode: skip palm_graph queries)
if (!isTRUE(api_skip_db)) {
  palm.g <- graph.palm(virome.df$sotu, expanded.graph = FALSE)
  vir2palm <- match(V(palm.g)$name, V(vir.g)$name)
  V(palm.g)$pr        <- V(vir.g)$pr[vir2palm]
  V(palm.g)$vrich     <- V(vir.g)$vrich[vir2palm]
  V(palm.g)$vrank     <- V(vir.g)$vrank[vir2palm]
  V(palm.g)$lpa.label <- V(vir.g)$lpa.label[vir2palm]
  rm(vir2palm)

  if (p$export.cytoscape) {
    tryCatch({
      RCy3::createNetworkFromIgraph(palm.g,
        paste0("Palmnet - ", p$analysis_name, ":", p$report_id))
      RCy3::setVisualStyle("ov002 palmnet")
    }, error = function(e) {
      cat("  Palmnet Cytoscape export failed:", conditionMessage(e), "\n")
    })
  }

  # 5e. Palmprint Degree Distribution
  palm.degree.df <- data.frame(
    set = "observed", setn = '0',
    degree = as.numeric(degree(palm.g)))

  n.controlsets <- 1
  for (i in 1:n.controlsets) {
    ctrl.g <- graph.palmControl(virome.df)
    palm.degree <- rbind(palm.degree.df,
      data.frame(set = "expected", setn = as.character(i),
        degree = as.numeric(degree(ctrl.g))))
  }

  palm.degree.max <- aggregate(palm.degree, by = list(palm.degree$setn), max)
  palm.degree.max <- palm.degree.max[, c('setn', 'degree')]
  palm.degree.max <- palm.degree.max[order(palm.degree.max$degree, decreasing = TRUE), ]
  palm.degree.max$rank <- 1:length(palm.degree.max$setn)
  palm.degree$rank <- palm.degree.max$rank[match(palm.degree$setn, palm.degree.max$setn)]
  observed.rank <- palm.degree$rank[palm.degree$set == 'observed'][1]

  cat(sprintf("  Observed Palm Network: Nodes=%d, Edges=%d, Rank=%d/%d\n",
    length(V(palm.g)), length(E(palm.g)), observed.rank, n.controlsets + 1))

  rd.plot <- ggplot(palm.degree, aes(degree, alpha = set, fill = setn)) +
    geom_histogram(binwidth = 1, position = 'identity', colour = NA) +
    theme_bw() + xlab('sOTU node degree') +
    theme(legend.position = "none") +
    scale_alpha_manual(values = c(0.05, 0.5)) +
    scale_fill_manual(values = c('orange2',
      rep("black", length(unique(palm.degree$setn)) - 1))) +
    facet_wrap(~set, ncol = 1)

  png(paste0(p$output.path, p$analysis_name, '_05_palm_degree.png'), width = 800, height = 600)
  print(rd.plot)
  invisible(dev.off())

  rm(ctrl.g, i, n.controlsets, observed.rank, rd.plot)
} else {
  cat("  Skipping Palmprint network (requires palm_graph DB table)\n")
  palm.g <- make_empty_graph(directed = FALSE)
}
} # End of if(!api_skip_db) for SECTION 5

# ---- SECTION 6: Data Tables (HTML widgets saved as standalone) -------------
cat("Generating Data Tables...\n")

if (isTRUE(api_skip_db)) {
  # API mode: simplified tables without BLAST/SRA links
  blast.col <- ""
  sra.col <- virome.df$run
  biosample.col <- ""
  if ("bio_sample" %in% colnames(virome.df)) biosample.col <- virome.df$bio_sample
  if ("bio_project" %in% colnames(virome.df)) colnames(virome.df)[colnames(virome.df) == "bio_project"] <- "bio_project"
  # Ensure bio_project column exists
  if (!("bio_project" %in% colnames(virome.df))) virome.df$bio_project <- ""
} else {
  blast.col <- linkBLAST(
    header = paste0(virome.df$run, "_", virome.df$palm_id, "_", virome.df$nickname),
    aa.seq = virome.df$node_seq)
  sra.col       <- linkDB(virome.df$run)
  biosample.col <- linkDB(virome.df$bio_sample, DB = "biosample")
}

# Full virome table
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
    options = list(pageLength = 20, scrollX = TRUE,
      order = list(list(6, 'desc'))))

# Summary virome table
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
    options = list(ordering = TRUE, order = list(list(2, 'desc')),
      pageLength = 20, scrollX = TRUE))

# Save DT widgets as HTML
htmlwidgets::saveWidget(dt_full,
  paste0(p$output.path, p$analysis_name, '_06_full_table.html'),
  selfcontained = TRUE)
htmlwidgets::saveWidget(dt_summary,
  paste0(p$output.path, p$analysis_name, '_06_summary_table.html'),
  selfcontained = TRUE)

# ---- SECTION 6b: SRA, Host, Ecology Tables (API mode only) -----------------
sra_table_ok <- FALSE; host_table_ok <- FALSE; eco_table_ok <- FALSE

if (isTRUE(api_skip_db)) {
  cat("Fetching SRA metadata table...\n")
  tryCatch({
    resp_sra <- httr::POST(
      paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(
        ids = virus_runs_ids,
        idColumn = "run_id",
        table = "sra",
        columns = "acc,assay_type,center_name,organism,bioproject,mbytes,mbases,librarylayout,instrument",
        pageStart = 0, pageEnd = 100000
      ), auto_unbox = TRUE), encode = "raw")
    if (httr::status_code(resp_sra) == 200) {
      sra_table <- jsonlite::fromJSON(httr::content(resp_sra, as = "text", encoding = "UTF-8"))
      if (is.data.frame(sra_table) && nrow(sra_table) > 0) {
        write.csv(sra_table, paste0(p$output.path, p$analysis_name, '_06_sra_table.csv'), row.names = FALSE)
        cat(sprintf("  SRA table: %d runs\n", nrow(sra_table)))
        sra_table_ok <- TRUE
      }
    }
  }, error = function(e) cat("  SRA table fetch failed:", conditionMessage(e), "\n"))

  cat("Fetching Host/Tissue metadata table...\n")
  biosample_ids_all <- unique(na.omit(virome.df$bio_sample))
  tryCatch({
    resp_host <- httr::POST(
      paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(
        ids = biosample_ids_all,
        idColumn = "biosample_id",
        table = "biosample_tissue",
        columns = "biosample_id,text,tissue,bto_id",
        pageStart = 0, pageEnd = 100000
      ), auto_unbox = TRUE), encode = "raw")
    if (httr::status_code(resp_host) == 200) {
      host_table <- jsonlite::fromJSON(httr::content(resp_host, as = "text", encoding = "UTF-8"))
      if (is.data.frame(host_table) && nrow(host_table) > 0) {
        write.csv(host_table, paste0(p$output.path, p$analysis_name, '_06_host_table.csv'), row.names = FALSE)
        cat(sprintf("  Host table: %d biosamples\n", nrow(host_table)))
        host_table_ok <- TRUE
      }
    }
  }, error = function(e) cat("  Host table fetch failed:", conditionMessage(e), "\n"))

  cat("Fetching Ecology/Geography table...\n")
  tryCatch({
    resp_eco <- httr::POST(
      paste0(API_BASE, "/results"),
      httr::add_headers("Content-Type" = "application/json"),
      body = jsonlite::toJSON(list(
        ids = biosample_ids_all[1:min(500, length(biosample_ids_all))],
        idColumn = "accession",
        table = "bgl_gm4326_gp4326",
        columns = "accession,attribute_name,attribute_value,center_name,country,biome,elevation",
        pageStart = 0, pageEnd = 100000
      ), auto_unbox = TRUE), encode = "raw")
    if (httr::status_code(resp_eco) == 200) {
      eco_table <- jsonlite::fromJSON(httr::content(resp_eco, as = "text", encoding = "UTF-8"))
      if (is.data.frame(eco_table) && nrow(eco_table) > 0) {
        write.csv(eco_table, paste0(p$output.path, p$analysis_name, '_06_ecology_table.csv'), row.names = FALSE)
        cat(sprintf("  Ecology table: %d records\n", nrow(eco_table)))
        eco_table_ok <- TRUE
      }
    }
  }, error = function(e) cat("  Ecology table fetch failed:", conditionMessage(e), "\n"))
}

# ---- Save Workspace --------------------------------------------------------
cat("Saving workspace...\n")
save(virome.df, virx.df, virome.df2, vir.g, palm.g, vrank.df,
     cs.df, p, con,
     file = p$output.rdata)

# ---- Generate HTML Summary Report ------------------------------------------
cat("Generating HTML summary report...\n")

# Collect all PNG files generated in the output directory
png_files <- list.files(p$output.path, pattern = paste0("^", p$analysis_name, "_.*\\.png$"),
                        full.names = FALSE)
png_files <- sort(png_files)

# Build section mapping from filename suffixes
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

# Group PNG files by section
sections <- list()
for (f in png_files) {
  sec <- get_section(f)
  if (is.null(sections[[sec]])) sections[[sec]] <- c()
  sections[[sec]] <- c(sections[[sec]], f)
}

# Build HTML content
html_lines <- c(
  '<!DOCTYPE html>',
  '<html lang="en">',
  '<head>',
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
  '</style>',
  '</head>',
  '<body>',
  sprintf('<h1>%s — Virome Analysis Report</h1>', p$analysis_name),
  '<div class="meta">',
  sprintf('  <span><strong>Version:</strong> %s</span>', p$ov.version),
  sprintf('  <span><strong>Report ID:</strong> %s</span>', p$report_id),
  sprintf('  <span><strong>Date:</strong> %s</span>', format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf('  <span><strong>Search Type:</strong> %s</span>', p$search_type),
  '</div>',
  '',
  '<div class="meta">',
  sprintf('  <span><strong>Genus:</strong> %s</span>', p$genus_match_term),
  sprintf('  <span><strong>Control Type:</strong> %s</span>',
          if (p$doControl) p$control_type else "None"),
  sprintf('  <span><strong>Palmprint Only:</strong> %s</span>', p$palmprint_only),
  '</div>',
  '',
  # Summary statistics
  '<div class="section">',
  '<h2>Summary Statistics</h2>',
  '<table>',
  sprintf('  <tr><td>Total SRA runs (all)</td><td><strong>%d</strong></td></tr>',
          length(unique(all.runs))),
  sprintf('  <tr><td>Virus-positive SRA runs</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.runs))),
  sprintf('  <tr><td>Unique sOTUs (palmprint clusters)</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.df$sotu))),
  sprintf('  <tr><td>Virus families detected</td><td><strong>%d</strong></td></tr>',
          length(unique(virome.df$tax_family))),
  sprintf('  <tr><td>Virome graph nodes</td><td><strong>%d</strong> (Runs + sOTU)</td></tr>',
          length(V(vir.g))),
  sprintf('  <tr><td>Virome graph edges</td><td><strong>%d</strong></td></tr>',
          length(E(vir.g))),
  sprintf('  <tr><td>Palmprint network nodes</td><td><strong>%d</strong></td></tr>',
          length(V(palm.g))),
  sprintf('  <tr><td>Palmprint network edges</td><td><strong>%d</strong></td></tr>',
          length(E(palm.g))),
  '</table>',
  '</div>',
  '')
  # Close html_lines c() vector

  # ---- LLM-Powered Analysis Summary ----
  llm_summary  <- ""
  llm_family   <- ""
  llm_network  <- ""
  llm_sra      <- ""
  llm_host     <- ""
  llm_ecology  <- ""

  if (use_llm) {
    cat("Generating LLM analysis summaries...\n")

    # ---- Helper: build JSON context for each data domain ----

    build_virome_json <- function() {
      top_fam <- as.data.frame(sort(table(as.character(virome.df$tax_family)), decreasing = TRUE)[1:10])
      colnames(top_fam) <- c("family", "count")
      top_sotu <- head(vrank.df, 15)
      top_sotu$sotu_label <- paste0(top_sotu$sotu, " (", top_sotu$nruns, " runs)")
      comp_summary <- cs.df[, c("component", "n_sotu", "n_run", "n_edge", "Vrich")]
      bp_for_llm <- NULL
      if (exists("sra.df") && "bioproject" %in% colnames(sra.df)) {
        bp_counts <- sort(table(as.character(sra.df$bioproject)), decreasing = TRUE)
        bp_top <- head(bp_counts, 20)
        bp_for_llm <- data.frame(bioproject = names(bp_top), n_runs = as.integer(bp_top), row.names = NULL)
      }
      jsonlite::toJSON(list(
        genus = p$genus_match_term,
        total_runs_all = length(unique(all.runs)),
        total_runs_virus = length(unique(virome.runs)),
        total_sotu = length(unique(virome.df$sotu)),
        total_families = length(unique(virome.df$tax_family)),
        top_families = top_fam,
        top_sotus = top_sotu[, c("sotu_label", "vrich", "vrank")],
        virome_components = comp_summary,
        palmprint_network_nodes = length(V(palm.g)),
        palmprint_network_edges = length(E(palm.g)),
        bioprojects = bp_for_llm
      ), auto_unbox = TRUE, pretty = TRUE)
    }

    build_sra_json <- function() {
      if (!exists("sra_table") || !is.data.frame(sra_table)) return("{}")
      sra_json <- list(
        total_runs = nrow(sra_table),
        assay_types = as.list(sort(table(as.character(sra_table$assay_type)), decreasing = TRUE)[1:5]),
        centers = as.list(sort(table(as.character(sra_table$center_name)), decreasing = TRUE)[1:5]),
        total_gbp = round(sum(as.numeric(sra_table$mbases), na.rm = TRUE) / 1e9, 2),
        instruments = as.list(sort(table(as.character(sra_table$instrument)), decreasing = TRUE)[1:5]),
        bioprojects = as.list(sort(table(as.character(sra_table$bioproject)), decreasing = TRUE)[1:10])
      )
      jsonlite::toJSON(sra_json, auto_unbox = TRUE, pretty = TRUE)
    }

    build_host_json <- function() {
      if (!exists("host_table") || !is.data.frame(host_table)) return("{}")
      host_json <- list(
        total_biosamples = nrow(host_table),
        tissues = as.list(sort(table(as.character(host_table$tissue)), decreasing = TRUE)[1:10]),
        bto_ids = as.list(sort(table(as.character(host_table$bto_id)), decreasing = TRUE)[1:5]),
        sample_texts = head(as.character(host_table$text), 20)
      )
      jsonlite::toJSON(host_json, auto_unbox = TRUE, pretty = TRUE)
    }

    build_ecology_json <- function() {
      if (!exists("eco_table") || !is.data.frame(eco_table)) return("{}")
      eco_json <- list(
        total_records = nrow(eco_table),
        countries = as.list(sort(table(as.character(eco_table$country)), decreasing = TRUE)[1:10]),
        biomes = as.list(sort(table(as.character(eco_table$biome)), decreasing = TRUE)[1:8]),
        elevations = summary(as.numeric(eco_table$elevation)),
        locations = head(unique(as.character(eco_table$attribute_value)), 10)
      )
      jsonlite::toJSON(eco_json, auto_unbox = TRUE, pretty = TRUE)
    }

    # ---- 1. Virome summary ----
    cat("  [LLM] 1/5 Virome analysis overview...\n")
    llm_summary <- ds_chat(
      paste0(
        "---Role---\n\nYou are a bioinformatics research assistant summarizing ",
        "virome data for a research paper.\n\n",
        "---Goal---\n",
        "1. Start with a factual overview of the virome data using only the provided data.\n",
        "2. Progressively highlight patterns, trends, implications within the bioproject context.\n",
        "3. Cite relevant BioProject IDs. DO NOT reference bioprojects not in the list.\n",
        "4. Avoid external knowledge.\n\n",
        "---Inference Guidelines---\n",
        "Start with observed data → highlight trends → end with a higher-level insight ",
        "connecting to virology, ecology, or host-pathogen interactions.\n\n",
        "---Target---\nOne paragraph. Use ** for keywords. ",
        "≤5 bioprojects per reference, add \"+more\"."
      ), build_virome_json())
    cat(sprintf("  [LLM] Virome: %d chars\n", nchar(llm_summary)))

    # ---- 2. Virus family interpretation ----
    cat("  [LLM] 2/5 Virus family interpretation...\n")
    llm_family <- ds_chat(
      paste0(
        "---Role---\n\nYou are a plant virologist interpreting virus family ",
        "distributions from a plant virome analysis.\n\n",
        "---Goal---\n",
        "1. For each top family: is it expected in plants? genome type? relevance?\n",
        "2. Cite BioProject IDs supporting the interpretation.\n",
        "3. ONLY use provided data.\n\n",
        "---Target---\nOne paragraph per family. Use ** for family names. ",
        "≤5 bioprojects per reference, add \"+more\"."
      ), build_virome_json())
    cat(sprintf("  [LLM] Family: %d chars\n", nchar(llm_family)))

    # ---- 3. Network interpretation ----
    cat("  [LLM] 3/5 Network analysis interpretation...\n")
    llm_network <- ds_chat(
      paste0(
        "---Role---\n\nYou are a bioinformatics specialist interpreting viral ",
        "network analysis results.\n\n",
        "---Goal---\n",
        "1. Explain what component structure reveals about virus-host associations.\n",
        "2. What high vrank sOTUs mean (high enrichment + significance + centrality).\n",
        "3. Does palmprint network suggest phylogenetic clustering?\n",
        "4. Cite BioProject IDs. ONLY use provided data.\n\n",
        "---Target---\n1-2 paragraphs. Use ** for key metrics. ",
        "≤5 bioprojects per reference, add \"+more\"."
      ), build_virome_json())
    cat(sprintf("  [LLM] Network: %d chars\n", nchar(llm_network)))

    # ---- 4. SRA metadata summary ----
    if (sra_table_ok) {
      cat("  [LLM] 4/5 SRA metadata summary...\n")
      llm_sra <- ds_chat(
        paste0(
          "---Role---\n\nYou are a bioinformatics research assistant summarizing ",
          "SRA (Sequence Read Archive) metadata for a research paper.\n\n",
          "---Goal---\n",
          "1. Describe the sequencing landscape: dominant assay types, instruments, ",
          "centers, and total sequencing depth (Gbp).\n",
          "2. Mention which BioProjects provided the most data.\n",
          "3. Note whether the data is transcriptomic (RNA-Seq) or other types.\n",
          "4. ONLY use provided data. Avoid external knowledge.\n\n",
          "---Target---\nOne paragraph. Use ** for key names. ",
          "≤5 bioprojects per reference, add \"+more\"."
        ), build_sra_json())
      cat(sprintf("  [LLM] SRA: %d chars\n", nchar(llm_sra)))
    }

    # ---- 5. Host/Tissue summary ----
    if (host_table_ok) {
      cat("  [LLM] 5/5 Host/Tissue metadata summary...\n")
      llm_host <- ds_chat(
        paste0(
          "---Role---\n\nYou are a bioinformatics research assistant summarizing ",
          "host/tissue metadata for a plant virome study.\n\n",
          "---Goal---\n",
          "1. Describe the tissue/organ distribution: which tissues were sampled ",
          "most (leaf, fruit, root, flower)?\n",
          "2. Note any developmental stages or stress conditions mentioned.\n",
          "3. Explain what host tissue diversity implies for the virome analysis.\n",
          "4. ONLY use provided data.\n\n",
          "---Target---\nOne paragraph. Use ** for tissue names. ",
          "Do NOT fabricate any sample information not in the data."
        ), build_host_json())
      cat(sprintf("  [LLM] Host: %d chars\n", nchar(llm_host)))
    }

    # ---- 6. Ecology/Geography summary ----
    if (eco_table_ok) {
      cat("  [LLM] 6/5 Ecology/Geography summary...\n")
      llm_ecology <- ds_chat(
        paste0(
          "---Role---\n\nYou are a bioinformatics research assistant summarizing ",
          "ecological and geographical data for a research paper.\n\n",
          "---Goal---\n",
          "1. Describe the geographical distribution: which countries/regions ",
          "dominate the sampling?\n",
          "2. Note the biome types (e.g. desert, temperate forest) and elevation range.\n",
          "3. Discuss any ecological patterns or implications for the virome.\n",
          "4. Avoid mentioning lat/lon coordinates directly; use location names.\n",
          "5. ONLY use provided data.\n\n",
          "---Target---\nOne paragraph. Use ** for locations and biomes. ",
          "≤5 bioprojects per reference, add \"+more\"."
        ), build_ecology_json())
      cat(sprintf("  [LLM] Ecology: %d chars\n", nchar(llm_ecology)))
    }
  }

  if (nchar(llm_summary) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #3498db;">',
      '<h2>AI-Generated Analysis Overview</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_summary)),
      '</div>',
      '')
  },

  if (nchar(llm_family) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #27ae60;">',
      '<h2>Virus Family Interpretation</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_family)),
      '</div>',
      '')
  },

  if (nchar(llm_network) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #e67e22;">',
      '<h2>AI: Network Analysis</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_network)),
      '</div>',
      '')
  }

  if (nchar(llm_sra) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #9b59b6;">',
      '<h2>AI: SRA Metadata Summary</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_sra)),
      '</div>',
      '')
  }

  if (nchar(llm_host) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #e74c3c;">',
      '<h2>AI: Host/Tissue Metadata Summary</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_host)),
      '</div>',
      '')
  }

  if (nchar(llm_ecology) > 0) {
    html_lines <- c(html_lines,
      '<div class="section" style="border-left: 4px solid #1abc9c;">',
      '<h2>AI: Ecology/Geography Summary</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_ecology)),
      '</div>',
      '')
  }

  # Table of Contents
  html_lines <- c(html_lines,
    '<div class="toc">',
    '<h3>Contents</h3>',
    '<ul>'
  )

# Add TOC entries
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
    sprintf('<div class="section" id="sec-%s">', tolower(gsub("[^a-zA-Z0-9]", "-", sec_name))),
    sprintf('<h2>%s</h2>', sec_name))

  sec_files <- sections[[sec_name]]
  if (!is.null(sec_files)) {
    for (f in sec_files) {
      # Derive a readable caption from the filename
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

  # If this is section 6 (Data Tables), add links to DT HTML widgets
  if (grepl("_06_", sn, fixed = TRUE)) {
    html_lines <- c(html_lines,
      '<div class="figure">',
      sprintf('  <div class="figure-title">Interactive Data Tables</div>'),
      sprintf('  <ul>'),
      sprintf('    <li><a href="%s_06_full_table.html" target="_blank">Full Virome Table (interactive)</a></li>',
              p$analysis_name),
      sprintf('    <li><a href="%s_06_summary_table.html" target="_blank">Summary Virome Table (interactive)</a></li>',
              p$analysis_name),
      sprintf('  </ul>'),
      '</div>')
  }

  # Add CSV download links
  html_lines <- c(html_lines, '', '</div>', '')
}

# Add CSV download section
  html_lines <- c(html_lines,
    '<div class="section">',
    '<h2>Download Data</h2>',
    '<ul>',
    sprintf('  <li><a href="%s_virome_full.csv" download>virome_full.csv</a> — Full virome table</li>', p$analysis_name),
    sprintf('  <li><a href="%s_virome_summary.csv" download>virome_summary.csv</a> — sOTU summary table</li>', p$analysis_name))

  if (sra_table_ok) html_lines <- c(html_lines,
    sprintf('  <li><a href="%s_06_sra_table.csv" download>sra_table.csv</a> — SRA metadata (assay, center, Gbp)</li>', p$analysis_name))
  if (host_table_ok) html_lines <- c(html_lines,
    sprintf('  <li><a href="%s_06_host_table.csv" download>host_table.csv</a> — Host tissue metadata</li>', p$analysis_name))
  if (eco_table_ok) html_lines <- c(html_lines,
    sprintf('  <li><a href="%s_06_ecology_table.csv" download>ecology_table.csv</a> — Geography/biome metadata</li>', p$analysis_name))

  html_lines <- c(html_lines,
    sprintf('  <li><a href="%s_%s.RData" download>%s_%s.RData</a> — R workspace (bioconductor)</li>',
            p$analysis_name, p$report_id, p$analysis_name, p$report_id),
    '</ul>',
    '</div>',
  '',
  '<div style="text-align:center; color:#95a5a6; padding: 30px; font-size: 12px;">',
  sprintf('Generated by Open Virome v%s | %s</div>', p$ov.version, format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  '</body>',
  '</html>'
)

# Write the HTML report
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
