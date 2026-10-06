// Verifica a integridade dos artefatos; não substitui revisão visual no navegador.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(script);
const screens = JSON.parse(script.match(/^const screens=([\s\S]*?);let current=/)[1]);
assert.equal(screens.length, 9);
const ids = new Set(screens.map(s => s.id));
const actions = new Set(['favorite', 'quantity', 'buy', 'save', 'search', 'range:5d', 'range:1mo', 'range:3mo', 'range:1y']);
for (const screen of screens) {
  assert(fs.existsSync(path.join(__dirname, screen.id + '.svg')));
  for (const match of screen.body.matchAll(/data-action="([^"]+)"/g)) {
    assert(ids.has(match[1]) || actions.has(match[1]), match[1]);
  }
}
for (const match of html.matchAll(/href="([^"]+)"/g)) {
  assert(fs.existsSync(path.join(__dirname, match[1])), match[1]);
}
assert(html.includes('range=3mo'));
console.log('PASS: sintaxe JavaScript, 9 telas, destinos de navegação e links locais.');
