#!/bin/csh -f
# =============================================================================
# extract_fpv_rpt.csh
# -----------------------------------------------------------------------------
# Reads Jasper FPV log files, extracts the SUMMARY block, and writes one
# structured .rpt file per FPV module per customer.
#
# Log path convention expected:
#   output/<customer>/jasper/fuse_fpv_<module>_out/jg_fpv/log/<logfile>
#
# Examples:
#   output/fuse_DMRDARW/jasper/fuse_fpv_fuse_distr_fsm_out/jg_fpv/log/fuse.jg_fpv.rpt
#   output/fuse_DMRDARW/jasper/fuse_fpv_fuse_mem_if_arb_out/jg_fpv/log/fuse.fpv.log
#
# Output .rpt files are written to:
#   <RPT_OUTDIR>/<module>/<customer>.rpt
#
# Usage:
#   csh extract_fpv_rpt.csh [base_output_dir] [rpt_out_dir]
#
# Arguments:
#   base_output_dir   Root directory containing output/<customer>/... tree
#                     (default: output)
#   rpt_out_dir       Directory to write .rpt files
#                     (default: fpv_rpt)
# =============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
set BASE_DIR  = "output"
set RPT_DIR   = "fpv_rpt"

if ( $#argv >= 1 ) set BASE_DIR = $argv[1]
if ( $#argv >= 2 ) set RPT_DIR  = $argv[2]

set MODULES = ( fuse_distr_fsm fuse_mem_if_arb )

echo "=============================================================="
echo "  FPV LOG EXTRACTOR"
echo "  Date        : `date '+%Y-%m-%d %H:%M'`"
echo "  Base dir    : $BASE_DIR"
echo "  RPT out dir : $RPT_DIR"
echo "=============================================================="
echo ""

# ---------------------------------------------------------------------------
# Discover all customer directories under BASE_DIR
# ---------------------------------------------------------------------------
if ( ! -d "$BASE_DIR" ) then
    echo "ERROR: Base directory not found: $BASE_DIR"
    exit 1
endif

set CUSTOMERS = ( `ls -1 "$BASE_DIR"` )

if ( $#CUSTOMERS == 0 ) then
    echo "ERROR: No customer directories found under $BASE_DIR"
    exit 1
endif

# ---------------------------------------------------------------------------
# Create output RPT directories per module
# ---------------------------------------------------------------------------
foreach MOD ( $MODULES )
    if ( ! -d "${RPT_DIR}/${MOD}" ) then
        mkdir -p "${RPT_DIR}/${MOD}"
    endif
end

# ---------------------------------------------------------------------------
# Process each customer x module combination
# ---------------------------------------------------------------------------
set total_extracted = 0
set total_missing   = 0

foreach CUST_DIR ( $CUSTOMERS )
    set CUST_PATH = "${BASE_DIR}/${CUST_DIR}"
    if ( ! -d "$CUST_PATH" ) continue

    # Strip "fuse_" prefix from customer dir name for display (e.g. fuse_DMRDARW -> DMRDARW)
    set CUST_NAME = `echo "$CUST_DIR" | sed 's/^fuse_//'`

    foreach MOD ( $MODULES )
        # Locate the log file for this customer + module
        # Pattern: output/<cust>/jasper/fuse_fpv_<mod>_out/jg_fpv/log/*.rpt or *.log
        set LOG_DIR = "${CUST_PATH}/jasper/fuse_fpv_${MOD}_out/jg_fpv/log"

        if ( ! -d "$LOG_DIR" ) then
            echo "  [SKIP] $CUST_NAME / $MOD  -- log dir not found: $LOG_DIR"
            @ total_missing++
            continue
        endif

        # Find the first .rpt or .log file in the log directory
        set LOG_FILE = ""
        foreach EXT ( rpt log )
            set CANDIDATE = `ls -1 ${LOG_DIR}/*.${EXT} 2>/dev/null | head -1`
            if ( "$CANDIDATE" != "" && -f "$CANDIDATE" ) then
                set LOG_FILE = "$CANDIDATE"
                break
            endif
        end

        if ( "$LOG_FILE" == "" ) then
            echo "  [SKIP] $CUST_NAME / $MOD  -- no .rpt or .log file in $LOG_DIR"
            @ total_missing++
            continue
        endif

        echo "  [EXTRACT] $CUST_NAME / $MOD"
        echo "            Log : $LOG_FILE"

        # Output .rpt path
        set OUT_RPT = "${RPT_DIR}/${MOD}/${CUST_NAME}.rpt"

        # -------------------------------------------------------------------
        # Extract SUMMARY block and parse fields using awk
        # -------------------------------------------------------------------
        awk -v cust="$CUST_NAME" -v module="$MOD" '
        BEGIN {
            in_summary      = 0
            props_total     = 0
            assert_total    = 0
            assert_proven   = 0
            assert_cex      = 0
            covers_total    = 0
            covers_covered  = 0
            covers_unreach  = 0
        }

        # Enter summary block
        /^={10,}/ { if ( in_summary == 1 ) in_summary = 2; next }
        /SUMMARY/  { if ( in_summary == 0 ) { in_summary = 1 }; next }

        # Parse fields inside summary block
        in_summary == 2 {
            # Properties Considered
            if ( $0 ~ /Properties Considered/ ) {
                match($0, /: *([0-9]+)/, a); props_total = a[1] + 0
            }
            # assertions total
            if ( $0 ~ /^ *assertions/ && $0 !~ /- / ) {
                match($0, /: *([0-9]+)/, a); assert_total = a[1] + 0
            }
            # proven
            if ( $0 ~ /- proven/ && $0 !~ /bounded/ && $0 !~ /marked/ ) {
                match($0, /: *([0-9]+)/, a); assert_proven = a[1] + 0
            }
            # cex
            if ( $0 ~ /- cex/ && $0 !~ /ar_cex/ ) {
                match($0, /: *([0-9]+)/, a); assert_cex = a[1] + 0
            }
            # covers total
            if ( $0 ~ /^ *covers/ && $0 !~ /- / ) {
                match($0, /: *([0-9]+)/, a); covers_total = a[1] + 0
            }
            # covered
            if ( $0 ~ /- covered/ && $0 !~ /ar_covered/ && $0 !~ /bounded/ ) {
                match($0, /: *([0-9]+)/, a); covers_covered = a[1] + 0
            }
            # unreachable
            if ( $0 ~ /- unreachable/ && $0 !~ /bounded/ ) {
                match($0, /: *([0-9]+)/, a); covers_unreach = a[1] + 0
            }
        }

        END {
            # Compute percentages
            if ( assert_total > 0 )
                proven_pct = assert_proven / assert_total * 100
            else
                proven_pct = 0

            if ( covers_total > 0 )
                covered_pct = covers_covered / covers_total * 100
            else
                covered_pct = 0

            # Format proven as "proven/total"
            proven_str  = assert_proven "/" assert_total
            covered_str = sprintf("%.4f%%", covered_pct)

            # Determine pass/fail status
            if ( assert_cex > 0 ) {
                status = "FAIL"
            } else if ( assert_proven == assert_total && assert_total > 0 ) {
                status = "PASS"
            } else if ( assert_proven > 0 ) {
                status = "PARTIAL"
            } else {
                status = "EMPTY"
            }

            # Write .rpt in standard table format
            SEP = "+-----------------------"
            print "FPV summary on " module
            print SEP
            printf "| %-12s | %-8s | %-10s |\n", "cust", "proven", "covered"
            print SEP
            printf "| %-12s | %-8s | %-10s |\n", cust, proven_str, covered_str
            print SEP
            print ""
            print "# --- Detail ---"
            print "# Properties Considered : " props_total
            print "# Assertions total      : " assert_total
            print "# Assertions proven     : " assert_proven
            print "# Assertions cex        : " assert_cex
            print "# Covers total          : " covers_total
            print "# Covers covered        : " covers_covered
            print "# Covers unreachable    : " covers_unreach
            print "# Status                : " status
        }
        ' "$LOG_FILE" > "$OUT_RPT"

        if ( $status == 0 ) then
            echo "            RPT : $OUT_RPT  [OK]"
            @ total_extracted++
        else
            echo "            RPT : FAILED to extract from $LOG_FILE"
            @ total_missing++
        endif

    end  # foreach MOD
end  # foreach CUST_DIR

echo ""
echo "=============================================================="
echo "  Extraction complete"
echo "  Extracted : $total_extracted"
echo "  Skipped   : $total_missing"
echo "  RPT files : $RPT_DIR/"
echo "=============================================================="
exit 0
