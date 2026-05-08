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
#   --palmprint_only {T|F} Only virus-positive runs in downstream analysis [TRUE]
#   --export_cytoscape {T|F} Export networks to Cytoscape [FALSE]
#   --deepseek_api_key {key} DeepSeek API key for LLM-powered summaries ['']
#                            When set, generates natural-language analysis summaries
#                            and embeds them in the HTML report. Uses model
#                            deepseek-v4-pro via HTTPS API. No extra R packages needed.
#                            Set env var DEEPSEEK_API_KEY as alternative.
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
  --palmprint_only {T|F} Only virus-positive runs in downstream analysis [TRUE]
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
    palmprint_only    = TRUE, # only include virus-positive SRA runs in downstream analysis
    deepseek_api_key  = ""    # DeepSeek API key for LLM summaries (or env var DEEPSEEK_API_KEY)
  )

  # Parse --key value pairs
  if (length(args) > 0) {
    i <- 1
    while (i <= length(args)) {
      arg <- args[i]
      if (grepl("^--", arg)) {
        key <- sub("^--", "", arg)
        val <- if (i + 1 <= length(args) && !grepl("^--", args[i + 1])) {
          i <<- i + 1
          args[i]
        } else {
          ""
        }
        # Map CLI flag to list name (handle snake_case and camelCase)
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
      i <- i + 1
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
defaultW <- getOption("warn")
options(warn = -1)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(igraph)
  library(plotly)
  library(viridis)
  library(DT)
})

rm(defaultW)

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

# Establish Serratus server connection
con <- SerratusConnect()

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

# Control set toggle
p$doControl <- (p$control_type != '')

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

if (p$search_type == "SEARCH") {
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
  # Get ALL runs under this genus (may include runs without virus hits)
  # get.taxRunlist returns a character vector, not a data.frame
  all.runs     <- get.taxRunlist(genus = p$genus_match_term)
  # Get only runs with palmprint (virus) hits
  virome.df    <- get.palmVirome(run.vec = all.runs)
  virome.runs  <- virome.df$run

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
cat(sprintf("  Runs with palmprint (virus) hits: %d\n", length(virome.runs)))

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
dev.off()

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
dev.off()

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
dev.off()

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
dev.off()

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
dev.off()

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
dev.off()

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
  dev.off()
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
dev.off()

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
dev.off()

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
dev.off()

# ---- SECTION 4: Geographical Distribution ----------------------------------
cat("Generating Geographical Map...\n")

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
    dev.off()
  }
}, error = function(e) {
  cat("  Skipping Geo Mapping:", conditionMessage(e), "\n")
})

# ---- SECTION 5: Network Analysis -------------------------------------------
cat("Generating Network Analysis...\n")

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
  dev.off()

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
dev.off()

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
dev.off()

# 5d. Palmprint Network
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
dev.off()

rm(ctrl.g, i, n.controlsets, observed.rank, rd.plot)

# ---- SECTION 6: Data Tables (HTML widgets saved as standalone) -------------
cat("Generating Data Tables...\n")

blast.col <- linkBLAST(
  header = paste0(virome.df$run, "_", virome.df$palm_id, "_", virome.df$nickname),
  aa.seq = virome.df$node_seq)
