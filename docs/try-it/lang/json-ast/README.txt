# JSON snapshot-counting setup (docs page experiment)

Same stats-annotated `ll.grm` as `../json` (annotations are inert with
procedures off); `config.zig` builds with AST on and procedures off.
Host-side counting lives in `snapshot-stats.js` (one snapshot crossing
plus a host walk). The page lets the user pick this or the `../json`
hook-counting setup per parse.
