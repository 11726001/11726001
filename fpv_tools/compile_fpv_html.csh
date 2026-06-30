#!/bin/csh -f
# =============================================================================
# compile_fpv_html.csh
# -----------------------------------------------------------------------------
# Reads all .rpt files produced by extract_fpv_rpt.csh and compiles them
# into a single styled HTML report, then optionally emails it.
#
# Expected .rpt directory structure:
#   <rpt_dir>/
#     fuse_distr_fsm/
#       DMRDARW.rpt
#       CUSTB.rpt
#       ...
#     fuse_mem_if_arb/
#       DMRDARW.rpt
#       CUSTB.rpt
#       ...
#
# Usage:
#   csh compile_fpv_html.csh [rpt_dir] [output.html] [--send]
#
# Arguments:
#   rpt_dir       Directory containing per-module .rpt files (default: fpv_rpt)
#   output.html   Output HTML file                           (default: fpv_report.html)
#   --send        Send HTML report via Intel SMTP after generation
# =============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
set SMTP_HOST   = "smtp.intel.com"
set SMTP_PORT   = 25
set SENDER      = "mohamad.nor.azam.hassan@intel.com"
set RECIPIENTS  = "mohamad.nor.azam.hassan@intel.com"
set REPORT_NAME = "FPV Report"
set REPORT_PATH = "/nfs/site/disks/zsc11_fuse_00003/ip-fuse-gen4p1-cth-uvm-FPV-cron/scripts/result_checks_softstrap_oob/"
set MODULES     = ( fuse_distr_fsm fuse_mem_if_arb )

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
set RPT_DIR     = "fpv_rpt"
set OUTPUT_HTML = "fpv_report.html"
set DO_SEND     = 0

