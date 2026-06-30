#!/bin/csh -f
# =============================================================================
# extract_fpv_rpt.csh
# =============================================================================

# ---------------------------------------------------------------------------
# Fixed NFS paths -- update here if project paths change
# ---------------------------------------------------------------------------
set DEFAULT_BASE_DIR = "/nfs/site/disks/zsc11_fuse_00003/ip-fuse-gen4p1-cth-uvm-FPV-cron/ip-fuse-gen4p1-cth/output"
set DEFAULT_RPT_DIR  = "/nfs/site/disks/zsc11_fuse_00003/ip-fuse-gen4p1-cth-uvm-FPV-cron/scripts/fpv_rpt"

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
    set RPT_DIR = "$DEFAULT_RPT_DIR"
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
    exit 1
endif

# ---------------------------------------------------------------------------
# Create RPT root directory early if it does not exist
# ---------------------------------------------------------------------------
if ( ! -d "$RPT_DIR" ) then
    echo "  Creating RPT dir : $RPT_DIR"
    mkdir -p "$RPT_DIR"
    if ( $status != 0 ) then
        echo "ERROR: Failed to create RPT directory: $RPT_DIR"
        exit 1
    endif
endif

# ---------------------------------------------------------------------------
# Write awk parser to temp file
#
# Actual structure (verified with cat -A):
#   ==============================================================$   <- fence line 3149
#   SUMMARY$                                                          <- line 3150
#   ==============================================================$   <- fence line 3151 -> START data
#            Properties Considered              : 388$
#                  assertions                   : 121$
#                  - proven                    : 121 (100%)$
#                  - cex                       : 0 (0%)$
#                 covers                       : 267$
#                  - unreachable               : 196 (73.4082%)$
#                  - covered                   : 71 (26.5918%)$
#   INFO (IPF177): ...                                                <- first non-data line -> STOP
#
# The block has NO closing fence -- it ends when a non-indented INFO line appears.
# Strategy: record line number of SUMMARY keyword.
#           The fence at SUMMARY+1 starts collection.
#           Collection stops when a line does NOT start with whitespace
#           (i.e. the INFO lines after the data block).
# ---------------------------------------------------------------------------
set AWK_SCRIPT = "/tmp/fpv_parse_$$.awk"

cat > "$AWK_SCRIPT" << 'AWKEOF'
BEGIN {
    summary_line   = 0
    collecting     = 0
    props_total    = 0
    assert_total   = 0
    assert_proven  = 0
    assert_cex     = 0
    covers_total   = 0
    covers_covered = 0
    covers_unreach = 0
}

# Record line number when we see bare "SUMMARY"
$0 == "SUMMARY" {
    summary_line = NR
    next
}

# The fence line immediately after SUMMARY starts collection
index($0, "===") == 1 && NR == summary_line + 1 {
    collecting = 1
    next
}

# While collecting: stop if line does not start with whitespace
# (the data lines all start with spaces; INFO lines start with "I")
collecting == 1 && $0 !~ /^[ \t]/ {
    collecting = 0
    next
}

