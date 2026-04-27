import html
import json
import subprocess
import webbrowser
from pathlib import Path

from data_structures import RightHandSide, TerminalSymbol


def sanitize_text(text: str) -> str:
    """Escapes control characters and ensures the string is never empty for Graphviz."""
    sanitized = "".join(c if ord(c) >= 32 else f"\\x{ord(c):02x}" for c in text)
    return sanitized if sanitized.strip() else "&nbsp;"


def build_table_html(node_name: str, rules_dict: dict) -> str:
    safe_name = html.escape(sanitize_text(node_name))
    if node_name not in rules_dict:
        return f'<table class="rhs-table"><tr><th style="background: #c8e6c9;">{safe_name}</th></tr></table>'

    rhs_set = rules_dict[node_name]

    max_syms = max((len(rhs.symbols) for rhs in rhs_set), default=1)
    if max_syms == 0:
        max_syms = 1

    html_str = '<table class="rhs-table">'
    html_str += f'<tr><th colspan="{max_syms}">{safe_name}</th></tr>'

    for rhs in rhs_set:
        html_str += "<tr>"
        if not rhs.symbols:
            html_str += f'<td colspan="{max_syms}" class="empty">&epsilon;</td>'
        else:
            for i, sym in enumerate(rhs.symbols):
                colspan = ""
                if i == len(rhs.symbols) - 1 and len(rhs.symbols) < max_syms:
                    colspan = f' colspan="{max_syms - i}"'
                safe_sym = html.escape(sanitize_text(repr(sym)))
                html_str += f"<td{colspan}>{safe_sym}</td>"
        html_str += "</tr>"
    html_str += "</table>"
    return html_str


def build_dot_label(node_name: str, rules_dict: dict) -> str:
    """Generates a Graphviz HTML-like label that mirrors the dimensions of the real HTML table."""
    safe_name = html.escape(sanitize_text(node_name)).replace('"', "&quot;")
    if node_name not in rules_dict:
        return f'<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="6"><TR><TD BGCOLOR="#c8e6c9">{safe_name}</TD></TR></TABLE>>'

    rhs_set = rules_dict[node_name]

    max_syms = max((len(rhs.symbols) for rhs in rhs_set), default=1)
    if max_syms == 0:
        max_syms = 1

    # Graphviz requires strictly `<<` and `>>` without spaces for HTML-like labels
    label = '<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="6">'
    # Make sure we don't have empty <B></B> which causes Graphviz syntax errors
    label += (
        f'<TR><TD COLSPAN="{max_syms}" BGCOLOR="#bbdefb"><B>{safe_name}</B></TD></TR>'
    )

    for rhs in rhs_set:
        label += "<TR>"
        if not rhs.symbols:
            label += f'<TD COLSPAN="{max_syms}">ε</TD>'
        else:
            for i, sym in enumerate(rhs.symbols):
                colspan = ""
                if i == len(rhs.symbols) - 1 and len(rhs.symbols) < max_syms:
                    colspan = f' COLSPAN="{max_syms - i}"'
                safe_sym = html.escape(sanitize_text(repr(sym))).replace('"', "&quot;")
                label += f"<TD{colspan}>{safe_sym}</TD>"
        label += "</TR>"
    label += "</TABLE>>"
    return label


def parse_graphviz_path(pos_string: str, scale_x: float = 1.0) -> str:
    parts = pos_string.split(" ")
    points = []

    for p in parts:
        if p.startswith("e,") or p.startswith("s,"):
            continue
        coords = p.split(",")
        if len(coords) == 2:
            x = float(coords[0]) * scale_x
            y = -float(coords[1])
            points.append((x, y))

    if not points:
        return ""
    path_d = f"M {points[0][0]} {points[0][1]} "

    for i in range(1, len(points), 3):
        if i + 2 < len(points):
            path_d += f"C {points[i][0]} {points[i][1]}, {points[i + 1][0]} {points[i + 1][1]}, {points[i + 2][0]} {points[i + 2][1]} "
        else:
            for j in range(i, len(points)):
                path_d += f"L {points[j][0]} {points[j][1]} "

    return path_d.strip()


