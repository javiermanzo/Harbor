#!/usr/bin/env python3
import os
import subprocess
import sys


def parse_lcov(file_path):
    """Parses an lcov.info file and returns a map of relative file path -> (lines_hit, lines_found)."""
    coverage = {}
    if not os.path.exists(file_path):
        return coverage

    current_file = None
    lh = 0
    lf = 0

    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                current_file = line[3:]
                if "Sources/" in current_file:
                    idx = current_file.find("Sources/")
                    current_file = current_file[idx:]
                lh = 0
                lf = 0
            elif line.startswith("LF:"):
                lf = int(line[3:])
            elif line.startswith("LH:"):
                lh = int(line[3:])
            elif line == "end_of_record":
                if current_file and current_file.startswith("Sources/"):
                    coverage[current_file] = (lh, lf)
                current_file = None

    return coverage


def get_changed_files(base_ref):
    """Retrieves list of changed Swift files in Sources/ for the current PR."""
    try:
        cmd = ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"]
        out = subprocess.check_output(cmd, text=True)
        files = [
            line.strip()
            for line in out.splitlines()
            if line.strip().startswith("Sources/") and line.strip().endswith(".swift")
        ]
        return files
    except Exception:
        return []


def format_percentage(pct):
    if pct is None:
        return "N/A"
    return f"{pct:.2f}%"


def format_variation(diff):
    if diff > 0.001:
        return f"+{diff:.2f}% 🟢"
    elif diff < -0.001:
        return f"{diff:.2f}% 🔴"
    else:
        return "0.00% ⚪"


def main():
    pr_lcov_path = sys.argv[1] if len(sys.argv) > 1 else "./lcov.info"
    base_lcov_path = sys.argv[2] if len(sys.argv) > 2 else "./base-coverage/lcov.info"
    output_path = sys.argv[3] if len(sys.argv) > 3 else "./coverage_comment.md"
    base_ref = os.environ.get("GITHUB_BASE_REF", "release/4.0.0")

    pr_cov = parse_lcov(pr_lcov_path)
    base_cov = parse_lcov(base_lcov_path)

    pr_lh = sum(lh for lh, lf in pr_cov.values())
    pr_lf = sum(lf for lh, lf in pr_cov.values())
    pr_overall = (pr_lh / pr_lf * 100) if pr_lf > 0 else 0.0

    base_lh = sum(lh for lh, lf in base_cov.values())
    base_lf = sum(lf for lh, lf in base_cov.values())
    has_base = base_lf > 0
    base_overall = (base_lh / base_lf * 100) if has_base else 0.0

    overall_diff = pr_overall - base_overall if has_base else 0.0

    md = ["## 📊 Line Coverage Report", ""]
    md.append(f"- **Overall Line Coverage**: **{format_percentage(pr_overall)}** ({pr_lh}/{pr_lf} lines)")
    if has_base:
        md.append(f"- **Base Branch Coverage**: **{format_percentage(base_overall)}** ({base_lh}/{base_lf} lines)")
        md.append(f"- **Overall Variation**: **{format_variation(overall_diff)}**")

    md.append("")

    changed_files = get_changed_files(base_ref)

    relevant_files_with_changes = []

    for f in sorted(changed_files):
        p_lh, p_lf = pr_cov.get(f, (0, 0))
        p_pct = (p_lh / p_lf * 100) if p_lf > 0 else None

        b_lh, b_lf = base_cov.get(f, (0, 0))
        b_pct = (b_lh / b_lf * 100) if (has_base and b_lf > 0) else None

        if p_pct is not None and b_pct is not None:
            diff = p_pct - b_pct
            if abs(diff) <= 0.001:
                # Skip files without coverage variation!
                continue
            var_str = format_variation(diff)
        elif p_pct is not None and b_pct is None:
            var_str = f"New File ({format_percentage(p_pct)}) 🟢"
        elif p_pct is None and b_pct is not None:
            var_str = "Deleted 🔴"
        else:
            continue

        relevant_files_with_changes.append((f, b_pct, p_pct, var_str))

    md.append("<details><summary><b>Coverage Report for Changed Files</b></summary>")
    md.append("<br/>")

    if relevant_files_with_changes:
        md.append("| File | Base Branch | PR Branch | Variation |")
        md.append("| :--- | :---: | :---: | :---: |")
        for f, b_pct, p_pct, var_str in relevant_files_with_changes:
            b_str = format_percentage(b_pct)
            p_str = format_percentage(p_pct)
            md.append(f"| `{f}` | {b_str} | {p_str} | {var_str} |")
    else:
        md.append("No coverage variations in changed files.")

    md.append("</details>")

    report_text = "\n".join(md)

    with open(output_path, "w", encoding="utf-8") as out_f:
        out_f.write(report_text)

    print(report_text)


if __name__ == "__main__":
    main()
