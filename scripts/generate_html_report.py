#!/usr/bin/env python3
import json
import os
import subprocess
import sys


def parse_lcov(file_path):
    """Parses lcov.info and returns map: file_path -> {lh, lf, lines: {line_num: count}}."""
    coverage = {}
    if not os.path.exists(file_path):
        return coverage

    current_file = None
    lh = 0
    lf = 0
    lines_map = {}

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
                lines_map = {}
            elif line.startswith("LF:"):
                lf = int(line[3:])
            elif line.startswith("LH:"):
                lh = int(line[3:])
            elif line.startswith("DA:"):
                parts = line[3:].split(",")
                if len(parts) >= 2:
                    line_num = int(parts[0])
                    count = int(parts[1])
                    lines_map[line_num] = count
            elif line == "end_of_record":
                if current_file and current_file.startswith("Sources/"):
                    coverage[current_file] = {
                        "lh": lh,
                        "lf": lf,
                        "lines": lines_map,
                    }
                current_file = None

    return coverage


def get_changed_files(base_ref):
    """Retrieves list of changed Swift files in Sources/ for current PR."""
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


def read_source_file(file_path):
    """Reads source code lines of a file."""
    if not os.path.exists(file_path):
        return []
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return f.readlines()
    except Exception:
        return []


def main():
    pr_lcov_path = sys.argv[1] if len(sys.argv) > 1 else "./lcov.info"
    base_lcov_path = sys.argv[2] if len(sys.argv) > 2 else "./base-coverage/lcov.info"
    output_dir = sys.argv[3] if len(sys.argv) > 3 else "./coverage_html"
    base_ref = os.environ.get("GITHUB_BASE_REF", "release/4.0.0")

    pr_cov = parse_lcov(pr_lcov_path)
    base_cov = parse_lcov(base_lcov_path)

    changed_files = get_changed_files(base_ref)
    if not changed_files:
        changed_files = sorted(list(set(pr_cov.keys()).union(set(base_cov.keys()))))

    pr_lh = sum(d["lh"] for d in pr_cov.values())
    pr_lf = sum(d["lf"] for d in pr_cov.values())
    pr_overall = (pr_lh / pr_lf * 100) if pr_lf > 0 else 0.0

    base_lh = sum(d["lh"] for d in base_cov.values())
    base_lf = sum(d["lf"] for d in base_cov.values())
    has_base = base_lf > 0
    base_overall = (base_lh / base_lf * 100) if has_base else 0.0

    overall_diff = pr_overall - base_overall if has_base else 0.0

    files_data = []
    for f in sorted(changed_files):
        p_data = pr_cov.get(f, {"lh": 0, "lf": 0, "lines": {}})
        b_data = base_cov.get(f, {"lh": 0, "lf": 0, "lines": {}})

        p_pct = (p_data["lh"] / p_data["lf"] * 100) if p_data["lf"] > 0 else 0.0
        b_pct = (b_data["lh"] / b_data["lf"] * 100) if b_data["lf"] > 0 else 0.0
        diff = p_pct - b_pct if has_base else 0.0

        source_lines = read_source_file(f)
        annotated_lines = []

        for idx, text in enumerate(source_lines, 1):
            count = p_data["lines"].get(idx, None)
            annotated_lines.append({
                "number": idx,
                "text": text.rstrip("\r\n"),
                "count": count,
            })

        uncovered_count = sum(1 for l in annotated_lines if l["count"] == 0)

        files_data.append({
            "path": f,
            "filename": os.path.basename(f),
            "pr_pct": round(p_pct, 2),
            "base_pct": round(b_pct, 2),
            "diff": round(diff, 2),
            "lh": p_data["lh"],
            "lf": p_data["lf"],
            "uncovered_count": uncovered_count,
            "lines": annotated_lines,
        })

    os.makedirs(output_dir, exist_ok=True)

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Harbor PR Coverage Report</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {{
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --border-color: #30363d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --text-heading: #f0f6fc;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-red: #f85149;
            --accent-yellow: #d29922;
            --covered-bg: rgba(46, 160, 67, 0.15);
            --covered-border: #2ea043;
            --uncovered-bg: rgba(248, 81, 73, 0.15);
            --uncovered-border: #f85149;
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}

        body {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.5;
            padding: 2rem;
            max-width: 1400px;
            margin: 0 auto;
        }}

        header {{
            margin-bottom: 2rem;
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 1.5rem;
        }}

        h1 {{
            font-size: 1.75rem;
            color: var(--text-heading);
            font-weight: 700;
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }}

        .subtitle {{
            color: var(--text-secondary);
            font-size: 0.95rem;
        }}

        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }}

        .stat-card {{
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 1.25rem;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
        }}

        .stat-label {{
            font-size: 0.85rem;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            font-weight: 600;
            margin-bottom: 0.5rem;
        }}

        .stat-value {{
            font-size: 2rem;
            font-weight: 700;
            color: var(--text-heading);
        }}

        .badge {{
            display: inline-flex;
            align-items: center;
            padding: 0.25rem 0.6rem;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
        }}

        .badge-positive {{
            background: rgba(63, 185, 80, 0.2);
            color: #56d364;
            border: 1px solid rgba(63, 185, 80, 0.4);
        }}

        .badge-negative {{
            background: rgba(248, 81, 73, 0.2);
            color: #ff7b72;
            border: 1px solid rgba(248, 81, 73, 0.4);
        }}

        .badge-neutral {{
            background: rgba(139, 148, 158, 0.2);
            color: #8b949e;
            border: 1px solid rgba(139, 148, 158, 0.4);
        }}

        .section-title {{
            font-size: 1.25rem;
            color: var(--text-heading);
            font-weight: 600;
            margin-bottom: 1rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }}

        .files-table-container {{
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 2rem;
        }}

        table {{
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }}

        th {{
            background: var(--bg-tertiary);
            color: var(--text-heading);
            padding: 0.85rem 1rem;
            font-size: 0.85rem;
            font-weight: 600;
            border-bottom: 1px solid var(--border-color);
        }}

        td {{
            padding: 0.85rem 1rem;
            border-bottom: 1px solid var(--border-color);
            font-size: 0.9rem;
        }}

        tr:last-child td {{
            border-bottom: none;
        }}

        tr:hover td {{
            background: rgba(255, 255, 255, 0.02);
        }}

        .file-name-btn {{
            background: none;
            border: none;
            color: var(--accent-blue);
            font-family: inherit;
            font-size: 0.9rem;
            font-weight: 600;
            cursor: pointer;
            text-align: left;
            text-decoration: none;
        }}

        .file-name-btn:hover {{
            text-decoration: underline;
        }}

        /* Code Viewer Modal / Inspector */
        .inspector {{
            display: none;
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            margin-top: 2rem;
            overflow: hidden;
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
        }}

        .inspector.active {{
            display: block;
        }}

        .inspector-header {{
            background: var(--bg-tertiary);
            padding: 1rem;
            border-bottom: 1px solid var(--border-color);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }}

        .inspector-title {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.95rem;
            color: var(--accent-blue);
            font-weight: 600;
        }}

        .inspector-actions {{
            display: flex;
            gap: 0.5rem;
        }}

        .btn {{
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 0.4rem 0.8rem;
            border-radius: 6px;
            font-size: 0.8rem;
            font-weight: 500;
            cursor: pointer;
        }}

        .btn:hover {{
            background: var(--border-color);
        }}

        .btn-active {{
            background: var(--accent-blue);
            color: #fff;
            border-color: var(--accent-blue);
        }}

        .code-container {{
            overflow-x: auto;
            max-height: 700px;
            overflow-y: auto;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.85rem;
        }}

        .code-line {{
            display: flex;
            align-items: stretch;
            min-width: 100%;
        }}

        .line-number {{
            width: 50px;
            padding: 0.2rem 0.5rem;
            text-align: right;
            color: var(--text-secondary);
            background: rgba(0,0,0,0.1);
            user-select: none;
            border-right: 1px solid var(--border-color);
            flex-shrink: 0;
        }}

        .line-hits {{
            width: 45px;
            padding: 0.2rem 0.5rem;
            text-align: right;
            font-size: 0.75rem;
            color: var(--text-secondary);
            user-select: none;
            border-right: 1px solid var(--border-color);
            flex-shrink: 0;
        }}

        .line-text {{
            padding: 0.2rem 0.75rem;
            white-space: pre;
            flex-grow: 1;
        }}

        .line-covered {{
            background-color: var(--covered-bg);
        }}

        .line-covered .line-hits {{
            color: var(--accent-green);
            font-weight: bold;
        }}

        .line-uncovered {{
            background-color: var(--uncovered-bg);
        }}

        .line-uncovered .line-hits {{
            color: var(--accent-red);
            font-weight: bold;
        }}

        .filter-uncovered .line-covered, .filter-uncovered .line-neutral {{
            display: none;
        }}
    </style>