sra.col       <- linkDB(virome.df$run)
biosample.col <- linkDB(virome.df$bio_sample, DB = "biosample")

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
  '',

  # ---- LLM-Powered Analysis Summary ----
  llm_summary <- ""
  llm_family   <- ""
  llm_sotu     <- ""
  llm_network  <- ""

  if (use_llm) {
    cat("Generating LLM analysis summaries...\n")

    # Helper: build prompt for a structured virome overview
    build_data_json <- function() {
      # Top virus families
      top_fam <- as.data.frame(sort(table(as.character(virome.df$tax_family)), decreasing = TRUE)[1:10])
      colnames(top_fam) <- c("family", "count")

      # Top sOTUs by vrank
      top_sotu <- head(vrank.df, 15)
      top_sotu$sotu_label <- paste0(top_sotu$sotu, " (", top_sotu$nruns, " runs)")

      # Component stats summary
      comp_summary <- cs.df[, c("component", "n_sotu", "n_run", "n_edge", "Vrich")]

      # BioProject summary for LLM context (matches web-style bioproject references)
      bp_for_llm <- NULL
      if (exists("sra.df") && "bioproject" %in% colnames(sra.df)) {
        bp_counts <- sort(table(as.character(sra.df$bioproject)), decreasing = TRUE)
        bp_top <- head(bp_counts, 20)
        bp_for_llm <- data.frame(
          bioproject = names(bp_top),
          n_runs = as.integer(bp_top),
          row.names = NULL
        )
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

    # 1. Virome summarization (web-style prompt architecture)
    cat("  [LLM] Generating virome analysis summary...\n")
    llm_summary <- ds_chat(
      paste0(
        "---Role---\n\n",
        "You are a helpful bioinformatics research assistant being used to ",
        "summarize virome data for a research paper.\n\n",
        "---Goal---\n\n",
        "Follow the instructions to summarize virome data:\n",
        "1. Start with a concise, factual overview of the virome data based only ",
        "on the provided bioprojects and dataset.\n",
        "2. Progressively incorporate inferred insights by identifying patterns, ",
        "trends, or broader implications of the virome data while staying within ",
        "the given bioproject context.\n",
        "3. For each overarching topic in the summarization, cite all relevant ",
        "BioProject ID(s).\n",
        "4. DO NOT reference any bioprojects that aren't given in the list.\n",
        "5. ONLY use the information provided in the virome data and bioproject ",
        "data to generate the summary.\n",
        "6. Avoid using any external information or knowledge.\n",
        "7. Focus on virome data and only use the provided bioproject context to ",
        "guide the summarization and insights.\n\n",
        "--- Inference Guidelines ---\n\n",
        "Start by reporting observed data directly.\n",
        "As the summary progresses, highlight trends, correlations, or significant ",
        "findings that emerge.\n",
        "End with a higher-level insight that connects findings to broader ",
        "implications in virology, ecology, or host-pathogen interactions, while ",
        "staying grounded in the provided data.\n\n",
        "---Target response length and format---\n\n",
        "One paragraph.\n",
        "Use standard markdown delimiter ** to surround/highlight important topics ",
        "or keywords in the virome data, DO NOT ADD THEM TO BIOPROJECT IDs.\n",
        "DO NOT use any other delimiter in your summary, unless it is part of ",
        "the virome data.\n",
        "**Do not list more than 5 bioprojects in a single reference**. Instead, ",
        "list the top 5 most relevant bioprojects and add \"+more\" to indicate ",
        "that there are more."
      ),
      build_data_json())
    cat(sprintf("  [LLM] Virome summary: %d chars\n", nchar(llm_summary)))

    # 2. Virus family interpretation (as virome data detail)
    cat("  [LLM] Generating virus family interpretation...\n")
    llm_family <- ds_chat(
      paste0(
        "---Role---\n\n",
        "You are a helpful bioinformatics research assistant being used to ",
        "summarize virome data for a research paper.\n\n",
        "---Goal---\n\n",
        "Given the top virus families detected in a plant virome analysis, ",
        "interpret the distribution and significance of the detected families:\n",
        "1. For each top family, state whether it is expected in plant samples.\n",
        "2. Note the genome type (ssRNA/dsRNA/ssDNA/dsDNA).\n",
        "3. Explain potential relevance to plant health, agriculture, or ecology.\n",
        "4. Cite any relevant BioProject IDs that support the interpretation.\n",
        "5. ONLY use information from the provided data. Avoid external knowledge.\n\n",
        "---Target response length and format---\n\n",
        "One paragraph per virus family.\n",
        "Use ** to highlight virus family names.\n",
        "**Do not list more than 5 bioprojects in a single reference** — list ",
        "the top 5 most relevant and add \"+more\".\n",
        "DO NOT use any other delimiter in your summary."
      ),
      build_data_json())
    cat(sprintf("  [LLM] Family interpretation: %d chars\n", nchar(llm_family)))

    # 3. Network analysis interpretation (as virome data detail)
    cat("  [LLM] Generating network analysis interpretation...\n")
    llm_network <- ds_chat(
      paste0(
        "---Role---\n\n",
        "You are a helpful bioinformatics research assistant being used to ",
        "summarize virome network data for a research paper.\n\n",
        "---Goal---\n\n",
        "Interpret the bipartite Run-sOTU network and palmprint-palmprint network ",
        "from a plant virome analysis:\n",
        "1. Explain what the component structure reveals about virus-host ",
        "associations and community organization.\n",
        "2. Describe what high vrank sOTUs mean biologically — these are sOTUs ",
        "with high virome enrichment, statistical significance, and network centrality.\n",
        "3. Note whether the palmprint network degree distribution suggests ",
        "clustering of phylogenetically related virus sequences.\n",
        "4. Cite any relevant BioProject IDs that support the interpretation.\n",
        "5. ONLY use the information provided. Avoid external knowledge.\n\n",
        "---Target response length and format---\n\n",
        "One to two paragraphs.\n",
        "Use ** to highlight key metrics or sOTU identifiers.\n",
        "**Do not list more than 5 bioprojects in a single reference** — list ",
        "the top 5 most relevant and add \"+more\".\n",
        "DO NOT use any other delimiter in your summary."
      ),
      build_data_json())
    cat(sprintf("  [LLM] Network interpretation: %d chars\n", nchar(llm_network)))
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
      '<h2>Network Analysis Interpretation</h2>',
      sprintf('<div style="line-height: 1.8; color: #2c3e50;">%s</div>',
              gsub("\n", "<br>", llm_network)),
      '</div>',
      '')
  },

  # Table of Contents
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
  sprintf('  <li><a href="%s_virome_summary.csv" download>virome_summary.csv</a> — sOTU summary table</li>', p$analysis_name),
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
