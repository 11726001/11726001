#!/usr/bin/env python3
"""
generate_fpv_html.py
---------------------
Compiles FPV results from both modules (fuse_distr_fsm, fuse_mem_if_arb)
into a styled HTML report and sends it via Intel internal SMTP.

Usage:
    python generate_fpv_html.py <report_file> [--output report.html] [--send]

Options:
    --output   Path to save the HTML file (default: fpv_report.html)
    --send     Send the HTML report via email after generating it
"""

import argparse
import smtplib
import sys
from datetime import datetime, date
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path

# Import parser from sibling module
sys.path.insert(0, str(Path(__file__).parent))
from parse_fpv_report import parse_fpv_report, ModuleResult

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SMTP_HOST   = "smtp.intel.com"
SMTP_PORT   = 25
SENDER      = "mohamad.nor.azam.hassan@intel.com"
RECIPIENTS  = [
    "mohamad.nor.azam.hassan@intel.com",
]
REPORT_NAME = "FPV Report"
REPORT_PATH = (
    "/nfs/site/disks/zsc11_fuse_00003/ip-fuse-gen4p1-cth-uvm-FPV-cron/"
    "scripts/result_checks_softstrap_oob/"
)

# ---------------------------------------------------------------------------
# Work week helper
# ---------------------------------------------------------------------------

def get_work_week(d: date | None = None) -> str:
    """Return work week string in 'WWxx yyyy' format (ISO week number)."""
    if d is None:
        d = date.today()
    week_num = d.isocalendar()[1]
    return f"WW{week_num:02d} {d.year}"


def get_email_subject() -> str:
    return f"{REPORT_NAME} - {get_work_week()}"


# ---------------------------------------------------------------------------
# Status helpers
# ---------------------------------------------------------------------------

STATUS_STYLE = {
    "PASS":    ("✅ PASS",    "#d4edda", "#155724"),
    "PARTIAL": ("⚠️ PARTIAL", "#fff3cd", "#856404"),
    "FAIL":    ("❌ FAIL",    "#f8d7da", "#721c24"),
    "EMPTY":   ("⬜ EMPTY",   "#e2e3e5", "#383d41"),
}


def status_badge(status: str) -> str:
    label, bg, fg = STATUS_STYLE.get(status, ("?", "#fff", "#000"))
    return (
        f'<span style="background:{bg};color:{fg};padding:3px 10px;'
        f'border-radius:4px;font-weight:bold;font-size:0.85em;">{label}</span>'
    )


def coverage_bar(pct: float) -> str:
    """Return an inline HTML progress bar for a coverage percentage."""
    color = "#28a745" if pct >= 80 else "#ffc107" if pct >= 50 else "#dc3545"
    return (
        f'<div style="background:#e9ecef;border-radius:4px;height:14px;width:120px;display:inline-block;vertical-align:middle;">'
        f'<div style="width:{min(pct,100):.1f}%;background:{color};height:14px;border-radius:4px;"></div>'
        f'</div> <span style="font-size:0.85em;">{pct:.1f}%</span>'
    )


# ---------------------------------------------------------------------------
# HTML builder
# ---------------------------------------------------------------------------

def build_module_table(mod: ModuleResult) -> str:
    status_label, bg, fg = STATUS_STYLE.get(mod.overall_status, ("?", "#fff", "#000"))
    badge = status_badge(mod.overall_status)

    rows_html = ""
    if mod.is_empty:
        rows_html = (
            '<tr><td colspan="4" style="text-align:center;color:#999;font-style:italic;">'
            'No data — verify FPV job completed successfully.'
            '</td></tr>'
        )
    else:
        for i, row in enumerate(mod.rows):
            row_bg = "#f9f9f9" if i % 2 == 0 else "#ffffff"
            total  = str(row["total"]) if row["total"] is not None else "?"
            rows_html += f"""
            <tr style="background:{row_bg};">
                <td style="padding:8px 12px;">{row['cust']}</td>
                <td style="padding:8px 12px;text-align:center;">{row['proven']}</td>
                <td style="padding:8px 12px;text-align:center;">{total}</td>
                <td style="padding:8px 12px;">{coverage_bar(row['covered_pct'])}</td>
            </tr>
            """

    return f"""
    <div style="margin-bottom:32px;">
        <h2 style="font-family:Arial,sans-serif;color:#2c3e50;border-left:5px solid #0071c5;padding-left:12px;">
            {mod.name} &nbsp; {badge}
        </h2>
        <table style="border-collapse:collapse;width:100%;font-family:Arial,sans-serif;font-size:14px;border:1px solid #dee2e6;border-radius:6px;overflow:hidden;">
            <thead>
                <tr style="background:#0071c5;color:#ffffff;">
                    <th style="padding:10px 12px;text-align:left;">Customer</th>
                    <th style="padding:10px 12px;text-align:center;">Proven</th>
                    <th style="padding:10px 12px;text-align:center;">Total</th>
                    <th style="padding:10px 12px;text-align:left;">Coverage</th>
                </tr>
            </thead>
            <tbody>
                {rows_html}
            </tbody>
        </table>
    </div>
    """


