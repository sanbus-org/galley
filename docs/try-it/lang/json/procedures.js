/**
 * Host-side counting hooks for the docs JSON checker grammar
 * (`docs/try-it/lang/json/ll.grm`, `@count*` annotations).
 *
 * The Try-it component imports this module and registers it with
 * `installProcedures` (browsers cannot auto-scan `procedures.*`, so the
 * registration is explicit). Only the seven `hook_count*` names below are
 * picked up; `stats` and `resetStats` are plain helpers for the page.
 * The component resets the counters before every JSON parse and reads
 * them after.
 */

export const stats = {
  object: 0,
  array: 0,
  number: 0,
  string: 0,
  null: 0,
  boolean: 0,
  key: 0,
};

export function resetStats() {
  for (const name of Object.keys(stats)) stats[name] = 0;
}

export function hook_countObject() {
  stats.object++;
}

export function hook_countArray() {
  stats.array++;
}

export function hook_countNumber() {
  stats.number++;
}

export function hook_countString() {
  stats.string++;
}

export function hook_countNull() {
  stats.null++;
}

export function hook_countBoolean() {
  stats.boolean++;
}

export function hook_countKey() {
  stats.key++;
}
