#!/bin/csh -f
# =============================================================================
# parse_fpv_report.csh
# -----------------------------------------------------------------------------
# Parses a raw FPV (Formal Property Verification) report file.
# Extracts per-module, per-customer proven counts and coverage percentages.
#
# Supported modules:
#   - fuse_distr_fsm
#   - fuse_mem_if_arb
#
# Usage:
#   csh parse_fpv_report.csh <report_file>
# =============================================================================

if ( $#argv < 1 ) then
    echo "Usage: csh parse_fpv_report.csh <report_file>"
    exit 1
endif

set REPORT_FILE = $argv[1]

if ( ! -f "$REPORT_FILE" ) then
    echo "ERROR: Report file not found: $REPORT_FILE"
    exit 1
endif

# ---------------------------------------------------------------------------
# Helper: pad/trim string to fixed width (uses awk)
# ---------------------------------------------------------------------------
alias lpad  'printf "%-20s" \!*'
alias rpad  'printf "%8s"  \!*'

# ---------------------------------------------------------------------------
# Parse and print using awk
# ---------------------------------------------------------------------------
echo ""
echo "=============================================================="
echo "  FPV VERIFICATION REPORT"
echo "  Date   : `date '+%Y-%m-%d %H:%M'`"
echo "  Source : $REPORT_FILE"
echo "=============================================================="

awk '
BEGIN {
    module      = ""
    in_data     = 0
    pass_count  = 0
    total_mods  = 0
    SEP         = "+--------------------+----------+----------+------------+"
    HDR         = sprintf("| %-18s | %8s | %8s | %10s |", "Customer", "Proven", "Total", "Covered %")
}

# Detect module header line
/^FPV summary on / {
    # Print previous module footer if any
    if ( module != "" ) {
        print SEP
        print "Status: " status_icon
        print ""
    }
    # Start new module
    module     = $NF
    in_data    = 0
    row_count  = 0
    all_pass   = 1
    any_cover  = 0
    total_mods++
    delete rows
    delete proven_arr
    delete total_arr
    delete cover_arr
    delete cust_arr
    next
}

# Skip separator lines
/^\+[-+]+/ { next }

# Skip header row
/cust/ && /proven/ && /covered/ {
    in_data = 1
    next
}

# Data rows: | cust_A | 12/15 | 80% |
/^\|/ && in_data {
    # Remove leading/trailing pipe and whitespace
    line = $0
    gsub(/^\|/, "", line)
    gsub(/\|$/, "", line)

    # Split on pipe
    n = split(line, cols, "|")
    if ( n < 3 ) next

    cust    = cols[1]; gsub(/^ +| +$/, "", cust)
    proven  = cols[2]; gsub(/^ +| +$/, "", proven)
    covered = cols[3]; gsub(/^ +| +$/, "", covered)

    # Parse proven  e.g. "12/15"
    if ( index(proven, "/") > 0 ) {
        split(proven, pv, "/")
        p_count = pv[1] + 0
        t_count = pv[2] + 0
    } else {
        p_count = proven + 0
        t_count = "?"
    }

    # Parse covered e.g. "80%"
    gsub(/%/, "", covered)
    cov_pct = covered + 0

    if ( cov_pct < 100 ) all_pass = 0
    if ( cov_pct > 0   ) any_cover = 1

    row_count++
    cust_arr[row_count]   = cust
    proven_arr[row_count] = p_count
    total_arr[row_count]  = t_count
    cover_arr[row_count]  = cov_pct
    next
}

# After all lines, flush last module in END
END {
    if ( module != "" ) {
        flush_module()
    }
    print ""
    print "=============================================================="
    print "OVERALL: " pass_count "/" total_mods " modules passing"
    print "=============================================================="
}

function flush_module(    i, t, icon) {
    print "MODULE: " module
    print SEP
    print HDR
    print SEP

    if ( row_count == 0 ) {
        printf "| %-52s |\n", "(no data) -- verify FPV job completed"
        status_icon = "[EMPTY] No results"
    } else {
        for (i = 1; i <= row_count; i++) {
            t = (total_arr[i] == "?") ? "?" : total_arr[i]
            printf "| %-18s | %8d | %8s | %9.1f%% |\n",
                cust_arr[i], proven_arr[i], t, cover_arr[i]
        }
        if ( all_pass ) {
            status_icon = "[PASS]    All properties proven and covered"
            pass_count++
        } else if ( any_cover ) {
            status_icon = "[PARTIAL] Some properties unproven or uncovered"
        } else {
            status_icon = "[FAIL]    No properties proven"
        }
    }
    print SEP
    print "Status: " status_icon
    print ""

    # Reset for next module
    row_count = 0
    all_pass  = 1
    any_cover = 0
    delete cust_arr
    delete proven_arr
    delete total_arr
    delete cover_arr
}

# Flush on each new module header (call before resetting)
/^FPV summary on / && module != "" {
    flush_module()
}
' "$REPORT_FILE"

exit 0