def build_html(results: list[ModuleResult], report_file: str) -> str:
    now       = datetime.now().strftime("%Y-%m-%d %H:%M")
    ww        = get_work_week()
    modules_html = "".join(build_module_table(m) for m in results)

    passing  = sum(1 for r in results if r.overall_status == "PASS")
    total    = len(results)
    overall_status = "PASS" if passing == total else "PARTIAL" if passing > 0 else "FAIL" if total > 0 else "EMPTY"
    overall_badge  = status_badge(overall_status)

    legend_rows = ""
    for key, (label, bg, fg) in STATUS_STYLE.items():
        legend_rows += (
            f'<tr><td style="padding:4px 8px;">'
            f'<span style="background:{bg};color:{fg};padding:2px 8px;border-radius:4px;font-weight:bold;">'
            f'{label}</span></td>'
            f'<td style="padding:4px 8px;font-size:13px;color:#555;">'
            + {
                "PASS":    "All properties proven and covered",
                "PARTIAL": "Some properties unproven or uncovered",
                "FAIL":    "No properties proven",
                "EMPTY":   "No results — check run or data issue",
            }[key]
            + "</td></tr>"
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{REPORT_NAME} - {ww}</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f9;font-family:Arial,sans-serif;">
<div style="max-width:860px;margin:32px auto;background:#ffffff;border-radius:8px;
            box-shadow:0 2px 8px rgba(0,0,0,0.1);overflow:hidden;">

    <!-- Header -->
    <div style="background:#0071c5;padding:24px 32px;">
        <h1 style="color:#ffffff;margin:0;font-size:22px;">{REPORT_NAME}</h1>
        <p style="color:#cce4ff;margin:4px 0 0 0;font-size:14px;">
            {ww} &nbsp;|&nbsp; Generated: {now}
        </p>
    </div>

    <!-- Body -->
    <div style="padding:28px 32px;">

        <!-- Overall Summary -->
        <div style="background:#f0f4ff;border:1px solid #c8d8f0;border-radius:6px;
                    padding:16px 20px;margin-bottom:28px;">
            <h3 style="margin:0 0 10px 0;color:#2c3e50;">Overall Summary &nbsp; {overall_badge}</h3>
            <table style="font-size:14px;color:#333;">
                <tr><td style="padding:2px 8px;">Modules checked:</td><td><strong>{total}</strong></td></tr>
                <tr><td style="padding:2px 8px;">Modules passing:</td><td><strong>{passing}</strong></td></tr>
                <tr><td style="padding:2px 8px;">Modules failing/empty:</td><td><strong>{total - passing}</strong></td></tr>
            </table>
        </div>

        <!-- Module Tables -->
        {modules_html}

        <!-- Legend -->
        <div style="margin-top:24px;border-top:1px solid #dee2e6;padding-top:16px;">
            <h4 style="color:#555;margin-bottom:8px;">Legend</h4>
            <table style="font-size:13px;">
                {legend_rows}
            </table>
        </div>

        <!-- Report Path -->
        <div style="margin-top:20px;font-size:12px;color:#888;border-top:1px solid #dee2e6;padding-top:12px;">
            <strong>Report source:</strong> {report_file}<br>
            <strong>Report path:</strong> {REPORT_PATH}
        </div>
    </div>
</div>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Email sender
# ---------------------------------------------------------------------------

def send_email(html_content: str, output_path: str) -> None:
    subject = get_email_subject()

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = SENDER
    msg["To"]      = ", ".join(RECIPIENTS)

    msg.attach(MIMEText(html_content, "html"))

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as server:
            server.sendmail(SENDER, RECIPIENTS, msg.as_string())
        print(f"✅ Email sent to: {', '.join(RECIPIENTS)}")
        print(f"   Subject: {subject}")
    except Exception as e:
        print(f"❌ Failed to send email: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate FPV HTML report and optionally email it."
    )
    parser.add_argument("report_file", help="Path to raw FPV report text file.")
    parser.add_argument(
        "--output", default="fpv_report.html",
        help="Output HTML file path (default: fpv_report.html)"
    )
    parser.add_argument(
        "--send", action="store_true",
        help="Send the HTML report via Intel internal SMTP after generating."
    )
    args = parser.parse_args()

    # Parse raw report
    print(f"📄 Parsing report: {args.report_file}")
    results = parse_fpv_report(args.report_file)

    # Build HTML
    html = build_html(results, args.report_file)

    # Save HTML file
    out_path = Path(args.output)
    out_path.write_text(html, encoding="utf-8")
    print(f"✅ HTML report saved: {out_path.resolve()}")

    # Send email if requested
    if args.send:
        print(f"📧 Sending email via {SMTP_HOST}:{SMTP_PORT} ...")
        send_email(html, args.report_file)


if __name__ == "__main__":
    main()
