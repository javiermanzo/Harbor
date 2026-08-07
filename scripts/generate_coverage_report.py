#!/usr/bin/env python3
import os
import subprocess
import sys


def parse_lcov(file_path):
    """Parses an lcov.info file and returns a map: file_path -> {'lh': int, 'lf': int, 'uncovered': [int]}"""
    coverage = {}
    if not os.path.exists(file_path):
        return coverage

    current_file = None
    lh = 0
    lf = 0
    uncovered_lines = []

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
                uncovered_lines = []
            elif line.startswith("LF:"):
                lf = int(line[3:])
            elif line.startswith("LH:"):
                lh = int(line[3:])
            elif line.startswith("DA:"):
                parts = line[3:].split(",")
                if len(parts) >= 2:
                    line_num = int(parts[0])
                    count = int(parts[1])
                    if count == 0:
                        uncovered_lines.append(line_num)
            elif line == "end_of_record":
                if current_file and current_file.startswith("Sources/"):
                    coverage[current_file] = {
                        "lh": lh,
                        "lf": lf,
                        "uncovered": sorted(uncovered_lines)
                    }
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


def format_line_ranges_with_links(lines, repo_slug, head_sha, file_path):
    """Formats list of uncovered line numbers into GitHub markdown links."""
    if not lines:
        return "-"

    ranges = []
    start = lines[0]
    prev = lines[0]

    for num in lines[1:]:
        if num == prev + 1:
            prev = num
        else:
            ranges.append((start, prev))
            start = num
            prev = num
    ranges.append((start, prev))

    links = []
    for s, e in ranges:
        if s == e:
            link_text = str(s)
            url = f"https://github.com/{repo_slug}/blob/{head_sha}/{file_path}#L{s}"
        else:
            link_text = f"{s}-{e}"
            url = f"https://github.com/{repo_slug}/blob/{head_sha}/{file_path}#L{s}-L{e}"
        links.append(f"[{link_text}]({url})")

    return ", ".join(links)


def main():
    pr_lcov_path = sys.argv[1] if len(sys.argv) > 1 else "./lcov.info"
    base_lcov_path = sys.argv[2] if len(sys.argv) > 2 else "./base-coverage/lcov.info"
    output_path = sys.argv[3] if len(sys.argv) > 3 else "./coverage_comment.md"
    base_ref = os.environ.get("GITHUB_BASE_REF", "release/4.0.0")
    repo_slug = os.environ.get("GITHUB_REPOSITORY", "javiermanzo/Harbor")
    head_sha = os.environ.get("PR_HEAD_SHA", os.environ.get("GITHUB_SHA", "main"))

    pr_cov = parse_lcov(pr_lcov_path)
    base_cov = parse_lcov(base_lcov_path)

    pr_lh = sum(data["lh"] for data in pr_cov.values())
    pr_lf = sum(data["lf"] for data in pr_cov.values())
    pr_overall = (pr_lh / pr_lf * 100) if pr_lf > 0 else 0.0

    base_lh = sum(data["lh"] for data in base_cov.values())
    base_lf = sum(data["lf"] for data in base_cov.values())
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
        pr_data = pr_cov.get(f, {"lh": 0, "lf": 0, "uncovered": []})
        p_lh, p_lf = pr_data["lh"], pr_data["lf"]
        p_pct = (p_lh / p_lf * 100) if p_lf > 0 else None

        base_data = base_cov.get(f, {"lh": 0, "lf": 0, "uncovered": []})
        b_lh, b_lf = base_data["lh"], base_data["lf"]
        b_pct = (b_lh / b_lf * 100) if (has_base and b_lf > 0) else None

        if p_pct is not None and b_pct is not None:
            diff = p_pct - b_pct
            if abs(diff) <= 0.001:
                continue
            var_str = format_variation(diff)
        elif p_pct is not None and b_pct is None:
            var_str = f"New File ({format_percentage(p_pct)}) 🟢"
        elif p_pct is None and b_pct is not None:
            var_str = "Deleted 🔴"
        else:
            continue

        pr_uncovered = set(pr_data["uncovered"])
        base_uncovered = set(base_data["uncovered"]) if has_base else set()

        # Extract only lines uncovered in PR that were NOT uncovered in base branch
        pr_affected_uncovered = sorted(list(pr_uncovered - base_uncovered))

        uncovered_str = format_line_ranges_with_links(pr_affected_uncovered, repo_slug, head_sha, f)
        relevant_files_with_changes.append((f, b_pct, p_pct, var_str, uncovered_str))

    md.append("<details>")
    md.append("<summary><b>Coverage Report for Changed Files</b></summary>")
    md.append("")

    if relevant_files_with_changes:
        md.append("| File | Base Branch | PR Branch | Variation | PR Uncovered Lines |")
        md.append("| :--- | :---: | :---: | :---: | :---: |")
        for f, b_pct, p_pct, var_str, unc_str in relevant_files_with_changes:
            b_str = format_percentage(b_pct)
            p_str = format_percentage(p_pct)
            md.append(f"| `{f}` | {b_str} | {p_str} | {var_str} | {unc_str} |")
    else:
        md.append("No coverage variations in changed files.")

    md.append("")
    md.append("</details>")

    report_text = "\n".join(md)

    with open(output_path, "w", encoding="utf-8") as out_f:
        out_f.write(report_text)

    print(report_text)


if __name__ == "__main__":
    main()