def generate_view_data(
    view_prefix: str,
    nodes_subset: dict,
    edges_subset: list,
    rules_dict: dict,
    node_to_id: dict,
):
    """Generates a Graphviz layout and SVG elements for a specific subset of the graph."""
    dot_lines = [
        "digraph G {",
        "  rankdir=LR;",
        "  nodesep=0.6;",
        "  ranksep=1.5;",
        '  node [fontname="sans-serif", fontsize=14];',
    ]

    for name in nodes_subset.keys():
        nid = node_to_id[name]
        dot_label = build_dot_label(name, rules_dict)
        dot_lines.append(f"  {nid} [shape=none, margin=0, label={dot_label}];")

    for u, v in edges_subset:
        dot_lines.append(f"  {node_to_id[u]} -> {node_to_id[v]};")

    dot_lines.append("}")
    dot_source = "\n".join(dot_lines)

    try:
        process = subprocess.run(
            ["dot", "-Tjson"],
            input=dot_source.encode("utf-8"),
            capture_output=True,
            check=True,
        )
        gv_data = json.loads(process.stdout.decode("utf-8"))
    except subprocess.CalledProcessError as e:
        print(f"Graphviz failed for view {view_prefix}:\n{e.stderr.decode('utf-8')}")
        return "", {"x": 0, "y": 0, "w": 800, "h": 600}, {}
    except Exception as e:
        print(f"Graphviz failed for view {view_prefix}:", e)
        return "", {"x": 0, "y": 0, "w": 800, "h": 600}, {}

    id_to_node = {v: k for k, v in node_to_id.items()}
    pos = {}

    for obj in gv_data.get("objects", []):
        nid = obj.get("name")
        if nid in id_to_node:
            p = obj.get("pos", "0,0").split(",")
            pos[id_to_node[nid]] = [float(p[0]), -float(p[1])]

    edge_paths = {}
    for obj in gv_data.get("edges", []):
        tail_idx = obj.get("tail")
        head_idx = obj.get("head")
        if tail_idx is not None and head_idx is not None:
            tail_name = gv_data["objects"][tail_idx]["name"]
            head_name = gv_data["objects"][head_idx]["name"]
            edge_paths[(tail_name, head_name)] = obj.get("pos", "")

    if pos:
        min_x = min(p[0] for p in pos.values())
        max_x = max(p[0] for p in pos.values())
        min_y = min(p[1] for p in pos.values())
        max_y = max(p[1] for p in pos.values())
    else:
        min_x, max_x, min_y, max_y = 0, 800, 0, 600

    pad = max((max_x - min_x) * 0.1, (max_y - min_y) * 0.1, 150)
    viewBox = {
        "x": min_x - pad,
        "y": min_y - pad,
        "w": (max_x - min_x) + 2 * pad,
        "h": (max_y - min_y) + 2 * pad,
    }

    topology = {
        node_to_id[name]: {
            "parents": [],
            "children": [],
            "x": pos[name][0],
            "y": pos[name][1],
        }
        for name in nodes_subset.keys()
    }

    svg_elements = []

    for u, v in edges_subset:
        u_id, v_id = node_to_id[u], node_to_id[v]
        topology[u_id]["children"].append(v_id)
        topology[v_id]["parents"].append(u_id)

        pos_str = edge_paths.get((u_id, v_id), "")
        edge_id = f"e-{view_prefix}-{u_id}-{v_id}"
        if pos_str:
            path_d = parse_graphviz_path(pos_str)
            svg_elements.append(
                f'<path id="{edge_id}" d="{path_d}" class="edge" fill="none" stroke="#888" stroke-width="2.5" vector-effect="non-scaling-stroke" marker-end="url(#arrowhead)" />'
            )
        else:
            x1, y1 = pos[u]
            x2, y2 = pos[v]
            svg_elements.append(
                f'<line id="{edge_id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="edge" stroke="#888" stroke-width="2.5" vector-effect="non-scaling-stroke" marker-end="url(#arrowhead)" />'
            )

    for n_name, n_info in nodes_subset.items():
        n_id = node_to_id[n_name]
        x, y = pos[n_name]
        label = html.escape(n_info["label"])
        color = "#34A853" if n_info["type"] == "terminal" else "#4285F4"
        est_width = len(label) * 9.5 + 12

        node_content = f"""
            <g class="simple-view">
                <circle cx="0" cy="0" r="8" fill="{color}" stroke="#fff" stroke-width="1.5" class="node-circle"/>
                <rect class="label-bg" x="{-est_width / 2}" y="14" width="{est_width}" height="24" rx="4" />
                <text x="0" y="31" font-family="sans-serif" fill="#111" text-anchor="middle" font-weight="bold" pointer-events="none">{label}</text>
            </g>
            <foreignObject class="detailed-view" x="-500" y="-500" width="1000" height="1000" style="pointer-events: none;">
                <div xmlns="http://www.w3.org/1999/xhtml" style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; pointer-events: none;">
                    {build_table_html(n_name, rules_dict)}
                </div>
            </foreignObject>
        """

        svg_elements.append(
            f'<g id="{view_prefix}-{n_id}" class="node" style="--x: {x}px; --y: {y}px;" '
            f'onmouseenter="highlightNode(\'{n_id}\')" onmouseleave="resetHighlight()" '
            f"onclick=\"switchView('{n_id}')\">"
            f"{node_content}"
            f"</g>"
        )

    return "\n".join(svg_elements), viewBox, topology


