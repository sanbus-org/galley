import html
import json
import math
import webbrowser
from pathlib import Path

from data_structures import RightHandSide, TerminalSymbol


def build_table_html(node_name: str, rules_dict: dict) -> str:
    """Generates the Graphviz-style HTML table for right hand sides."""
    if node_name not in rules_dict:
        # Terminal nodes or variables with no rules
        safe_name = html.escape(node_name)
        return f'<table class="rhs-table"><tr><th style="background: #c8e6c9;">{safe_name}</th></tr></table>'

    rhs_set = rules_dict[node_name]
    safe_lhs = html.escape(node_name)

    max_syms = max((len(rhs.symbols) for rhs in rhs_set), default=1)
    if max_syms == 0:
        max_syms = 1

    html_str = '<table class="rhs-table">'
    html_str += f'<tr><th colspan="{max_syms}">{safe_lhs}</th></tr>'

    for rhs in rhs_set:
        html_str += "<tr>"
        if not rhs.symbols:
            html_str += f'<td colspan="{max_syms}" class="empty">&epsilon;</td>'
        else:
            for i, sym in enumerate(rhs.symbols):
                colspan = ""
                if i == len(rhs.symbols) - 1 and len(rhs.symbols) < max_syms:
                    colspan = f' colspan="{max_syms - i}"'
                safe_sym = html.escape(repr(sym))
                html_str += f"<td{colspan}>{safe_sym}</td>"
        html_str += "</tr>"
    html_str += "</table>"
    return html_str