</head>
<body>

    <header>
        <h1>📊 Harbor PR Code Coverage</h1>
        <p class="subtitle">Detailed code coverage report specifically for changed files in this Pull Request</p>
    </header>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-label">PR Line Coverage</div>
            <div class="stat-value">{pr_overall:.2f}%</div>
        </div>
        <div class="stat-card">
            <div class="stat-label">Base Line Coverage</div>
            <div class="stat-value">{base_overall:.2f}%</div>
        </div>
        <div class="stat-card">
            <div class="stat-label">PR Coverage Variation</div>
            <div class="stat-value" style="display: flex; align-items: center; gap: 0.5rem;">
                {overall_diff:+.2f}%
                <span class="badge {'badge-positive' if overall_diff > 0.001 else ('badge-negative' if overall_diff < -0.001 else 'badge-neutral')}">
                    {'🟢 Increase' if overall_diff > 0.001 else ('🔴 Decrease' if overall_diff < -0.001 else '⚪ Unchanged')}
                </span>
            </div>
        </div>
    </div>

    <div class="section-title">
        <span>📁 Changed Files in PR ({len(files_data)})</span>
    </div>

    <div class="files-table-container">
        <table>
            <thead>
                <tr>
                    <th>File Name</th>
                    <th>Base Coverage</th>
                    <th>PR Coverage</th>
                    <th>Variation</th>
                    <th>Uncovered Lines</th>
                    <th>Action</th>
                </tr>
            </thead>
            <tbody>
