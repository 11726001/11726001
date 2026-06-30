#!/bin/csh -f
# =============================================================================
# generate_fpv_html.csh
# -----------------------------------------------------------------------------
# Compiles FPV results from both modules (fuse_distr_fsm, fuse_mem_if_arb)
# into a styled HTML report and optionally sends it via Intel internal SMTP.
#
# Usage:
#   csh generate_fpv_html.csh <report_file> [output.html] [--send]
#
# Arguments:
#   report_file   Path to the raw FPV report text file  (required)
#   output.html   Output HTML file path                 (optional, default: fpv_report.html)
#   --send        Send email after generating HTML      (optional flag)
#
# Dependencies:
#   - awk  (for parsing)
#   - python3 (for SMTP email sending — inline, no extra files needed)
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

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
if ( $#argv < 1 ) then
    echo "Usage: csh generate_fpv_html.csh <report_file> [output.html] [--send]"
    exit 1
endif

set REPORT_FILE = $argv[1]
set OUTPUT_HTML = "fpv_report.html"
set DO_SEND     = 0

if ( $#argv >= 2 ) then
    if ( "$argv[2]" == "--send" ) then
        set DO_SEND = 1
    else
        set OUTPUT_HTML = $argv[2]
    endif
endif

if ( $#argv >= 3 ) then
    if ( "$argv[3]" == "--send" ) then
        set DO_SEND = 1
    endif
endif

if ( ! -f "$REPORT_FILE" ) then
    echo "ERROR: Report file not found: $REPORT_FILE"
    exit 1
endif

# ---------------------------------------------------------------------------
# Work week calculation (ISO week number)
# ---------------------------------------------------------------------------
set WW_NUM  = `date +%V`
set WW_YEAR = `date +%Y`
set WW_STR  = "WW${WW_NUM} ${WW_YEAR}"
set NOW_STR = `date '+%Y-%m-%d %H:%M'`
set SUBJECT = "${REPORT_NAME} - ${WW_STR}"

echo "Parsing report : $REPORT_FILE"
echo "Output HTML    : $OUTPUT_HTML"
echo "Work week      : $WW_STR"
echo ""

# ---------------------------------------------------------------------------
# Parse raw report with awk, emit HTML
# ---------------------------------------------------------------------------
awk -v report_file="$REPORT_FILE" \
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

    # Emit HTML header
    print "<!DOCTYPE html>"
    print "<html lang=\"en\">"
    print "<head>"
    print "  <meta charset=\"UTF-8\">"
    print "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
    print "  <title>" report_name " - " ww_str "</title>"
    print "</head>"
    print "<body style=\"margin:0;padding:0;background:#f4f6f9;font-family:Arial,sans-serif;\">"
    print "<div style=\"max-width:860px;margin:32px auto;background:#fff;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1);overflow:hidden;\">"

    # Header bar
    print "  <div style=\"background:#0071c5;padding:24px 32px;\">"
    print "    <h1 style=\"color:#fff;margin:0;font-size:22px;\">" report_name "</h1>"
    print "    <p style=\"color:#cce4ff;margin:4px 0 0 0;font-size:14px;\">" ww_str " &nbsp;|&nbsp; Generated: " now_str "</p>"
    print "  </div>"
    print "  <div style=\"padding:28px 32px;\">"
}

# Detect module header
/^FPV summary on / {
    if ( module != "" ) flush_module()
    module     = $NF
    in_data    = 0
    row_count  = 0
    all_pass   = 1
    any_cover  = 0
    total_mods++
    delete cust_arr
    delete proven_arr
    delete total_arr
    delete cover_arr
    next
}

# Skip separator lines
/^\+[-+]+/ { next }

# Skip header row
/cust/ && /proven/ && /covered/ { in_data = 1; next }

# Data rows
/^\|/ && in_data {
    line = $0
    gsub(/^\|/, "", line)
    gsub(/\|$/, "", line)
    n = split(line, cols, "|")
    if ( n < 3 ) next
    cust    = cols[1]; gsub(/^ +| +$/, "", cust)
    proven  = cols[2]; gsub(/^ +| +$/, "", proven)
    covered = cols[3]; gsub(/^ +| +$/, "", covered)

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

    # Overall summary block
    if ( pass_count == total_mods && total_mods > 0 ) {
        o_bg = "#d4edda"; o_fg = "#155724"; o_lbl = "PASS"
    } else if ( pass_count > 0 ) {
        o_bg = "#fff3cd"; o_fg = "#856404"; o_lbl = "PARTIAL"
    } else if ( total_mods > 0 ) {
        o_bg = "#f8d7da"; o_fg = "#721c24"; o_lbl = "FAIL"
    } else {
        o_bg = "#e2e3e5"; o_fg = "#383d41"; o_lbl = "EMPTY"
    }
    badge = "<span style=\"background:" o_bg ";color:" o_fg ";padding:3px 10px;border-radius:4px;font-weight:bold;font-size:0.85em;\">" o_lbl "</span>"

    print "    <div style=\"background:#f0f4ff;border:1px solid #c8d8f0;border-radius:6px;padding:16px 20px;margin-bottom:28px;\">" 
    print "      <h3 style=\"margin:0 0 10px 0;color:#2c3e50;\">Overall Summary &nbsp; " badge "</h3>"
    print "      <table style=\"font-size:14px;color:#333;\">"
    print "        <tr><td style=\"padding:2px 8px;\">Modules checked:</td><td><strong>" total_mods "</strong></td></tr>"
    print "        <tr><td style=\"padding:2px 8px;\">Modules passing:</td><td><strong>" pass_count "</strong></td></tr>"
    print "        <tr><td style=\"padding:2px 8px;\">Modules failing/empty:</td><td><strong>" total_mods - pass_count "</strong></td></tr>"
    print "      </table>"
    print "    </div>"

    # Module HTML collected in mod_html array
    for (i = 1; i <= mod_idx; i++) print mod_html[i]

    # Legend
    print "    <div style=\"margin-top:24px;border-top:1px solid #dee2e6;padding-top:16px;\">"
    print "      <h4 style=\"color:#555;margin-bottom:8px;\">Legend</h4>"
    print "      <table style=\"font-size:13px;\">"
    print "        <tr><td><span style=\"background:#d4edda;color:#155724;padding:2px 8px;border-radius:4px;font-weight:bold;\">PASS</span></td><td style=\"padding:4px 8px;\">All properties proven and covered</td></tr>"
    print "        <tr><td><span style=\"background:#fff3cd;color:#856404;padding:2px 8px;border-radius:4px;font-weight:bold;\">PARTIAL</span></td><td style=\"padding:4px 8px;\">Some properties unproven or uncovered</td></tr>"
    print "        <tr><td><span style=\"background:#f8d7da;color:#721c24;padding:2px 8px;border-radius:4px;font-weight:bold;\">FAIL</span></td><td style=\"padding:4px 8px;\">No properties proven</td></tr>"
    print "        <tr><td><span style=\"background:#e2e3e5;color:#383d41;padding:2px 8px;border-radius:4px;font-weight:bold;\">EMPTY</span></td><td style=\"padding:4px 8px;\">No results - check run or data issue</td></tr>"
    print "      </table>"
    print "    </div>"

    # Report path footer
    print "    <div style=\"margin-top:20px;font-size:12px;color:#888;border-top:1px solid #dee2e6;padding-top:12px;\">"
    print "      <strong>Report source:</strong> " report_file "<br>"
    print "      <strong>Report path:</strong> " report_path
    print "    </div>"
    print "  </div>" # end body padding div
    print "</div>"   # end outer card div
    print "</body>"
    print "</html>"
}

function flush_module(    i, t, bg, fg, lbl, badge, bar, row_bg, html, cov_int, bar_color, bar_w) {
    mod_idx++

    if ( row_count == 0 ) {
        bg = "#e2e3e5"; fg = "#383d41"; lbl = "EMPTY"
    } else if ( all_pass ) {
        bg = "#d4edda"; fg = "#155724"; lbl = "PASS"; pass_count++
    } else if ( any_cover ) {
        bg = "#fff3cd"; fg = "#856404"; lbl = "PARTIAL"
    } else {
        bg = "#f8d7da"; fg = "#721c24"; lbl = "FAIL"
    }

    badge = "<span style=\"background:" bg ";color:" fg ";padding:3px 10px;border-radius:4px;font-weight:bold;font-size:0.85em;\">" lbl "</span>"

    html  = "    <div style=\"margin-bottom:32px;\">\n"
    html  = html "      <h2 style=\"font-family:Arial,sans-serif;color:#2c3e50;border-left:5px solid #0071c5;padding-left:12px;\">" module " &nbsp; " badge "</h2>\n"
    html  = html "      <table style=\"border-collapse:collapse;width:100%;font-family:Arial,sans-serif;font-size:14px;border:1px solid #dee2e6;\">\n"
    html  = html "        <thead><tr style=\"background:#0071c5;color:#fff;\">\n"
    html  = html "          <th style=\"padding:10px 12px;text-align:left;\">Customer</th>\n"
    html  = html "          <th style=\"padding:10px 12px;text-align:center;\">Proven</th>\n"
    html  = html "          <th style=\"padding:10px 12px;text-align:center;\">Total</th>\n"
    html  = html "          <th style=\"padding:10px 12px;text-align:left;\">Coverage</th>\n"
    html  = html "        </tr></thead>\n        <tbody>\n"

    if ( row_count == 0 ) {
        html = html "          <tr><td colspan=\"4\" style=\"text-align:center;color:#999;font-style:italic;padding:10px;\">No data - verify FPV job completed successfully.</td></tr>\n"
    } else {
        for (i = 1; i <= row_count; i++) {
            row_bg = (i % 2 == 1) ? "#f9f9f9" : "#ffffff"
            t      = (total_arr[i] == "?") ? "?" : total_arr[i]
            cov_int = int(cover_arr[i])
            if ( cov_int > 100 ) cov_int = 100
            bar_color = (cover_arr[i] >= 80) ? "#28a745" : (cover_arr[i] >= 50) ? "#ffc107" : "#dc3545"
            bar = "<div style=\"background:#e9ecef;border-radius:4px;height:14px;width:120px;display:inline-block;vertical-align:middle;\"><div style=\"width:" cov_int "%;background:" bar_color ";height:14px;border-radius:4px;\"></div></div> <span style=\"font-size:0.85em;\">" cover_arr[i] "%</span>"
            html = html "          <tr style=\"background:" row_bg ";\">"
            html = html "<td style=\"padding:8px 12px;\">" cust_arr[i] "</td>"
            html = html "<td style=\"padding:8px 12px;text-align:center;\">" proven_arr[i] "</td>"
            html = html "<td style=\"padding:8px 12px;text-align:center;\">" t "</td>"
            html = html "<td style=\"padding:8px 12px;\">" bar "</td></tr>\n"
        }
    }
    html = html "        </tbody>\n      </table>\n    </div>"
    mod_html[mod_idx] = html

    # Reset
    row_count = 0; all_pass = 1; any_cover = 0
    delete cust_arr; delete proven_arr; delete total_arr; delete cover_arr
}
' "$REPORT_FILE" > "$OUTPUT_HTML"

if ( $status != 0 ) then
    echo "ERROR: awk parsing failed."
    exit 1
endif

echo "HTML report saved: $OUTPUT_HTML"

# ---------------------------------------------------------------------------
# Send email via inline Python3 (SMTP — no extra files needed)
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
