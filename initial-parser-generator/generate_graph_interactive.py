import html
import json
import webbrowser
from pathlib import Path
from typing import Any

# Assuming these are defined in your data_structures.py
from data_structures import RightHandSide, VariableSymbol


def generate_graph(
    graphs_dir: Path,
    rules: dict[bytes, set[RightHandSide]],
    filename: str = "cfg_selectable.html",
    start_symbol: bytes | None = None,
) -> None:
    graph_path = (graphs_dir / filename).absolute()
    css_path = graph_path.with_suffix(".css")

    if not rules:
        print("Error: The rules dictionary is empty.")
        return

    def b2s(b: bytes) -> str:
        try:
            return b.decode("utf-8")
        except UnicodeDecodeError:
            return b.decode("latin1")

    js_rules: dict[str, list[list[dict[str, Any]]]] = {}

    for lhs, rhss in rules.items():
        lhs_s = b2s(lhs)
        js_rules[lhs_s] = []
        for rhs in rhss:
            row = []
            for sym in rhs.symbols:
                row.append(
                    {
                        "id": b2s(sym.id),
                        "is_var": isinstance(sym, VariableSymbol),
                    }
                )
            js_rules[lhs_s].append(row)

    rules_json = json.dumps(js_rules, ensure_ascii=False).replace("</", "<\\/")

    if start_symbol is not None:
        start_var = b2s(start_symbol)
    else:
        start_var = b2s(next(iter(rules.keys())))

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="{css_path}">
<title>CFG Selector</title>
</head>

<body>
    <div id="graph-panel">
        <h2>CFG Interactive Graph</h2>
        <div id="root"></div>
    </div>
    
    <div id="result-panel">
        <h2>Generated Text</h2>
        <div id="result-content"></div>
    </div>

<script>
const RULES = {rules_json};

function escapeHtml(unsafe) {{
    return (unsafe || "").toString()
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}}

// Recursively build the generated string from the current table states
function traverseTable(table) {{
    // If a specific row is chosen/collapsed, traverse its direct children
    if (table.chosenRow) {{
        let html = "";
        
        // Use .children to only iterate over the direct cells of THIS row, 
        // avoiding nested cells inside unselected child tables.
        Array.from(table.chosenRow.children).forEach(cell => {{
            if (cell.classList.contains("lead") || cell.classList.contains("pad")) return;
            
            if (cell.classList.contains("symbol-terminal")) {{
                html += `<span class="gen-terminal">${{escapeHtml(cell.dataset.value)}}</span>`;
            }} else if (cell.classList.contains("cell-variable")) {{
                const childTable = cell.querySelector("table");
                if (childTable) {{
                    html += traverseTable(childTable);
                }}
            }}
        }});
        return html;
    }} else {{
        // Table is fully expanded or collapsed with NO row selected -> Unresolved
        return `<span class="gen-variable">$${{escapeHtml(table.dataset.varName)}}</span>`;
    }}
}}

function updateGeneratedText() {{
    const rootTable = document.querySelector("#root > table");
    if (!rootTable) return;
    
    const resultHtml = traverseTable(rootTable);
    const resultContainer = document.getElementById("result-content");
    
    if (!resultHtml) {{
        resultContainer.innerHTML = `<span style="color: #94a3b8; font-style: italic;">(Empty)</span>`;
    }} else {{
        resultContainer.innerHTML = resultHtml;
    }}
}}