def generate_graph(graphs_dir: Path, rules: dict[bytes, set[RightHandSide]]) -> None:
    nodes = {}
    edges = []
    rules_dict = {}

    for lhs_bytes, rhs_set in rules.items():
        # Fallback to repr decoding if raw utf-8 throws
        try:
            lhs_name = lhs_bytes.decode("utf-8")
        except UnicodeDecodeError:
            lhs_name = repr(lhs_bytes)

        rules_dict[lhs_name] = rhs_set
        if lhs_name not in nodes:
            nodes[lhs_name] = {"label": sanitize_text(lhs_name), "type": "variable"}

        for rhs in rhs_set:
            for symbol in rhs.symbols:
                sym_name = repr(symbol)
                sym_type = (
                    "terminal" if isinstance(symbol, TerminalSymbol) else "variable"
                )
                if sym_name not in nodes:
                    nodes[sym_name] = {
                        "label": sanitize_text(sym_name),
                        "type": sym_type,
                    }
                edges.append((lhs_name, sym_name))

    edges = list(set(edges))
    node_to_id = {name: f"n{i}" for i, name in enumerate(nodes.keys())}

    # Generate GLOBAL View
    global_svg, global_vb, global_topo = generate_view_data(
        "global", nodes, edges, rules_dict, node_to_id
    )

    views_data = {"global": {"vb": global_vb, "topo": global_topo}}

    svg_layers = [f'<g id="view-global">{global_svg}</g>']

    # Generate LOCAL views for every single node
    for n_name, n_info in nodes.items():
        n_id = node_to_id[n_name]

        # Determine local neighborhood (node + parents + children)
        local_nodes = {n_name: n_info}
        local_edges = []
        for u, v in edges:
            if u == n_name or v == n_name:
                local_edges.append((u, v))
                if u not in local_nodes:
                    local_nodes[u] = nodes[u]
                if v not in local_nodes:
                    local_nodes[v] = nodes[v]

        l_svg, l_vb, l_topo = generate_view_data(
            f"local-{n_id}", local_nodes, local_edges, rules_dict, node_to_id
        )

        views_data[n_id] = {"vb": l_vb, "topo": l_topo}
        svg_layers.append(f'<g id="view-{n_id}" display="none">{l_svg}</g>')

    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>CFG Visualization</title>
    <style>
        :root {{ --zoom-scale: 1; }}
        body {{ margin: 0; padding: 0; overflow: hidden; background-color: #f8f9fa; font-family: sans-serif; }}
        svg {{ width: 100vw; height: 100vh; cursor: grab; transition: viewBox 0.3s cubic-bezier(0.25, 0.8, 0.25, 1); }}
        svg:active {{ cursor: grabbing; }}
        svg.panning {{ transition: none; }}
        
        .node {{ transform: translate(var(--x), var(--y)) scale(var(--zoom-scale)); transition: transform 0.2s; cursor: pointer; }}
        .node.show-detailed {{ z-index: 100; }}
        .node text {{ font-size: 16px; transition: opacity 0.2s; pointer-events: none; }}
        .label-bg {{ fill: rgba(255, 255, 255, 0.8); stroke: transparent; stroke-width: 1.5; transition: all 0.2s; }}
        .node:hover .label-bg {{ fill: rgba(255, 255, 255, 1); stroke: #333; }}
        .node:hover text {{ opacity: 1 !important; }}
        
        .hide-text .node .simple-view text {{ opacity: 0; }}
        .hide-text .node .simple-view .label-bg {{ opacity: 0; }}
        .hide-text .node:hover .simple-view .label-bg {{ opacity: 1; }} 
        .hide-text .node.show-label .simple-view text {{ opacity: 1 !important; }}
        .hide-text .node.show-label .simple-view .label-bg {{ opacity: 1 !important; }}
        
        .detailed-view {{ opacity: 0; transition: opacity 0.2s; }}
        .simple-view {{ opacity: 1; transition: opacity 0.2s; }}
        .node.show-detailed .detailed-view {{ opacity: 1; }}
        .node.show-detailed .simple-view {{ opacity: 0; }}
        
        .rhs-table {{ border-collapse: collapse; font-family: sans-serif; font-size: 14px; background: white; box-shadow: 0 4px 12px rgba(0,0,0,0.3); border-radius: 6px; overflow: hidden; pointer-events: auto; border: 2px solid #333; }}
        .rhs-table th {{ background: #bbdefb; border-bottom: 1px solid #333; padding: 6px; font-weight: bold; color: #111; }}
        .rhs-table td {{ border: 1px solid #ccc; padding: 6px; text-align: center; color: #111; }}
        .rhs-table td.empty {{ color: #888; font-style: italic; font-family: serif; }}
        
        .edge {{ transition: stroke 0.2s, opacity 0.2s; pointer-events: none; }}
        .node-circle {{ transition: fill 0.2s, stroke 0.2s, opacity 0.2s; }}
        .dimmed {{ opacity: 0.15 !important; }}
        
        .highlight-center .node-circle {{ fill: #FBBC05 !important; stroke: #333 !important; }}
        .highlight-child .node-circle {{ fill: #FF6D00 !important; }}
        .highlight-parent .node-circle {{ fill: #9C27B0 !important; }}
        .highlight-edge-child {{ stroke: #FF6D00 !important; opacity: 1 !important; stroke-width: 4 !important; marker-end: url(#arrowhead-highlighted) !important; }}
        .highlight-edge-parent {{ stroke: #9C27B0 !important; opacity: 1 !important; stroke-width: 4 !important; marker-end: url(#arrowhead-parent) !important; }}
        
        .ui-panel {{ position: absolute; top: 10px; left: 10px; z-index: 10; display: flex; flex-direction: column; gap: 10px; pointer-events: none; }}
        .legend {{ background: white; padding: 10px; border-radius: 5px; box-shadow: 0 1px 3px rgba(0,0,0,0.2); border: 1px solid #eee; }}
        
        #back-btn {{ display: none; background: #333; color: white; border: none; padding: 10px 15px; border-radius: 5px; cursor: pointer; font-size: 14px; pointer-events: auto; box-shadow: 0 2px 5px rgba(0,0,0,0.3); font-weight: bold; transition: background 0.2s; }}
        #back-btn:hover {{ background: #555; }}
    </style>
</head>
<body>
    <div class="ui-panel">
        <button id="back-btn" onclick="switchView('global')">← Back to Full Graph</button>
        <div class="legend">
            <div><span style="color: #4285F4;">&#9679;</span> Variable (Non-Terminal)</div>
            <div><span style="color: #34A853;">&#9679;</span> Terminal</div>
            <hr style="margin: 5px 0; border-top: 1px solid #ccc; border-bottom: none;">
            <div><span style="color: #FBBC05;">&#9679;</span> Selected Node</div>
            <div><span style="color: #9C27B0;">&#9679;</span> Parent Nodes (LHS)</div>
            <div><span style="color: #FF6D00;">&#9679;</span> Child Nodes (RHS)</div>
            <div style="margin-top: 5px; font-size: 12px; color: #666; font-style: italic;">Click a node to isolate</div>
        </div>
    </div>
    
    <svg id="canvas" viewBox="{global_vb["x"]} {global_vb["y"]} {global_vb["w"]} {global_vb["h"]}" xmlns="http://www.w3.org/2000/svg">
        <defs>
            <marker id="arrowhead" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path d="M 0 0 L 10 5 L 0 10 z" fill="#888" /></marker>
            <marker id="arrowhead-highlighted" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 0 0 L 10 5 L 0 10 z" fill="#FF6D00" /></marker>
            <marker id="arrowhead-parent" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 0 0 L 10 5 L 0 10 z" fill="#9C27B0" /></marker>
        </defs>
        {chr(10).join(svg_layers)}
    </svg>

    <script>
        const svg = document.getElementById('canvas');
        const viewsData = {json.dumps(views_data)};
        
        let currentView = 'global';
        let isPanning = false, startP = {{x:0, y:0}};
        let viewBox = {{...viewsData.global.vb}};
        let topology = viewsData.global.topo;
        
        function doUpdateScale() {{
            const scale = viewBox.w / svg.clientWidth;
            document.documentElement.style.setProperty('--zoom-scale', scale);
            if ((180 / scale) < 60) {{ svg.classList.add('hide-text'); }} else {{ svg.classList.remove('hide-text'); }}
        }}

        let updateScaleTimeout;
        function updateScale() {{
            clearTimeout(updateScaleTimeout);
            updateScaleTimeout = setTimeout(doUpdateScale, 30);
        }}
        
        function applyViewBox() {{
            svg.setAttribute('viewBox', `${{viewBox.x}} ${{viewBox.y}} ${{viewBox.w}} ${{viewBox.h}}`);
            updateScale();
        }}
        
        function applyDefaultHighlight() {{
            if (currentView === 'global') return;
            
            const prefix = 'local-' + currentView;
            const centerId = currentView;
            
            const centerNode = document.getElementById(`${{prefix}}-${{centerId}}`);
            if (centerNode) {{
                centerNode.classList.add('show-detailed');
                centerNode.parentNode.appendChild(centerNode); 
            }}
            
            const data = topology[centerId];
            if (data && data.parents) {{
                data.parents.forEach(parentId => {{
                    const parentNode = document.getElementById(`${{prefix}}-${{parentId}}`);
                    if (parentNode) {{
                        parentNode.classList.add('show-detailed');
                        parentNode.parentNode.appendChild(parentNode); 
                    }}
                }});
            }}
        }}

        function switchView(viewId) {{
            document.getElementById('view-' + currentView).setAttribute('display', 'none');
            
            currentView = viewId;
            document.getElementById('view-' + currentView).setAttribute('display', 'inline');
            
            document.getElementById('back-btn').style.display = viewId === 'global' ? 'none' : 'block';
            
            viewBox = {{...viewsData[currentView].vb}};
            topology = viewsData[currentView].topo;
            applyViewBox();
            
            applyDefaultHighlight();
        }}
        
        doUpdateScale(); // Initial call to avoid 100ms render pop-in
        window.addEventListener('resize', updateScale);

        function highlightNode(baseNodeId) {{
            const prefix = currentView === 'global' ? 'global' : 'local-' + currentView;
            
            const viewGroup = document.getElementById('view-' + currentView);
            viewGroup.querySelectorAll('.node').forEach(el => {{
                el.classList.add('dimmed');
                el.classList.remove('show-detailed', 'show-label'); 
            }});
            viewGroup.querySelectorAll('.edge').forEach(el => el.classList.add('dimmed'));
            
            const centerNode = document.getElementById(`${{prefix}}-${{baseNodeId}}`);
            const data = topology[baseNodeId];
            if (!data) return;
            
            const edgesToBringToFront = [];
            
            data.children.forEach(childId => {{
                const el = document.getElementById(`${{prefix}}-${{childId}}`);
                if(el) {{ el.classList.remove('dimmed'); el.classList.add('highlight-child', 'show-label'); el.parentNode.appendChild(el); }}
                const edge = document.getElementById(`e-${{prefix}}-${{baseNodeId}}-${{childId}}`);
                if(edge) {{ edge.classList.remove('dimmed'); edge.classList.add('highlight-edge-child'); edgesToBringToFront.push(edge); }}
            }});
            
            data.parents.forEach(parentId => {{
                const el = document.getElementById(`${{prefix}}-${{parentId}}`);
                if(el) {{ el.classList.remove('dimmed'); el.classList.add('highlight-parent', 'show-detailed'); el.parentNode.appendChild(el); }}
                const edge = document.getElementById(`e-${{prefix}}-${{parentId}}-${{baseNodeId}}`);
                if(edge) {{ edge.classList.remove('dimmed'); edge.classList.add('highlight-edge-parent'); edgesToBringToFront.push(edge); }}
            }});
            
            if(centerNode) {{
                centerNode.classList.remove('dimmed');
                centerNode.classList.add('highlight-center', 'show-detailed');
                centerNode.parentNode.appendChild(centerNode);
            }}

            edgesToBringToFront.forEach(edge => edge.parentNode.appendChild(edge));
        }}

        function resetHighlight() {{
            document.getElementById('view-' + currentView).querySelectorAll('.node, .edge').forEach(el => {{
                el.classList.remove('dimmed', 'highlight-center', 'highlight-child', 'highlight-parent', 'highlight-edge-child', 'highlight-edge-parent', 'show-detailed', 'show-label');
            }});
            
            applyDefaultHighlight();
        }}

        svg.onwheel = e => {{
            e.preventDefault();
            svg.classList.add('panning'); 
            const z = e.deltaY > 0 ? 1.05 : (1 / 1.05);
            let mx = e.offsetX / svg.clientWidth * viewBox.w + viewBox.x;
            let my = e.offsetY / svg.clientHeight * viewBox.h + viewBox.y;
            viewBox.x = mx - (mx - viewBox.x) * z;
            viewBox.y = my - (my - viewBox.y) * z;
            viewBox.w *= z; viewBox.h *= z;
            applyViewBox();
        }};

        svg.onmousedown = e => {{ 
            isPanning = true; 
            svg.classList.add('panning');
            startP = {{x: e.clientX, y: e.clientY}}; 
        }};
        
        window.onmousemove = e => {{
            if (!isPanning) return;
            viewBox.x += (startP.x - e.clientX) * (viewBox.w / svg.clientWidth);
            viewBox.y += (startP.y - e.clientY) * (viewBox.h / svg.clientHeight);
            applyViewBox();
            startP = {{x: e.clientX, y: e.clientY}};
        }};
        
        window.onmouseup = () => isPanning = false;
        window.onmouseleave = () => isPanning = false;
    </script>
</body>
</html>"""

    graphs_dir.mkdir(exist_ok=True, parents=True)
    graph_path = (graphs_dir / "cfg_graphviz_isolated.html").absolute()
    with graph_path.open("w", encoding="utf-8") as f:
        f.write(html_content)

    webbrowser.open(f"file://{graph_path}")
