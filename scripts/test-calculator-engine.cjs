#!/usr/bin/env node
'use strict';

// Runs the actual CalculatorEngine.ets and its Hypium cases in Node.
// This checks calculation behavior; DevEco still supplies ArkTS/build validation.
// Usage: node scripts/test-calculator-engine.cjs --deveco-home "<DevEco install directory>"
// Or: --typescript /path/to/typescript.js, DEVECO_HOME, or TYPESCRIPT_PATH.
// Transpilation stays in memory and does not change source or build files.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function readOptions() {
  const options = {};
  for (let index = 2; index < process.argv.length; index++) {
    const name = process.argv[index];
    if (name === '--help' || name === '-h') {
      options.help = true;
      continue;
    }
    if (!['--deveco-home', '-DevEcoHome', '--typescript'].includes(name)) {
      throw new Error(`Unknown option: ${name}`);
    }
    const value = process.argv[++index];
    if (!value || value.startsWith('-')) throw new Error(`Missing value for ${name}`);
    options[name === '-DevEcoHome' ? '--deveco-home' : name] = value;
  }
  return options;
}

function findTypeScript(options) {
  const explicit = options['--typescript'] || process.env.TYPESCRIPT_PATH;
  if (explicit) return require(path.resolve(explicit));
  const home = options['--deveco-home'] || process.env.DEVECO_HOME;
  const roots = home ? [path.resolve(home)] : [];
  if (!home && process.env.ProgramFiles) {
    roots.push(path.join(process.env.ProgramFiles, 'Huawei', 'DevEco Studio'));
  }
  const candidates = roots.flatMap((root) => [
    path.join(root, 'tools', 'hvigor', 'hvigor', 'node_modules', 'typescript', 'lib', 'typescript.js'),
    path.join(root, 'plugins', 'codelinter', 'node_modules', 'typescript', 'lib', 'typescript.js'),
    path.join(root, 'sdk', 'default', 'openharmony', 'ets', 'build-tools', 'ets-loader', 'node_modules',
      'typescript', 'lib', 'typescript.js')
  ]);
  const match = candidates.find((candidate) => fs.existsSync(candidate));
  if (match) return require(match);
  if (!home) {
    try { return require('typescript'); } catch (error) { /* No local TypeScript package. */ }
  }
  throw new Error('TypeScript not found. Pass --deveco-home or --typescript, or set DEVECO_HOME/TYPESCRIPT_PATH.');
}

function loadSource(ts, relativePath, requireFn) {
  const sourcePath = path.join(__dirname, '..', relativePath);
  const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
    fileName: sourcePath.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true
  });
  const errors = (compiled.diagnostics || []).filter((item) => item.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0,
    errors.map((item) => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));
  const module = { exports: {} };
  const context = vm.createContext({ module, exports: module.exports, require: requireFn });
  new vm.Script(compiled.outputText, { filename: sourcePath }).runInContext(context);
  return module.exports;
}

async function main() {
  const options = readOptions();
  if (options.help) {
    console.log('Usage: node scripts/test-calculator-engine.cjs [--deveco-home DIR | --typescript PATH]');
    console.log('Environment alternatives: DEVECO_HOME or TYPESCRIPT_PATH.');
    return;
  }
  const ts = findTypeScript(options);
  const cases = [];
  // The adapter only supplies test registration/assertions. Expected behavior
  // remains in the same ETS tests that run under Hypium on HarmonyOS.
  const hypium = {
    describe(name, body) { console.log(name); body(); },
    it(name, level, body) { cases.push({ name, run: body }); },
    expect(actual) {
      return {
        assertEqual(expected) { assert.equal(actual, expected); },
        assertTrue() { assert.equal(actual, true); }
      };
    }
  };
  const engine = loadSource(ts, 'entry/src/main/ets/model/CalculatorEngine.ets', (name) => {
    throw new Error(`Unexpected calculation-model import: ${name}`);
  });
  const tests = loadSource(ts, 'entry/src/ohosTest/ets/test/CalculatorEngine.test.ets', (name) => {
    if (name === '@ohos/hypium') return hypium;
    if (name === '../../../main/ets/model/CalculatorEngine') return engine;
    throw new Error(`Unexpected test import: ${name}`);
  });
  tests.default();
  assert.ok(cases.length > 0, 'No calculator tests were registered.');
  let passed = 0;
  for (const item of cases) {
    try {
      await item.run();
      passed++;
      console.log(`PASS ${item.name}`);
    } catch (error) {
      console.error(`FAIL ${item.name}`);
      console.error(error);
      process.exitCode = 1;
    }
  }
  console.log(`Calculator engine tests: ${passed}/${cases.length} passed`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