# Parse data lines
collecting == 1 {
    # Properties Considered : 388
    if ( index($0, "Properties Considered") > 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        props_total = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # assertions : 121  (not a sub-item)
    if ( index($0, "assertions") > 0 && index($0, "-") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        assert_total = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # - proven : 121  (not bounded, not marked)
    if ( index($0, "- proven") > 0 && index($0, "bounded") == 0 && index($0, "marked") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        assert_proven = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # - cex : 0  (not ar_cex)
    if ( index($0, "- cex") > 0 && index($0, "ar_cex") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        assert_cex = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # covers : 267  (not a sub-item)
    if ( index($0, "covers") > 0 && index($0, "-") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        covers_total = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # - covered : 71  (not ar_covered, not bounded)
    if ( index($0, "- covered") > 0 && index($0, "ar_covered") == 0 && index($0, "bounded") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        covers_covered = substr(a[length(a)], RSTART, RLENGTH) + 0
    }
    # - unreachable : 196  (not bounded)
    if ( index($0, "- unreachable") > 0 && index($0, "bounded") == 0 ) {
        split($0, a, ":")
        match(a[length(a)], /[0-9]+/)
        covers_unreach = substr(a[length(a)], RSTART, RLENGTH) + 0
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
AWKEOF

# ---------------------------------------------------------------------------
# Discover customer directories (fuse_* excluding fuse_*_visa)
# ---------------------------------------------------------------------------
set ALL_DIRS  = ( ${BASE_DIR}/fuse_* )
set CUST_DIRS = ()

foreach D ( $ALL_DIRS )
    if ( ! -d "$D" ) continue
    set DNAME = `basename "$D"`
    if ( "$DNAME" =~ *_visa ) then
        echo "  [SKIP] $DNAME -- visa directory, skipping"
        continue
    endif
    set CUST_DIRS = ( $CUST_DIRS $D )
end

if ( $#CUST_DIRS == 0 ) then
    echo "ERROR: No valid customer directories (fuse_*, excluding fuse_*_visa) found under $BASE_DIR"
    ls "$BASE_DIR"
    rm -f "$AWK_SCRIPT"
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

    if ( ! -d "$CUST_FULL" ) continue

    set CUST_DIR  = `basename "$CUST_FULL"`
    set CUST_NAME = `echo "$CUST_DIR" | sed 's/^fuse_//'`

    set JASPER_DIR = "${CUST_FULL}/jasper"
    if ( ! -d "$JASPER_DIR" ) then
        echo "  [SKIP] $CUST_NAME -- no jasper/ directory at $JASPER_DIR"
        continue
    endif

    set MOD_DIRS = ( ${JASPER_DIR}/fuse_fpv_*_out )

    if ( ! -d "$MOD_DIRS[1]" ) then
        echo "  [SKIP] $CUST_NAME -- no fuse_fpv_*_out dirs in $JASPER_DIR"
        continue
    endif

    foreach MOD_FULL ( $MOD_DIRS )

        if ( ! -d "$MOD_FULL" ) continue

        set MOD_DIR  = `basename "$MOD_FULL"`
        set MOD_NAME = `echo "$MOD_DIR" | sed 's/^fuse_fpv_//' | sed 's/_out$//'`

        set LOG_DIR = "${MOD_FULL}/jg_fpv/log"
        if ( ! -d "$LOG_DIR" ) then
            echo "  [SKIP] $CUST_NAME / $MOD_NAME -- log dir not found: $LOG_DIR"
            @ total_missing++
            continue
        endif

        # Priority: fuse.fpv.log > *.log > *.rpt
        set LOG_FILE = ""

        if ( -f "${LOG_DIR}/fuse.fpv.log" ) then
            set LOG_FILE = "${LOG_DIR}/fuse.fpv.log"
        else
            set LOG_CANDS = ( ${LOG_DIR}/*.log )
            if ( -f "$LOG_CANDS[1]" ) then
                set LOG_FILE = "$LOG_CANDS[1]"
            else
                set RPT_CANDS = ( ${LOG_DIR}/*.rpt )
                if ( -f "$RPT_CANDS[1]" ) then
                    set LOG_FILE = "$RPT_CANDS[1]"
                endif
            endif
        endif

        if ( "$LOG_FILE" == "" ) then
            echo "  [SKIP] $CUST_NAME / $MOD_NAME -- no fuse.fpv.log / *.log / *.rpt in $LOG_DIR"
            @ total_missing++
            continue
        endif

        echo "  [EXTRACT] $CUST_NAME / $MOD_NAME"
        echo "            Log : $LOG_FILE"

        # Create per-module subdir under RPT_DIR
        if ( ! -d "${RPT_DIR}/${MOD_NAME}" ) then
            mkdir -p "${RPT_DIR}/${MOD_NAME}"
            if ( $status != 0 ) then
                echo "  ERROR: Failed to create ${RPT_DIR}/${MOD_NAME}"
                @ total_missing++
                continue
            endif
        endif

        set OUT_RPT = "${RPT_DIR}/${MOD_NAME}/${CUST_NAME}.rpt"

        awk -v cust="$CUST_NAME" \
            -v module="$MOD_NAME" \
            -v logfile="$LOG_FILE" \
            -f "$AWK_SCRIPT" \
            "$LOG_FILE" > "$OUT_RPT"

        if ( $status == 0 ) then
            echo "            RPT : $OUT_RPT  [OK]"
            @ total_extracted++
        else
            echo "            RPT : FAILED to extract from $LOG_FILE"
            @ total_missing++
        endif

    end  # foreach MOD_FULL
end  # foreach CUST_FULL

rm -f "$AWK_SCRIPT"

echo ""
echo "=============================================================="
echo "  Extraction complete"
echo "  Extracted : $total_extracted"
echo "  Skipped   : $total_missing"
echo "  RPT files : $RPT_DIR/"
echo "=============================================================="
exit 0
