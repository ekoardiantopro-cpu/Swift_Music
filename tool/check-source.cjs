// Structural smoke check only. This does not replace the Dart analyzer.
const fs = require('node:fs');
const path = require('node:path');
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
}
let failures = 0;
for (const file of [...walk('lib'), ...walk('test')].filter(file => file.endsWith('.dart'))) {
  const source = fs.readFileSync(file, 'utf8');
  const stack = [];
  let quote = null;
  let comment = null;
  let line = 1;
  for (let i = 0; i < source.length; i++) {
    const char = source[i], next = source[i + 1];
    if (char === '\n') line++;
    if (comment === 'line') { if (char === '\n') comment = null; continue; }
    if (comment === 'block') { if (char === '*' && next === '/') { comment = null; i++; } continue; }
    if (quote) {
      if (char === '\\') { i++; continue; }
      if (char === quote) quote = null;
      continue;
    }
    if (char === '/' && next === '/') { comment = 'line'; i++; continue; }
    if (char === '/' && next === '*') { comment = 'block'; i++; continue; }
    if (char === "'" || char === '"') { quote = char; continue; }
    if ('([{'.includes(char)) stack.push({ char, line });
    if (')]}'.includes(char)) {
      const opening = stack.pop();
      if (opening?.char !== { ')': '(', ']': '[', '}': '{' }[char]) {
        console.error(`${file}:${line}: delimiter mismatch`); failures++; break;
      }
    }
  }
  if (stack.length) { console.error(`${file}: unclosed delimiters`, stack); failures++; }
  for (const match of source.matchAll(/import\s+'([^']+)'/g)) {
    if (!match[1].includes(':') && !fs.existsSync(path.resolve(path.dirname(file), match[1]))) {
      console.error(`${file}: missing import ${match[1]}`); failures++;
    }
  }
}
if (failures) process.exitCode = 1;
else console.log('Dart source delimiters and relative import targets: OK (not a compile check).');
