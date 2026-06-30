#!/bin/csh -f
# =============================================================================
# extract_fpv_rpt.csh
# -----------------------------------------------------------------------------
# Reads Jasper FPV log files, extracts the SUMMARY block, and writes one
# structured .rpt file per FPV module per customer.
#
# Log path pattern:
#   <BASE_DIR>/fuse_<CUSTOMER>/jasper/fuse_fpv_<MODULE>_out/jg_fpv/log/*.{rpt,log}
#
# - CUSTOMER : parsed from directory name  fuse_<CUSTOMER>
# - MODULE   : parsed from directory name  fuse_fpv_<MODULE>_out
#
# Output .rpt files are written to:
#   <RPT_DIR>/<MODULE>/<CUSTOMER>.rpt
#
# Usage:
#   csh extract_fpv_rpt.csh [base_output_dir] [rpt_out_dir]
#
# Arguments:
#   base_output_dir   Full path to directory containing fuse_* customer subdirs
#                     (default: fixed project NFS path below)
#   rpt_out_dir       Directory to write .rpt files
#                     (default: fpv_rpt/ next to this script)
# =============================================================================

# ---------------------------------------------------------------------------
# Fixed project NFS path — update here if project root changes
# ---------------------------------------------------------------------------
set DEFAULT_BASE_DIR = "/nfs/site/disks/zsc11_fuse_00003/ip-fuse-gen4p1-cth-uvm-FPV-cron/ip-fuse-gen4p1-cth/output"

