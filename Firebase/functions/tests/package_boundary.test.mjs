import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, readdir, rm, stat } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { builtinModules, createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const packageRoot = resolve(import.meta.dirname, '..');
const require = createRequire(import.meta.url);
const expectedExports = [
  'approveInstituteMembership',
  'createOrReactivateParentLink',
  'deactivateNotificationDevice',
  'getNotificationPreferences',
  'invalidateStudentInstituteLinks',
  'listApplicableParentNotices',
  'refreshNotificationDevice',
  'registerNotificationDevice',
  'requestInstituteMembership',
  'revokeParentStudentLink',
  'syncParentProjectionForAssignment',
  'syncParentProjectionForAttendance',
  'syncParentProjectionForAttendanceCorrection',
  'syncParentProjectionForClass',
  'syncParentProjectionForInstitute',
  'syncParentProjectionForSchedule',
  'syncParentProjectionForStudent',
  'synchronizeInstitutePublicProfile',
  'synchronizeParentAttendanceSummary',
  'synchronizeParentClassProjection',
  'synchronizeParentNotice',
  'synchronizeParentStudentProjection',
  'updateNotificationPermissionStatus',
  'updateNotificationPreferences',
];

const productionModules = async (directory) => {
  const entries = await readdir(directory, { withFileTypes: true });
  const modules = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) modules.push(...await productionModules(path));
    else if (entry.name.endsWith('.mjs')) modules.push(path);
  }
  return modules;
};

const importSpecifiers = (source) => [
  ...source.matchAll(/(?:from\s+|import\s*\()(['"])([^'"]+)\1/g),
].map((match) => match[2]);

test('every production runtime import resolves from the Functions package', async () => {
  const manifest = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
  const modules = [join(packageRoot, 'index.mjs'), ...await productionModules(join(packageRoot, 'lib'))];
  for (const modulePath of modules) {
    const source = await readFile(modulePath, 'utf8');
    for (const specifier of importSpecifiers(source)) {
      if (specifier.startsWith('.')) {
        const resolved = resolve(dirname(modulePath), specifier);
        const pathFromRoot = relative(packageRoot, resolved);
        const outside = pathFromRoot.startsWith('..') || isAbsolute(pathFromRoot);
        assert.equal(outside, false, `${modulePath} imports outside package: ${specifier}`);
        assert.equal((await stat(resolved)).isFile(), true, `Missing runtime import: ${specifier}`);
        continue;
      }
      if (specifier.startsWith('node:') || builtinModules.includes(specifier)) continue;
      const dependency = specifier.startsWith('@')
        ? specifier.split('/').slice(0, 2).join('/')
        : specifier.split('/')[0];
      assert.ok(manifest.dependencies[dependency], `Undeclared runtime dependency: ${dependency}`);
      const resolved = require.resolve(specifier);
      const pathFromRoot = relative(packageRoot, resolved);
      assert.equal(pathFromRoot.startsWith('node_modules'), true, `Dependency resolved outside package: ${specifier}`);
    }
  }
});

test('a staged copy loads index and exposes all approved callables', async (context) => {
  const stagingRoot = await mkdtemp(join(packageRoot, '.package-boundary-'));
  context.after(() => rm(stagingRoot, { recursive: true, force: true }));
  await Promise.all([
    cp(join(packageRoot, 'index.mjs'), join(stagingRoot, 'index.mjs')),
    cp(join(packageRoot, 'lib'), join(stagingRoot, 'lib'), { recursive: true }),
    cp(join(packageRoot, 'package.json'), join(stagingRoot, 'package.json')),
    cp(join(packageRoot, 'package-lock.json'), join(stagingRoot, 'package-lock.json')),
    cp(join(packageRoot, 'README.md'), join(stagingRoot, 'README.md')),
  ]);
  process.env.FUNCTIONS_EMULATOR = 'true';
  const packaged = await import(`${pathToFileURL(join(stagingRoot, 'index.mjs')).href}?boundary=${Date.now()}`);
  assert.deepEqual(Object.keys(packaged).sort(), expectedExports);
});

test('package metadata fixes production runtime and deployment contents', async () => {
  const manifest = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
  assert.equal(manifest.engines.node, '22');
  assert.equal(manifest.main, 'index.mjs');
  assert.deepEqual(manifest.files, ['index.mjs', 'lib/**', 'tools/**', 'README.md']);
});
