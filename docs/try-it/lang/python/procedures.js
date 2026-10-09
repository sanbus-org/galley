/**
 * Host-side counting hooks for the docs Python checker grammar
 * (`docs/try-it/lang/python/ll.grm`, `@count*` annotations).
 *
 * The Try-it component imports this module and registers it with
 * `installProcedures` (browsers cannot auto-scan `procedures.*`, so the
 * registration is explicit). Only the eleven `hook_count*` names below
 * are picked up; `stats` and `resetStats` are plain helpers for the
 * page. The component resets the counters before every Python parse
 * and reads them after.
 */

export const stats = {
  function: 0,
  class: 0,
  import: 0,
  if: 0,
  loop: 0,
  with: 0,
  try: 0,
  match: 0,
  case: 0,
  string: 0,
  number: 0,
};

export function resetStats() {
  for (const name of Object.keys(stats)) stats[name] = 0;
}

export function hook_countFunction() {
  stats.function++;
}

export function hook_countClass() {
  stats.class++;
}

export function hook_countImport() {
  stats.import++;
}

export function hook_countIf() {
  stats.if++;
}

export function hook_countLoop() {
  stats.loop++;
}

export function hook_countWith() {
  stats.with++;
}

export function hook_countTry() {
  stats.try++;
}

export function hook_countMatch() {
  stats.match++;
}

export function hook_countCase() {
  stats.case++;
}

export function hook_countString() {
  stats.string++;
}

export function hook_countNumber() {
  stats.number++;
}