if ( $#argv >= 1 ) then
    if ( "$argv[1]" == "--send" ) then
        set DO_SEND = 1
    else
        set RPT_DIR = $argv[1]
    endif
endif

if ( $#argv >= 2 ) then
    if ( "$argv[2]" == "--send" ) then
        set DO_SEND = 1
    else
        set OUTPUT_HTML = $argv[2]
    endif
endif

if ( $#argv >= 3 ) then
    if ( "$argv[3]" == "--send" ) set DO_SEND = 1
endif

if ( ! -d "$RPT_DIR" ) then
    echo "ERROR: RPT directory not found: $RPT_DIR"
    exit 1
endif

# ---------------------------------------------------------------------------
# Work week + timestamp
# ---------------------------------------------------------------------------
set WW_NUM  = `date +%V`
set WW_YEAR = `date +%Y`
set WW_STR  = "WW${WW_NUM} ${WW_YEAR}"
set NOW_STR = `date '+%Y-%m-%d %H:%M'`
set SUBJECT = "${REPORT_NAME} - ${WW_STR}"

echo "=============================================================="
echo "  FPV HTML COMPILER"
echo "  Work week  : $WW_STR"
echo "  RPT dir    : $RPT_DIR"
echo "  Output     : $OUTPUT_HTML"
echo "=============================================================="
echo ""

# ---------------------------------------------------------------------------
# Build a merged flat report file: combine all .rpt files per module
# so we can pass one stream to awk for HTML generation
# ---------------------------------------------------------------------------
set MERGED_RPT = "/tmp/fpv_merged_$$.rpt"
if ( -f "$MERGED_RPT" ) rm -f "$MERGED_RPT"
touch "$MERGED_RPT"

foreach MOD ( $MODULES )
    set MOD_DIR = "${RPT_DIR}/${MOD}"
    if ( ! -d "$MOD_DIR" ) then
        echo "  [WARN] Module dir not found: $MOD_DIR -- skipping"
        # Write an empty placeholder so module still appears in HTML
        echo "FPV summary on ${MOD}"  >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo "| cust         | proven   | covered    |" >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo ""                          >> "$MERGED_RPT"
        continue
    endif

    # Collect all .rpt files for this module
    set RPT_FILES = ( `ls -1 ${MOD_DIR}/*.rpt 2>/dev/null` )

    if ( $#RPT_FILES == 0 ) then
        echo "  [WARN] No .rpt files in $MOD_DIR -- writing empty placeholder"
        echo "FPV summary on ${MOD}"  >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo "| cust         | proven   | covered    |" >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo "+-----------------------" >> "$MERGED_RPT"
        echo ""                          >> "$MERGED_RPT"
        continue
    endif

    # Write module header once
    echo "FPV summary on ${MOD}" >> "$MERGED_RPT"
    echo "+-----------------------" >> "$MERGED_RPT"
    echo "| cust         | proven   | covered    |" >> "$MERGED_RPT"
    echo "+-----------------------" >> "$MERGED_RPT"

    # Append data rows from each .rpt (skip header/separator/comment lines)
    foreach RPT ( $RPT_FILES )
        echo "  [INCLUDE] $RPT"
        # Extract only the data row line (line starting with | but not header)
        grep -E '^\|' "$RPT" | grep -v 'cust' >> "$MERGED_RPT"
    end

    echo "+-----------------------" >> "$MERGED_RPT"
    echo ""                          >> "$MERGED_RPT"
end

echo ""
echo "Merged RPT : $MERGED_RPT"

# ---------------------------------------------------------------------------
# Generate HTML from merged RPT using awk
# ---------------------------------------------------------------------------
awk -v report_file="$MERGED_RPT" \
    -v report_name="$REPORT_NAME" \
    -v ww_str="$WW_STR" \
    -v now_str="$NOW_STR" \
    -v report_path="$REPORT_PATH" \
'
BEGIN {
    module      = ""
    in_data     = 0
    pass_count  = 0
    total_mods  = 0
    mod_idx     = 0

    print "<!DOCTYPE html>"
    print "<html lang=\"en\">"
    print "<head>"
    print "  <meta charset=\"UTF-8\">"
    print "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
    print "  <title>" report_name " - " ww_str "</title>"
    print "  <style>"
    print "    body { margin:0; padding:0; background:#f4f6f9; font-family:Arial,sans-serif; }"
    print "    .card { max-width:960px; margin:32px auto; background:#fff; border-radius:8px; box-shadow:0 2px 8px rgba(0,0,0,0.1); overflow:hidden; }"
    print "    .header { background:#0071c5; padding:24px 32px; }"
    print "    .header h1 { color:#fff; margin:0; font-size:22px; }"
    print "    .header p  { color:#cce4ff; margin:4px 0 0 0; font-size:14px; }"
    print "    .body { padding:28px 32px; }"
    print "    .summary-box { background:#f0f4ff; border:1px solid #c8d8f0; border-radius:6px; padding:16px 20px; margin-bottom:28px; }"
    print "    .mod-title { font-family:Arial,sans-serif; color:#2c3e50; border-left:5px solid #0071c5; padding-left:12px; }"
    print "    table.data { border-collapse:collapse; width:100%; font-size:14px; border:1px solid #dee2e6; }"
    print "    table.data th { background:#0071c5; color:#fff; padding:10px 12px; }"
    print "    table.data td { padding:8px 12px; }"
    print "    .badge { padding:3px 10px; border-radius:4px; font-weight:bold; font-size:0.85em; }"
    print "    .footer { margin-top:20px; font-size:12px; color:#888; border-top:1px solid #dee2e6; padding-top:12px; }"
    print "  </style>"
    print "</head>"
    print "<body>"
    print "<div class=\"card\">"
    print "  <div class=\"header\">"
    print "    <h1>" report_name "</h1>"
    print "    <p>" ww_str " &nbsp;|&nbsp; Generated: " now_str "</p>"
    print "  </div>"
    print "  <div class=\"body\">"
}

# Detect module header
/^FPV summary on / {
    if ( module != "" ) flush_module()
    module    = $NF
    in_data   = 0
    row_count = 0
    all_pass  = 1
    any_cover = 0
    has_cex   = 0
    total_mods++
    delete cust_arr; delete proven_arr; delete total_arr
    delete cover_arr; delete cex_arr
    next
}

# Skip separator and comment lines
/^\+[-+]+/  { next }
/^#/        { next }

# Skip header row
/cust/ && /proven/ && /covered/ { in_data = 1; next }

# Data rows: | CUSTNAME | proven/total | covered% |
/^\|/ && in_data {
    line = $0
    gsub(/^\|/, "", line); gsub(/\|$/, "", line)
    n = split(line, cols, "|")
    if ( n < 3 ) next
    cust    = cols[1]; gsub(/^ +| +$/, "", cust)
    proven  = cols[2]; gsub(/^ +| +$/, "", proven)
    covered = cols[3]; gsub(/^ +| +$/, "", covered)
    if ( cust == "" ) next

    if ( index(proven, "/") > 0 ) {
        split(proven, pv, "/")
        p_count = pv[1] + 0
        t_count = pv[2] + 0
    } else {
        p_count = proven + 0
        t_count = "?"
    }
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

END {
    if ( module != "" ) flush_module()

    # Overall summary
    if      ( pass_count == total_mods && total_mods > 0 ) { o_bg="#d4edda"; o_fg="#155724"; o_lbl="PASS"    }
    else if ( pass_count > 0                              ) { o_bg="#fff3cd"; o_fg="#856404"; o_lbl="PARTIAL" }
    else if ( total_mods > 0                              ) { o_bg="#f8d7da"; o_fg="#721c24"; o_lbl="FAIL"    }
    else                                                    { o_bg="#e2e3e5"; o_fg="#383d41"; o_lbl="EMPTY"   }

    badge = "<span class=\"badge\" style=\"background:" o_bg ";color:" o_fg ";\">&nbsp;" o_lbl "&nbsp;</span>"

    print "    <div class=\"summary-box\">"
    print "      <h3 style=\"margin:0 0 10px 0;color:#2c3e50;\">Overall Summary &nbsp;" badge "</h3>"
    print "      <table style=\"font-size:14px;color:#333;\">"
    print "        <tr><td style=\"padding:2px 8px;\">Modules checked :</td><td><strong>" total_mods "</strong></td></tr>"
    print "        <tr><td style=\"padding:2px 8px;\">Modules passing :</td><td><strong>" pass_count "</strong></td></tr>"
    print "        <tr><td style=\"padding:2px 8px;\">Modules failing :</td><td><strong>" total_mods - pass_count "</strong></td></tr>"
    print "      </table>"
    print "    </div>"

    for (i = 1; i <= mod_idx; i++) print mod_html[i]

    # Legend
    print "    <div style=\"margin-top:24px;border-top:1px solid #dee2e6;padding-top:16px;\">"
    print "      <h4 style=\"color:#555;margin-bottom:8px;\">Legend</h4>"
    print "      <table style=\"font-size:13px;\">"
    print "        <tr><td><span class=\"badge\" style=\"background:#d4edda;color:#155724;\">PASS</span></td>   <td style=\"padding:4px 8px;\">All assertions proven, no CEX</td></tr>"
    print "        <tr><td><span class=\"badge\" style=\"background:#fff3cd;color:#856404;\">PARTIAL</span></td><td style=\"padding:4px 8px;\">Some assertions unproven</td></tr>"
    print "        <tr><td><span class=\"badge\" style=\"background:#f8d7da;color:#721c24;\">FAIL</span></td>   <td style=\"padding:4px 8px;\">Counter-example (CEX) found</td></tr>"
    print "        <tr><td><span class=\"badge\" style=\"background:#e2e3e5;color:#383d41;\">EMPTY</span></td>  <td style=\"padding:4px 8px;\">No results - check job completion</td></tr>"
    print "      </table>"
    print "    </div>"

    print "    <div class=\"footer\">"
    print "      <strong>Report path:</strong> " report_path "<br>"
    print "      <strong>Generated by:</strong> compile_fpv_html.csh"
    print "    </div>"
    print "  </div>"  # end .body
    print "</div>"    # end .card
    print "</body>"
    print "</html>"
}

function flush_module(    i, t, bg, fg, lbl, badge, bar, row_bg, html, cov_int, bar_color) {
    mod_idx++

    if      ( row_count == 0 ) { bg="#e2e3e5"; fg="#383d41"; lbl="EMPTY"   }
    else if ( all_pass        ) { bg="#d4edda"; fg="#155724"; lbl="PASS"; pass_count++ }
    else if ( any_cover       ) { bg="#fff3cd"; fg="#856404"; lbl="PARTIAL" }
    else                        { bg="#f8d7da"; fg="#721c24"; lbl="FAIL"    }

    badge = "<span class=\"badge\" style=\"background:" bg ";color:" fg ";\">&nbsp;" lbl "&nbsp;</span>"

    html  = "    <div style=\"margin-bottom:32px;\">\n"
    html  = html "      <h2 class=\"mod-title\">" module " &nbsp;" badge "</h2>\n"
    html  = html "      <table class=\"data\">\n"
    html  = html "        <thead><tr>"
    html  = html "<th style=\"text-align:left;\">Customer</th>"
    html  = html "<th style=\"text-align:center;\">Proven</th>"
    html  = html "<th style=\"text-align:center;\">Total Assertions</th>"
    html  = html "<th style=\"text-align:left;\">Coverage</th>"
    html  = html "</tr></thead>\n        <tbody>\n"

    if ( row_count == 0 ) {
        html = html "          <tr><td colspan=\"4\" style=\"text-align:center;color:#999;font-style:italic;padding:12px;\">No data &mdash; verify FPV job completed successfully.</td></tr>\n"
    } else {
        for (i = 1; i <= row_count; i++) {
            row_bg    = (i % 2 == 1) ? "#f9f9f9" : "#ffffff"
            t         = (total_arr[i] == "?") ? "?" : total_arr[i]
            cov_int   = int(cover_arr[i]); if (cov_int > 100) cov_int = 100
            bar_color = (cover_arr[i] >= 80) ? "#28a745" : (cover_arr[i] >= 50) ? "#ffc107" : "#dc3545"
            bar = "<div style=\"background:#e9ecef;border-radius:4px;height:14px;width:140px;display:inline-block;vertical-align:middle;\">" \
                  "<div style=\"width:" cov_int "%;background:" bar_color ";height:14px;border-radius:4px;\"></div></div>" \
                  " <span style=\"font-size:0.85em;\">" cover_arr[i] "%</span>"
            html = html "          <tr style=\"background:" row_bg ";\">" \
                        "<td>" cust_arr[i] "</td>" \
                        "<td style=\"text-align:center;\">" proven_arr[i] "</td>" \
                        "<td style=\"text-align:center;\">" t "</td>" \
                        "<td>" bar "</td></tr>\n"
        }
    }
    html = html "        </tbody>\n      </table>\n    </div>"
    mod_html[mod_idx] = html

    row_count = 0; all_pass = 1; any_cover = 0; has_cex = 0
    delete cust_arr; delete proven_arr; delete total_arr; delete cover_arr
}
' "$MERGED_RPT" > "$OUTPUT_HTML"

if ( $status != 0 ) then
    echo "ERROR: HTML generation failed."
    rm -f "$MERGED_RPT"
    exit 1
endif

rm -f "$MERGED_RPT"
echo "HTML report saved : $OUTPUT_HTML"

# ---------------------------------------------------------------------------
# Send email via inline Python3
# ---------------------------------------------------------------------------
if ( $DO_SEND == 1 ) then
    echo "Sending email via ${SMTP_HOST}:${SMTP_PORT} ..."

    python3 -c "
import smtplib, sys
from email.mime.multipart import MIMEMultipart
from email.mime.text      import MIMEText

smtp_host  = '${SMTP_HOST}'
smtp_port  =  ${SMTP_PORT}
sender     = '${SENDER}'
recipients = ['${RECIPIENTS}']
subject    = '${SUBJECT}'

try:
    with open('${OUTPUT_HTML}', 'r', encoding='utf-8') as f:
        html_body = f.read()
except Exception as e:
    print(f'ERROR reading HTML file: {e}')
    sys.exit(1)

msg = MIMEMultipart('alternative')
msg['Subject'] = subject
msg['From']    = sender
msg['To']      = ', '.join(recipients)
msg.attach(MIMEText(html_body, 'html'))

try:
    with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as s:
        s.sendmail(sender, recipients, msg.as_string())
    print(f'Email sent to: {chr(44).join(recipients)}')
    print(f'Subject: {subject}')
except Exception as e:
    print(f'ERROR sending email: {e}')
    sys.exit(1)
"

    if ( $status != 0 ) then
        echo "ERROR: Email sending failed."
        exit 1
    endif
endif

echo ""
echo "Done."
exit 0