function createVariableTable(name, isRoot = false) {{
    const table = document.createElement("table");
    table.dataset.varName = name; 
    table.chosenRow = null; // Direct JS property to track selection state cleanly

    const thead = document.createElement("thead");
    const tbody = document.createElement("tbody");

    const hRow = document.createElement("tr");
    const th = document.createElement("th");
    th.textContent = name;

    hRow.appendChild(th);
    thead.appendChild(hRow);
    table.appendChild(thead);
    table.appendChild(tbody);

    let populated = false;

    function showHeaderCollapse() {{
        clearRowCollapse();
        thead.classList.remove("hidden");
        tbody.classList.add("hidden");
        updateGeneratedText();
    }}

    function showExpanded() {{
        clearRowCollapse();
        thead.classList.remove("hidden");
        tbody.classList.remove("hidden");
        updateGeneratedText();
    }}

    function clearRowCollapse() {{
        thead.classList.remove("hidden");
        Array.from(tbody.children).forEach(tr => tr.classList.remove("hidden"));
        
        if (table.chosenRow) {{
            table.chosenRow.querySelector(".lead").textContent = "▶";
            table.chosenRow = null;
        }}
    }}

    function showRowCollapse(row) {{
        if (table.chosenRow === row) {{
            showExpanded();
            return;
        }}

        clearRowCollapse();
        table.chosenRow = row;

        thead.classList.add("hidden");
        Array.from(tbody.children).forEach(tr => {{
            if (tr !== row) tr.classList.add("hidden");
        }});

        row.querySelector(".lead").textContent = name;
        updateGeneratedText();
    }}

    function renderRows() {{
        const rhss = RULES[name] || [];
        let maxCols = 1;
        rhss.forEach(r => maxCols = Math.max(maxCols, r.length + 1));
        th.colSpan = maxCols;

        rhss.forEach((rhs) => {{
            const tr = document.createElement("tr");

            const lead = document.createElement("td");
            lead.className = "lead";
            lead.textContent = "▶";
            tr.appendChild(lead);

            lead.onclick = (e) => {{
                e.stopPropagation();
                showRowCollapse(tr);
            }};

            rhs.forEach(sym => {{
                const td = document.createElement("td");

                if (sym.is_var) {{
                    td.className = "cell-variable";
                    td.appendChild(createVariableTable(sym.id));
                }} else {{
                    td.textContent = "'" + sym.id + "'";
                    td.className = "symbol-terminal";
                    td.dataset.value = sym.id;
                }}

                tr.appendChild(td);
            }});

            if (rhs.length + 1 < maxCols) {{
                const pad = document.createElement("td");
                pad.className = "pad";
                pad.colSpan = maxCols - rhs.length - 1;
                tr.appendChild(pad);
            }}

            tbody.appendChild(tr);
        }});
    }}

    function expandIfNeeded() {{
        if (!populated) {{
            renderRows();
            populated = true;
        }}
    }}

    th.onclick = (e) => {{
        e.stopPropagation();
        expandIfNeeded();
        
        if (tbody.classList.contains("hidden")) {{
            showExpanded();
        }} else {{
            showHeaderCollapse();
        }}
    }};

    if (!isRoot) {{
        tbody.classList.add("hidden");
    }} else {{
        renderRows();
        populated = true;
    }}

    return table;
}}

window.onload = () => {{
    const rootDiv = document.getElementById("root");
    rootDiv.appendChild(createVariableTable("{html.escape(start_var)}", true));
    
    updateGeneratedText();
}};
</script>

</body>
</html>"""

    graphs_dir.mkdir(exist_ok=True, parents=True)
    with graph_path.open("w", encoding="utf-8") as f:
        f.write(html_content)

    with css_path.open("w", encoding="utf-8") as f:
        f.write("""\
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: #f0f4f8;
    color: #334155;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    height: 100vh;
    box-sizing: border-box;
}

#graph-panel {
    flex: 1;
    overflow: auto;
    padding: 30px;
}

#result-panel {
    flex: 0 0 auto;
    background: white;
    padding: 20px 30px;
    box-shadow: 0 -4px 15px rgba(0,0,0,0.05);
    border-top: 4px solid #3b82f6;
    z-index: 10;
}

h2 {
    margin-top: 0;
    color: #0f172a;
    font-size: 1.25rem;
}

table {
    border-collapse: collapse;
    margin: 4px;
    display: inline-table;
    vertical-align: top;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.08);
    boder-radius: 6px;
    overflow: hidden;
}

td, th {
    border: 1px solid #cbd5e1;
    padding: 8px 14px;
    text-align: center;
}

th {
    background: #e2e8f0;
    cursor: pointer;
    user-select: none;
    font-style: italic;
    font-weight: 600;
    color: #1e293b;
    transition: background 0.2s, color 0.2s;
}

th:hover {
    background: #e11d48;
    color: white;
}

.hidden {
    display: none !important;
}

.lead {
    cursor: pointer;
    font-weight: bold;
    color: #64748b;
    width: 1px;
    white-space: nowrap;
    transition: color 0.2s;
    background: #f8fafc;
}

.lead:hover {
    color: #e11d48;
}

.cell-variable {
    padding: 0;
    background: #f8fafc;
}

.symbol-terminal {
    font-family: 'Courier New', Courier, monospace;
    font-weight: bold;
    color: #0f172a;
    white-space: nowrap;
}

#result-content {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    font-family: 'Courier New', Courier, monospace;
    font-size: 1.1rem;
    align-items: center;
    min-height 32px;
}

.gen-terminal {
    color: #0f172a;
    background: #f1f5f9;
    padding: 4px 10px;
    border-radius: 4px;
    border: 1px solid #cbd5e1;
    box-shadow: 0 1px 2px rgba(0,0,0,0.05);
}

.gen-variable {
    color: white;
    background: #ef4444;
    padding: 4px 10px;
    border-radius: 4px;
    font-weight: bold;
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    box-shadow: 0 2px 5px rgba(239, 68, 68, 0.4);
    letter-spacing: 0.5px;
}\
""")

    webbrowser.open(f"file://{graph_path}")