def generate_graph(graphs_dir: Path, rules: dict[bytes, set[RightHandSide]]) -> None:
    nodes = {}
    edges = []

    # Store rules cleanly by string for table generation later
    rules_dict = {}

    for lhs_bytes, rhs_set in rules.items():
        lhs_name = lhs_bytes.decode("utf-8")
        rules_dict[lhs_name] = rhs_set

        if lhs_name not in nodes:
            nodes[lhs_name] = {"label": lhs_name, "type": "variable"}

        for rhs in rhs_set:
            for symbol in rhs.symbols:
                sym_name = repr(symbol)
                sym_type = (
                    "terminal" if isinstance(symbol, TerminalSymbol) else "variable"
                )

                if sym_name not in nodes:
                    nodes[sym_name] = {"label": sym_name, "type": sym_type}

                edges.append((lhs_name, sym_name))

    edges = list(set(edges))
    node_ids = list(nodes.keys())

    # --- 1. Calculate Max Depth (Longest Path) ---
    # Finds the maximum steps from the start node, pushing elements as far right as possible
    depths = {n: 0 for n in node_ids}
    max_d = len(node_ids)

    if node_ids:
        for _ in range(max_d):
            changed = False
            for u, v in edges:
                if depths[u] + 1 > depths[v]:
                    depths[v] = depths[u] + 1
                    changed = True
            if not changed:
                break

    # Normalize depth layers in case of gaps
    sorted_unique_depths = sorted(list(set(depths.values())))
    depth_map = {d: i for i, d in enumerate(sorted_unique_depths)}
    depths = {n: depth_map[d] for n, d in depths.items()}

    # --- 2. Initial Grid Assignment ---
    X_STEP_DISTANCE = 350
    Y_STEP_DISTANCE = 80

    layers = {}
    for n, d in depths.items():
        layers.setdefault(d, []).append(n)

    pos = {}
    for d, layer_nodes in layers.items():
        for i, n in enumerate(layer_nodes):
            pos[n] = [d * X_STEP_DISTANCE, (i - len(layer_nodes) / 2) * Y_STEP_DISTANCE]

    # --- 3. 1D Physics Engine (Y-axis only) to untangle edges ---
    if node_ids:
        temperature = 100.0
        iterations = 300

        for _ in range(iterations):
            disp_y = {n: 0.0 for n in node_ids}

            # Repulsion (Only push apart nodes in the SAME depth column)
            for v in node_ids:
                for u in node_ids:
                    if v != u and depths[v] == depths[u]:
                        dy = pos[v][1] - pos[u][1]
                        dist = abs(dy)
                        if dist < 1.0:
                            dist = 1.0
                        force = 2500.0 / dist
                        disp_y[v] += (dy / dist) * force

            # Attraction (Connected nodes pull each other to the same Y-level)
            for u, v in edges:
                dy = pos[u][1] - pos[v][1]
                force = dy * 0.15
                disp_y[u] -= force
                disp_y[v] += force

            # Apply movements
            for v in node_ids:
                dy = disp_y[v]
                if abs(dy) > 0:
                    pos[v][1] += math.copysign(min(abs(dy), temperature), dy)

            temperature *= 0.95

        # Final pass: Enforce strict minimum vertical spacing
        for _, layer_nodes in layers.items():
            layer_nodes.sort(key=lambda n: pos[n][1])
            for i in range(1, len(layer_nodes)):
                prev, curr = layer_nodes[i - 1], layer_nodes[i]
                if pos[curr][1] - pos[prev][1] < 45:
                    pos[curr][1] = pos[prev][1] + 45

    # --- 4. Calculate Viewport ---
    if pos:
        min_x = min(p[0] for p in pos.values())
        max_x = max(p[0] for p in pos.values())
        min_y = min(p[1] for p in pos.values())
        max_y = max(p[1] for p in pos.values())
    else:
        min_x, max_x, min_y, max_y = 0, 800, 0, 600

    pad = max((max_x - min_x) * 0.1, (max_y - min_y) * 0.1, 150)
    vb_x, vb_y = min_x - pad, min_y - pad
    vb_w, vb_h = (max_x - min_x) + 2 * pad, (max_y - min_y) + 2 * pad

    topology = {
        name: {"parents": [], "children": [], "x": pos[name][0], "y": pos[name][1]}
        for name in node_ids
    }

    svg_elements = []

    # SVG Defs for perfectly aligned arrowheads
    # refX shifts the arrow out of the node center so it neatly touches the outer radius edge
    svg_elements.append("""
        <defs>
            <marker id="arrowhead" viewBox="0 0 10 10" refX="13.5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#888" />
            </marker>
            <marker id="arrowhead-highlighted" viewBox="0 0 10 10" refX="12" refY="5" markerWidth="5" markerHeight="5" orient="auto">
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#FF6D00" />
            </marker>
            <marker id="arrowhead-parent" viewBox="0 0 10 10" refX="12" refY="5" markerWidth="5" markerHeight="5" orient="auto">
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#9C27B0" />
            </marker>
        </defs>
    """)

    for u, v in edges:
        topology[u]["children"].append(v)
        topology[v]["parents"].append(u)

        x1, y1 = pos[u]
        x2, y2 = pos[v]
        svg_elements.append(
            f'<line id="e-{u}-{v}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="edge" stroke="#888" stroke-width="2.5" vector-effect="non-scaling-stroke" marker-end="url(#arrowhead)" />'
        )

    for n_name, n_info in nodes.items():
        x, y = pos[n_name]

        label = html.escape(n_info["label"])
        color = "#34A853" if n_info["type"] == "terminal" else "#4285F4"

        est_width = len(label) * 9.5 + 12
        rect_x = -est_width / 2

        # Build Graphviz HTML equivalent
        table_html = build_table_html(n_name, rules_dict)

        node_content = f"""
            <g class="simple-view">
                <circle cx="0" cy="0" r="8" fill="{color}" stroke="#fff" stroke-width="1.5" class="node-circle"/>
                <rect class="label-bg" x="{rect_x}" y="14" width="{est_width}" height="24" rx="4" />
                <text x="0" y="31" font-family="sans-serif" fill="#111" text-anchor="middle" font-weight="bold" pointer-events="none">{label}</text>
            </g>
            <foreignObject class="detailed-view" x="-500" y="-500" width="1000" height="1000" style="pointer-events: none;">
                <div xmlns="http://www.w3.org/1999/xhtml" style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; pointer-events: none;">
                    {table_html}
                </div>
            </foreignObject>
        """

        svg_elements.append(
            f'<g id="{n_name}" class="node" style="--x: {x}px; --y: {y}px;" onmouseenter="highlightNode(\'{n_name}\')" onmouseleave="resetHighlight()">'
            f"{node_content}"
            f"</g>"
        )

    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>CFG Visualization (Hierarchical)</title>
    <style>
        :root {{ --zoom-scale: 1; }}
        body {{ margin: 0; padding: 0; overflow: hidden; background-color: #f8f9fa; font-family: sans-serif; }}
        svg {{ width: 100vw; height: 100vh; cursor: grab; }}
        svg:active {{ cursor: grabbing; }}
        
        /* Node Transform & Zoom Mechanics */
        .node {{ transform: translate(var(--x), var(--y)) scale(var(--zoom-scale)); transition: transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275); }}
        .node.show-detailed {{ transform: translate(var(--x), var(--y)) scale(calc(var(--zoom-scale) * 1.3)); }}
        
        .node text {{ font-size: 16px; transition: opacity 0.2s; pointer-events: none; }}
        .label-bg {{ fill: rgba(255, 255, 255, 0.8); stroke: transparent; stroke-width: 1.5; transition: all 0.2s; cursor: pointer; }}
        .node:hover .label-bg {{ fill: rgba(255, 255, 255, 1); stroke: #333; }}
        .node:hover text {{ opacity: 1 !important; }}
        
        .hide-text .node .simple-view text {{ opacity: 0; }}
        .hide-text .node .simple-view .label-bg {{ opacity: 0; }}
        .hide-text .node:hover .simple-view .label-bg {{ opacity: 1; }} 
        
        /* Detailed Table CSS */
        .detailed-view {{ opacity: 0; transition: opacity 0.2s; }}
        .simple-view {{ opacity: 1; transition: opacity 0.2s; }}
        
        .node.show-detailed .detailed-view {{ opacity: 1; }}
        .node.show-detailed .simple-view {{ opacity: 0; }}
        
        .rhs-table {{
            border-collapse: collapse;
            font-family: sans-serif;
            font-size: 14px;
            background: white;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            border-radius: 6px;
            overflow: hidden;
            pointer-events: auto; /* Allows stable hover if mouse enters the table box */
            border: 2px solid #333;
        }}
        .rhs-table th {{ background: #bbdefb; border-bottom: 1px solid #333; padding: 6px 12px; font-weight: bold; color: #111; }}
        .rhs-table td {{ border: 1px solid #ccc; padding: 6px 12px; text-align: center; color: #111; }}
        .rhs-table td.empty {{ color: #888; font-style: italic; font-family: serif; }}
        
        /* Highlighting and Dimming CSS */
        .edge {{ transition: stroke 0.2s, opacity 0.2s; }}
        .node-circle {{ transition: fill 0.2s, stroke 0.2s, opacity 0.2s; }}
        
        .dimmed {{ opacity: 0.15 !important; }}
        
        .highlight-center .node-circle {{ fill: #FBBC05 !important; stroke: #333 !important; }}
        .highlight-child .node-circle {{ fill: #FF6D00 !important; }}
        .highlight-parent .node-circle {{ fill: #9C27B0 !important; }}
        
        .highlight-edge-child {{ stroke: #FF6D00 !important; opacity: 1 !important; stroke-width: 4 !important; marker-end: url(#arrowhead-highlighted) !important; }}
        .highlight-edge-parent {{ stroke: #9C27B0 !important; opacity: 1 !important; stroke-width: 4 !important; marker-end: url(#arrowhead-parent) !important; }}
        
        .legend {{ position: absolute; top: 10px; left: 10px; background: white; padding: 10px; border-radius: 5px; box-shadow: 0 1px 3px rgba(0,0,0,0.2); pointer-events: none; z-index: 10; border: 1px solid #eee; }}
    </style>
</head>
<body>
    <div class="legend">
        <div><span style="color: #4285F4;">&#9679;</span> Variable (Non-Terminal)</div>
        <div><span style="color: #34A853;">&#9679;</span> Terminal</div>
        <hr style="margin: 5px 0; border-top: 1px solid #ccc; border-bottom: none;">
        <div><span style="color: #FBBC05;">&#9679;</span> Hovered Node</div>
        <div><span style="color: #9C27B0;">&#9679;</span> Parent Nodes (LHS)</div>
        <div><span style="color: #FF6D00;">&#9679;</span> Child Nodes (RHS)</div>
    </div>
    <svg id="canvas" viewBox="{vb_x} {vb_y} {vb_w} {vb_h}" xmlns="http://www.w3.org/2000/svg">
        <g id="viewport">
            {chr(10).join(svg_elements)}
        </g>
    </svg>

    <script>
        const svg = document.getElementById('canvas');
        let isPanning = false, startP = {{x:0, y:0}};
        let viewBox = {{x: {vb_x}, y: {vb_y}, w: {vb_w}, h: {vb_h}}};
        
        const topology = {json.dumps(topology)};
        
        function updateScale() {{
            const scale = viewBox.w / svg.clientWidth * 2;
            document.documentElement.style.setProperty('--zoom-scale', scale);
            
            if ((180 / scale) < 60) {{
                svg.classList.add('hide-text');
            }} else {{
                svg.classList.remove('hide-text');
            }}
        }}
        
        updateScale(); 
        window.addEventListener('resize', updateScale);

        function highlightNode(nodeId) {{
            document.querySelectorAll('.node, .edge').forEach(el => el.classList.add('dimmed'));
            
            const centerNode = document.getElementById(nodeId);
            const data = topology[nodeId];
            
            if(centerNode) {{
                centerNode.classList.remove('dimmed');
                centerNode.classList.add('highlight-center', 'show-detailed');
            }}
            
            data.children.forEach(childId => {{
                const el = document.getElementById(childId);
                if(el) {{ el.classList.remove('dimmed'); el.classList.add('highlight-child'); }} // Children remain simple
                
                const edge = document.getElementById(`e-${{nodeId}}-${{childId}}`);
                if(edge) {{ edge.classList.remove('dimmed'); edge.classList.add('highlight-edge-child'); edge.parentNode.appendChild(edge); }}
            }});
            
            data.parents.forEach(parentId => {{
                const el = document.getElementById(parentId);
                if(el) {{ 
                    el.classList.remove('dimmed'); 
                    el.classList.add('highlight-parent', 'show-detailed'); // Parents reveal detailed tables
                    el.parentNode.appendChild(el); 
                }}
                
                const edge = document.getElementById(`e-${{parentId}}-${{nodeId}}`);
                if(edge) {{ edge.classList.remove('dimmed'); edge.classList.add('highlight-edge-parent'); edge.parentNode.appendChild(edge); }}
            }});
            
            // Bring center node to absolute front so table overlaps everything
            if(centerNode) centerNode.parentNode.appendChild(centerNode);
        }}

        function resetHighlight() {{
            document.querySelectorAll('.node, .edge').forEach(el => {{
                el.classList.remove('dimmed', 'highlight-center', 'highlight-child', 'highlight-parent', 'highlight-edge-child', 'highlight-edge-parent', 'show-detailed');
            }});
        }}

        svg.onwheel = e => {{
            e.preventDefault();
            const z = e.deltaY > 0 ? 1.05 : (1 / 1.05);
            
            let mx = e.offsetX / svg.clientWidth * viewBox.w + viewBox.x;
            let my = e.offsetY / svg.clientHeight * viewBox.h + viewBox.y;
            
            let closestDist = Infinity;
            let closestNode = null;
            for (const [id, data] of Object.entries(topology)) {{
                const dx = data.x - mx;
                const dy = data.y - my;
                const dist = Math.sqrt(dx*dx + dy*dy);
                if (dist < closestDist) {{
                    closestDist = dist;
                    closestNode = data;
                }}
            }}
            
            const snapThreshold = 50 * (viewBox.w / svg.clientWidth);
            if (closestDist < snapThreshold && closestNode) {{
                mx = closestNode.x;
                my = closestNode.y;
            }}

            viewBox.x = mx - (mx - viewBox.x) * z;
            viewBox.y = my - (my - viewBox.y) * z;
            viewBox.w *= z; viewBox.h *= z;
            svg.setAttribute('viewBox', `${{viewBox.x}} ${{viewBox.y}} ${{viewBox.w}} ${{viewBox.h}}`);
            updateScale();
        }};

        svg.onmousedown = e => {{ isPanning = true; startP = {{x: e.clientX, y: e.clientY}}; }};
        window.onmousemove = e => {{
            if (!isPanning) return;
            viewBox.x += (startP.x - e.clientX) * (viewBox.w / svg.clientWidth);
            viewBox.y += (startP.y - e.clientY) * (viewBox.h / svg.clientHeight);
            svg.setAttribute('viewBox', `${{viewBox.x}} ${{viewBox.y}} ${{viewBox.w}} ${{viewBox.h}}`);
            startP = {{x: e.clientX, y: e.clientY}};
        }};
        window.onmouseup = () => isPanning = false;
        window.onmouseleave = () => isPanning = false;
    </script>
</body>
</html>"""

    graphs_dir.mkdir(exist_ok=True, parents=True)
    graph_path = (graphs_dir / "cfg_hierarchical_graph.html").absolute()
    with graph_path.open("w", encoding="utf-8") as f:
        f.write(html_content)

    webbrowser.open(f"file://{graph_path}")
