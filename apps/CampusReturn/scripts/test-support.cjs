const fs = require('node:fs'), path = require('node:path');
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


module.exports = { findTypeScript, readOptions };
