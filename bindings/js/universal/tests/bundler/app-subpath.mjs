import { init, Session } from "@sanbus/galley/browser";

await init({ url: "http://127.0.0.1:8123/grammar.wasm" });
const session = new Session();
try {
  const parsed = session.parse("alpha:12,beta:3");
  if (parsed !== 15) throw new Error(`expected 15, got ${parsed}`);
  console.log(`subpath-entry: parsed ${parsed} bytes`);
} finally {
  session.close();
}
