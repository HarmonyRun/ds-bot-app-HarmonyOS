const fs = require('node:fs');
const { releaseTarget } = require('./release-target.cjs');

function checkRelease(tag) {
  const read = path => JSON.parse(fs.readFileSync(path, 'utf8'));
  const version = read('ds-bot/package.json').version;
  const target = releaseTarget(tag || `v${version}`);
  for (const directory of ['ds-bot', 'apps/mobile']) {
    const pkg = read(`${directory}/package.json`);
    const lock = read(`${directory}/package-lock.json`);
    if ([pkg.version, lock.version, lock.packages?.['']?.version].some(value => value !== target.version)) {
      throw new Error(`${directory} package/lock versions must match ${target.version}`);
    }
  }
  if (read('apps/mobile/app.json').expo?.version !== target.version) {
    throw new Error('Expo version must match the plugin and App version');
  }
  if (tag && !fs.existsSync(target.notesFile)) throw new Error('Write bilingual release notes before tagging');
  return target;
}

module.exports = { checkRelease };
if (require.main === module) {
  const target = checkRelease(process.env.RELEASE_TAG);
  console.log(`Plugin and App versions match ${target.version}`);
}
