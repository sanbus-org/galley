import { openLanguageDirectory } from "@sanbus/galley";

const [languageDir] = process.argv.slice(2);
if (!languageDir) {
  console.error("usage: node app.bundle.js <language-dir>");
  process.exit(1);
}
const language = await openLanguageDirectory(languageDir);
const session = await language.openSession();
try {
  const parsed = session.parse("alpha:12,beta:3");
  if (parsed !== 15) throw new Error(`expected 15, got ${parsed}`);
  console.log(`default-entry: parsed ${parsed} bytes via ${language.backend}`);
} finally {
  session.close();
}