set SCRIPT_DIR = `dirname $0`
set SCRIPT_DIR = `cd "$SCRIPT_DIR" && pwd`

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
if ( $#argv >= 1 ) then
    set BASE_DIR = $argv[1]
else
    set BASE_DIR = "$DEFAULT_BASE_DIR"
endif

if ( $#argv >= 2 ) then
    set RPT_DIR = $argv[2]
else
    set RPT_DIR = "${SCRIPT_DIR}/fpv_rpt"
endif

echo "=============================================================="
echo "  FPV LOG EXTRACTOR"
echo "  Date        : `date '+%Y-%m-%d %H:%M'`"
echo "  Base dir    : $BASE_DIR"
echo "  RPT out dir : $RPT_DIR"
echo "=============================================================="
echo ""

# ---------------------------------------------------------------------------
# Validate base directory
# ---------------------------------------------------------------------------
if ( ! -d "$BASE_DIR" ) then
    echo "ERROR: Base directory not found: $BASE_DIR"
    echo ""
    echo "  Please pass the correct path explicitly:"
    echo "  csh extract_fpv_rpt.csh <base_output_dir> [rpt_out_dir]"
    exit 1
endif

# ---------------------------------------------------------------------------
# Auto-discover customer directories (fuse_*) under BASE_DIR
# ---------------------------------------------------------------------------
set CUST_DIRS = ( `find "$BASE_DIR" -maxdepth 1 -type d -name "fuse_*" 2>/dev/null | sort` )

if ( $#CUST_DIRS == 0 ) then
    echo "ERROR: No customer directories (fuse_*) found under $BASE_DIR"
    exit 1
endif

echo "  Found $#CUST_DIRS customer dir(s):"
foreach D ( $CUST_DIRS )
    echo "    $D"
end
echo ""

# ---------------------------------------------------------------------------
# Process each customer x module combination
# ---------------------------------------------------------------------------
set total_extracted = 0
set total_missing   = 0

foreach CUST_FULL ( $CUST_DIRS )

    # Parse customer name: strip path and leading fuse_
    set CUST_DIR  = `basename "$CUST_FULL"`
    set CUST_NAME = `echo "$CUST_DIR" | sed 's/^fuse_//'`

    set JASPER_DIR = "${CUST_FULL}/jasper"
    if ( ! -d "$JASPER_DIR" ) then
        echo "  [SKIP] $CUST_NAME -- no jasper/ directory at $JASPER_DIR"
        continue
    endif

    # Auto-discover all fuse_fpv_*_out module directories under jasper/
    set MOD_DIRS = ( `find "$JASPER_DIR" -maxdepth 1 -type d -name "fuse_fpv_*_out" 2>/dev/null | sort` )

    if ( $#MOD_DIRS == 0 ) then
        echo "  [SKIP] $CUST_NAME -- no fuse_fpv_*_out dirs in $JASPER_DIR"
        continue
    endif

    foreach MOD_FULL ( $MOD_DIRS )

        # Parse module name: strip fuse_fpv_ prefix and _out suffix
        set MOD_DIR  = `basename "$MOD_FULL"`
        set MOD_NAME = `echo "$MOD_DIR" | sed 's/^fuse_fpv_//' | sed 's/_out$//'`

        # Locate log directory
        set LOG_DIR = "${MOD_FULL}/jg_fpv/log"
        if ( ! -d "$LOG_DIR" ) then
            echo "  [SKIP] $CUST_NAME / $MOD_NAME -- log dir not found: $LOG_DIR"
            @ total_missing++
            continue
        endif

        # Find the first .rpt or .log file
        set LOG_FILE = ""
        foreach EXT ( rpt log )
            set CANDIDATE = `ls -1 ${LOG_DIR}/*.${EXT} 2>/dev/null | head -1`
            if ( "$CANDIDATE" != "" ) then
                if ( -f "$CANDIDATE" ) then
                    set LOG_FILE = "$CANDIDATE"
                    break
                endif
            endif
        end

        if ( "$LOG_FILE" == "" ) then
            echo "  [SKIP] $CUST_NAME / $MOD_NAME -- no .rpt or .log in $LOG_DIR"
            @ total_missing++
            continue
        endif

        echo "  [EXTRACT] $CUST_NAME / $MOD_NAME"
        echo "            Log : $LOG_FILE"

        # Create output RPT dir for this module if needed
        if ( ! -d "${RPT_DIR}/${MOD_NAME}" ) then
            mkdir -p "${RPT_DIR}/${MOD_NAME}"
        endif

        set OUT_RPT = "${RPT_DIR}/${MOD_NAME}/${CUST_NAME}.rpt"

        # -------------------------------------------------------------------
        # Parse SUMMARY block with awk and write structured .rpt
        # -------------------------------------------------------------------
        awk -v cust="$CUST_NAME" -v module="$MOD_NAME" -v logfile="$LOG_FILE" '
        BEGIN {
            in_summary     = 0
            props_total    = 0
            assert_total   = 0
            assert_proven  = 0
            assert_cex     = 0
            covers_total   = 0
            covers_covered = 0
            covers_unreach = 0
        }

        # State machine: SUMMARY keyword then ==== fence activates parsing
        /SUMMARY/ {
            if ( in_summary == 0 ) { in_summary = 1 }
            next
        }
        /^={10,}/ {
            if ( in_summary == 1 ) { in_summary = 2 }
            next
        }

        in_summary == 2 {
            if ( $0 ~ /Properties Considered/ ) {
                match($0, /[0-9]+/); props_total = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /^ *assertions *:/ ) {
                match($0, /[0-9]+/); assert_total = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /- proven *:/ && $0 !~ /bounded/ && $0 !~ /marked/ ) {
                match($0, /[0-9]+/); assert_proven = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /- cex *:/ && $0 !~ /ar_cex/ ) {
                match($0, /[0-9]+/); assert_cex = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /^ *covers *:/ ) {
                match($0, /[0-9]+/); covers_total = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /- covered *:/ && $0 !~ /ar_covered/ && $0 !~ /bounded/ ) {
                match($0, /[0-9]+/); covers_covered = substr($0, RSTART, RLENGTH) + 0
            }
            if ( $0 ~ /- unreachable *:/ && $0 !~ /bounded/ ) {
                match($0, /[0-9]+/); covers_unreach = substr($0, RSTART, RLENGTH) + 0
            }
        }

        END {
            proven_pct  = (assert_total > 0) ? assert_proven  / assert_total  * 100 : 0
            covered_pct = (covers_total > 0) ? covers_covered / covers_total  * 100 : 0

            proven_str  = assert_proven "/" assert_total
            covered_str = sprintf("%.4f%%", covered_pct)

            if      ( assert_cex > 0 )                                   status = "FAIL"
            else if ( assert_proven == assert_total && assert_total > 0 ) status = "PASS"
            else if ( assert_proven > 0 )                                 status = "PARTIAL"
            else                                                          status = "EMPTY"

            SEP = "+-----------------------"
            print "FPV summary on " module
            print SEP
            printf "| %-12s | %-8s | %-10s |\n", "cust", "proven", "covered"
            print SEP
            printf "| %-12s | %-8s | %-10s |\n", cust, proven_str, covered_str
            print SEP
            print ""
            print "# --- Detail ---"
            print "# Log file               : " logfile
            print "# Properties Considered  : " props_total
            print "# Assertions total       : " assert_total
            print "# Assertions proven      : " assert_proven
            print "# Assertions cex         : " assert_cex
            print "# Covers total           : " covers_total
            print "# Covers covered         : " covers_covered
            print "# Covers unreachable     : " covers_unreach
            print "# Status                 : " status
        }
        ' "$LOG_FILE" > "$OUT_RPT"

        if ( $status == 0 ) then
            echo "            RPT : $OUT_RPT  [OK]"
            @ total_extracted++
        else
            echo "            RPT : FAILED to extract from $LOG_FILE"
            @ total_missing++
        endif

    end  # foreach MOD_FULL
end  # foreach CUST_FULL

echo ""
echo "=============================================================="
echo "  Extraction complete"
echo "  Extracted : $total_extracted"
echo "  Skipped   : $total_missing"
echo "  RPT files : $RPT_DIR/"
echo "=============================================================="
exit 0
