#!/usr/bin/env python3
"""
parse_fpv_report.py
--------------------
Parses a raw FPV (Formal Property Verification) report file.
Extracts per-module, per-customer proven counts and coverage percentages.

Supported modules:
  - fuse_distr_fsm
  - fuse_mem_if_arb

Output: List of dicts per module, ready for HTML generation.
"""

import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

class ModuleResult:
    """Holds parsed results for one FPV module."""

    def __init__(self, name: str):
        self.name = name
        self.rows: list[dict] = []  # [{cust, proven, total, covered_pct}]

    def add_row(self, cust: str, proven: str, covered: str):
        # Parse proven count e.g. "12/15"
        proven_parts = proven.strip().split("/")
        if len(proven_parts) == 2:
            proven_count = int(proven_parts[0].strip())
            total_count  = int(proven_parts[1].strip())
        else:
            proven_count = int(proven_parts[0].strip())
            total_count  = None

        # Parse covered percentage e.g. "80%"
        covered_clean = covered.strip().rstrip("%")
        covered_pct   = float(covered_clean) if covered_clean else 0.0

        self.rows.append({
            "cust":        cust.strip(),
            "proven":      proven_count,
            "total":       total_count,
            "covered_pct": covered_pct,
        })

    @property
    def is_empty(self) -> bool:
        return len(self.rows) == 0

    @property
    def overall_status(self) -> str:
        if self.is_empty:
            return "EMPTY"
        if all(r["covered_pct"] >= 100.0 for r in self.rows):
            return "PASS"
        if any(r["covered_pct"] > 0.0 for r in self.rows):
            return "PARTIAL"
        return "FAIL"


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

def parse_fpv_report(report_path: str) -> list[ModuleResult]:
    """
    Parse the raw FPV report file and return a list of ModuleResult objects.

    Expected format:
        FPV summary on <module_name>
        +-----------------------
        | cust      | proven  | covered |
        +-----------------------
        | cust_A    | 12/15   | 80%     |
        | cust_B    |  0/15   |  0%     |
        +-----------------------
    """
    path = Path(report_path)
    if not path.exists():
        raise FileNotFoundError(f"Report file not found: {report_path}")

    results: list[ModuleResult] = []
    current_module: ModuleResult | None = None
    in_data_rows = False  # True after we pass the header separator

    module_pattern  = re.compile(r"^FPV summary on\s+(\S+)", re.IGNORECASE)
    separator_pattern = re.compile(r"^\+[-+]+\+?")
    data_row_pattern  = re.compile(
        r"^\|\s*(?P<cust>[^|]+)\|\s*(?P<proven>[^|]+)\|\s*(?P<covered>[^|]+)\|"
    )
    header_pattern = re.compile(r"cust", re.IGNORECASE)

    with path.open("r") as fh:
        for line in fh:
            line = line.rstrip("\n")

            # Detect new module block
            m = module_pattern.match(line.strip())
            if m:
                current_module = ModuleResult(m.group(1))
                results.append(current_module)
                in_data_rows = False
                continue

            if current_module is None:
                continue

            # Separator line
            if separator_pattern.match(line.strip()):
                continue

            # Header row — skip it
            if header_pattern.search(line):
                in_data_rows = True
                continue

            # Data rows
            if in_data_rows:
                dm = data_row_pattern.match(line.strip())
                if dm:
                    current_module.add_row(
                        dm.group("cust"),
                        dm.group("proven"),
                        dm.group("covered"),
                    )

    return results


# ---------------------------------------------------------------------------
# CLI — quick human-readable console print
# ---------------------------------------------------------------------------

STATUS_ICON = {
    "PASS":    "✅ PASS",
    "PARTIAL": "⚠️  PARTIAL",
    "FAIL":    "❌ FAIL",
    "EMPTY":   "⬜ EMPTY",
}


def print_results(results: list[ModuleResult]) -> None:
    col_w = [20, 10, 10, 12]
    sep   = "+" + "+".join("-" * w for w in col_w) + "+"
    hdr   = "| {:<18} | {:>8} | {:>8} | {:>10} |".format(
        "Customer", "Proven", "Total", "Covered %"
    )

    for mod in results:
        print(f"\nMODULE: {mod.name}")
        print(sep)
        print(hdr)
        print(sep)
        if mod.is_empty:
            print("| {:^{w}} |".format("(no data)", w=sum(col_w) + len(col_w) - 1))
        else:
            for row in mod.rows:
                total = str(row["total"]) if row["total"] is not None else "?"
                print("| {:<18} | {:>8} | {:>8} | {:>9.1f}% |".format(
                    row["cust"], row["proven"], total, row["covered_pct"]
                ))
        print(sep)
        print(f"Status: {STATUS_ICON[mod.overall_status]}")

    print("\n" + "=" * 60)
    passing = sum(1 for r in results if r.overall_status == "PASS")
    print(f"OVERALL: {passing}/{len(results)} modules passing")
    print("=" * 60)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse_fpv_report.py <report_file>")
        sys.exit(1)

    parsed = parse_fpv_report(sys.argv[1])
    print_results(parsed)