"""

    for idx, f in enumerate(files_data):
        diff = f["diff"]
        badge_class = "badge-positive" if diff > 0.001 else ("badge-negative" if diff < -0.001 else "badge-neutral")
        diff_str = f"{diff:+.2f}%" if abs(diff) > 0.001 else "0.00%"
        
        html_content += f"""
                <tr>
                    <td>
                        <button class="file-name-btn" onclick="inspectFile({idx})">`{f["path"]}`</button>
                    </td>
                    <td>{f["base_pct"]:.2f}%</td>
                    <td><strong>{f["pr_pct"]:.2f}%</strong></td>
                    <td><span class="badge {badge_class}">{diff_str}</span></td>
                    <td><span style="color: {'var(--accent-red)' if f['uncovered_count'] > 0 else 'var(--text-secondary)'}; font-weight: 600;">{f['uncovered_count']} lines</span></td>
                    <td>
                        <button class="btn" onclick="inspectFile({idx})">Inspect Code</button>
                    </td>
                </tr>
"""

    html_content += """
            </tbody>
        </table>
    </div>

    <div id="inspector" class="inspector">
        <div class="inspector-header">
            <div id="inspector-title" class="inspector-title">Select a file above to inspect coverage</div>
            <div class="inspector-actions">
                <button id="btn-all" class="btn btn-active" onclick="setFilter('all')">Show All Lines</button>
                <button id="btn-uncovered" class="btn" onclick="setFilter('uncovered')">Uncovered Only</button>
            </div>
        </div>
        <div id="code-container" class="code-container"></div>
    </div>

    <script>
        const filesData = """ + json.dumps(files_data) + """;
        let currentFileIdx = 0;
        let currentFilter = 'all';

        function inspectFile(index) {
            currentFileIdx = index;
            const file = filesData[index];
            document.getElementById('inspector-title').textContent = file.path + ' (' + file.pr_pct + '% covered)';
            
            const inspector = document.getElementById('inspector');
            inspector.classList.add('active');
            
            renderCode();
            inspector.scrollIntoView({ behavior: 'smooth' });
        }

        function setFilter(filter) {
            currentFilter = filter;
            document.getElementById('btn-all').classList.toggle('btn-active', filter === 'all');
            document.getElementById('btn-uncovered').classList.toggle('btn-active', filter === 'uncovered');
            renderCode();
        }

        function renderCode() {
            const file = filesData[currentFileIdx];
            const container = document.getElementById('code-container');
            container.innerHTML = '';
            
            if (currentFilter === 'uncovered') {
                container.classList.add('filter-uncovered');
            } else {
                container.classList.remove('filter-uncovered');
            }

            file.lines.forEach(line => {
                const lineDiv = document.createElement('div');
                let lineClass = 'line-neutral';
                let hitsText = '';

                if (line.count !== null) {
                    if (line.count > 0) {
                        lineClass = 'line-covered';
                        hitsText = line.count + 'x';
                    } else {
                        lineClass = 'line-uncovered';
                        hitsText = '0x';
                    }
                }

                lineDiv.className = 'code-line ' + lineClass;
                lineDiv.innerHTML = `
                    <div class="line-number">${line.number}</div>
                    <div class="line-hits">${hitsText}</div>
                    <div class="line-text">${escapeHtml(line.text)}</div>
                `;
                container.appendChild(lineDiv);
            });
        }

        function escapeHtml(text) {
            return text
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        }
    </script>
</body>
</html>
"""

    with open(os.path.join(output_dir, "index.html"), "w", encoding="utf-8") as out_f:
        out_f.write(html_content)

    print(f"Successfully generated modern PR HTML coverage report at {os.path.join(output_dir, 'index.html')}")

if __name__ == "__main__":
    main()
