/**
 * Host-side counting hooks for the docs Lisp checker grammar
 * (`docs/try-it/lang/lisp/ll.grm`, `@count*` annotations).
 *
 * The Try-it component imports this module and registers it with
 * `installProcedures` (browsers cannot auto-scan `procedures.*`, so the
 * registration is explicit). Only the seven `hook_count*` names below are
 * picked up; `stats` and `resetStats` are plain helpers for the page.
 * The component resets the counters before every Lisp parse and reads
 * them after.
 */

export const stats = {
  abbrev: 0,
  list: 0,
  hash: 0,
  string: 0,
  escaped: 0,
  number: 0,
  symbol: 0,
};

export function resetStats() {
  for (const name of Object.keys(stats)) stats[name] = 0;
}

export function hook_countAbbrev() {
  stats.abbrev++;
}

export function hook_countList() {
  stats.list++;
}

export function hook_countHash() {
  stats.hash++;
}

export function hook_countString() {
  stats.string++;
}

export function hook_countEscaped() {
  stats.escaped++;
}

export function hook_countNumber() {
  stats.number++;
}

export function hook_countSymbol() {
  stats.symbol++;
}
