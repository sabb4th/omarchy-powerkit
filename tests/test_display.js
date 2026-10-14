const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const display = {};
vm.createContext(display);
vm.runInContext(fs.readFileSync(require('path').join(__dirname, '../Display.js'), 'utf8'), display);
let mode = 'full', visited = [];
for (let i=0; i<7; i++) { visited.push(mode); mode=display.nextMode(mode); }
assert.strictEqual(mode, 'full');
assert.strictEqual(new Set(visited).size, 7);
assert.strictEqual(display.nextMode('full'), 'percentage');
assert.strictEqual(display.nextMode('percentage'), 'icon');
for (let value=0; value<=100; value++) {
 assert(display.level(value)>=0 && display.level(value)<=10);
}
assert.strictEqual(display.level(null), -1);
assert.strictEqual(display.level(0), 0);
assert.strictEqual(display.level(50), 5);
assert.strictEqual(display.level(100), 10);
assert.strictEqual(display.barText('icon', {}, null, 'en'), '');
assert.strictEqual(display.barText('watts', {power_w:6.4}, null, 'pt'), '6,4 W');
assert.strictEqual(display.barText('full', {percent:50,power_w:6.4}, null, 'en'), '50% · 6.4 W');
assert.strictEqual(display.barText('runtime', {hours:1.5}, null, 'en'), '1h 30m');
assert.strictEqual(display.barText('profile', {percent:75}, 'balanced', 'en'), '75% · BAL');
const locale={}; vm.createContext(locale);
vm.runInContext(fs.readFileSync(require('path').join(__dirname, '../I18n.js'),'utf8'),locale);
assert.strictEqual(locale.tr('Visão geral','en'),'Overview');
assert.strictEqual(locale.tr('TLP e sistema','pt'),'TLP e sistema');
assert.strictEqual(locale.tr('Botão direito: próximo formato','en'),'Right-click: next display mode');
console.log(JSON.stringify({display_modes:7,battery_levels:11,formatting:'ok',catalogue:'ok'}));
