/**
 * Host-side counting hooks for the docs Lua checker grammar
 * (`docs/try-it/lang/lua/ll.grm`, `@count*` annotations).
 *
 * The Try-it component imports this module and registers it with
 * `installProcedures` (browsers cannot auto-scan `procedures.*`, so the
 * registration is explicit). Only the four `hook_count*` names below are
 * picked up; `stats` and `resetStats` are plain helpers for the page.
 * The component resets the counters before every Lua parse and reads
 * them after.
 */

export const stats = {
  string: 0,
  longstring: 0,
  comment: 0,
  group: 0,
};

export function resetStats() {
  for (const name of Object.keys(stats)) stats[name] = 0;
}

export function hook_countString() {
  stats.string++;
}

export function hook_countLongString() {
  stats.longstring++;
}

export function hook_countComment() {
  stats.comment++;
}

export function hook_countGroup() {
  stats.group++;
}
