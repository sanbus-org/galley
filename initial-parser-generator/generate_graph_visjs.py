import json
import webbrowser
from pathlib import Path

from data_structures import RightHandSide, TerminalSymbol


def sanitize_text(text: str) -> str:
    """Escapes control characters and ensures the string is never empty for Graphviz."""
    sanitized = "".join(c if ord(c) >= 32 else f"\\x{ord(c):02x}" for c in text)
    return sanitized if sanitized.strip() else "&nbsp;"


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

    vis_nodes = []
    vis_edges = []

    for node, node_id in node_to_id.items():
        # Add node
        vis_nodes.append(
            {
                "id": node_id,
                "label": node,
                "title": f"Detailed info for {node}",  # Shows on hover
            }
        )

    # Add edges
    for u, v in edges:
        vis_edges.append(
            {
                "from": node_to_id[u],
                "to": node_to_id[v],
                "arrows": "to",  # Optional: makes it a directed graph
            }
        )

    html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Graph Visualization</title>
    <!-- We load the JS library from a CDN, no local installation needed -->
    <script type="text/javascript" src="vis-network.min.js"></script>
    <style type="text/css">
        body, html {{ margin: 0; padding: 0; height: 100%; font-family: sans-serif; }}
        #mynetwork {{ width: 100%; height: 100%; border: none; background-color: #f9f9f9; }}
    </style>
</head>
<body>
<div id="mynetwork"></div>

<script type="text/javascript">
    // Dumped from Python
    var nodes = new vis.DataSet({json.dumps(vis_nodes)});
    var edges = new vis.DataSet({json.dumps(vis_edges)});

    var container = document.getElementById('mynetwork');
    var data = {{
        nodes: nodes,
        edges: edges
    }};
    
    // Configuration to make it sophisticated and uncluttered
    var options = {{
        nodes: {{
            shape: 'dot',
            size: 20,
            font: {{ size: 16, face: 'Helvetica' }},
            borderWidth: 2,
            color: {{ background: '#97C2FC', border: '#2B7CE9' }}
        }},
        edges: {{
            width: 1.5,
            smooth: {{ type: 'continuous' }}
        }},
        physics: {{
            forceAtlas2Based: {{
                gravitationalConstant: -50000,
                centralGravity: 0.01,
                springLength: 10,
                springConstant: 8
            }},
            maxVelocity: 50,
            solver: 'forceAtlas2Based',
            timestep: 1,
            stabilization: {{ iterations: 500 }}
        }},
        interaction: {{
            hover: true,
            tooltipDelay: 200,
            zoomView: true
        }}
    }};

    var network = new vis.Network(container, data, options);
</script>
</body>
</html>
"""

    graphs_dir.mkdir(exist_ok=True, parents=True)
    graph_path = (graphs_dir / "graph_output.html").absolute()
    with graph_path.open("w", encoding="utf-8") as f:
        f.write(html_content)

    webbrowser.open(f"file://{graph_path}")
