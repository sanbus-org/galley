/**
 * Host-side counting hooks for the docs Galley checker grammar
 * (`docs/try-it/lang/galley/ll.grm`, `@count*` annotations).
 *
 * The Try-it component imports this module and registers it with
 * `installProcedures` (browsers cannot auto-scan `procedures.*`, so the
 * registration is explicit). Only the six `hook_count*` names below are
 * picked up; `stats` and `resetStats` are plain helpers for the page.
 * The component resets the counters before every Galley parse and reads
 * them after.
 */

export const stats = {
  alternative: 0,
  variable: 0,
  terminal: 0,
  generative: 0,
  annotation: 0,
  comment: 0,
};

export function resetStats() {
  for (const name of Object.keys(stats)) stats[name] = 0;
}

export function hook_countAlternative() {
  stats.alternative++;
}

export function hook_countVariable() {
  stats.variable++;
}

export function hook_countTerminal() {
  stats.terminal++;
}

export function hook_countGenerative() {
  stats.generative++;
}

export function hook_countAnnotation() {
  stats.annotation++;
}

export function hook_countComment() {
  stats.comment++;
}
