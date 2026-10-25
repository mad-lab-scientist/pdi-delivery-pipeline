// Commands for each public stage in website/src/content/pipeline.mjs (same ids, same order).
// {repo} and {work} are replaced by ci/run.mjs. A stage passes when every command exits 0 and its summary line
// ("N passed, M failed") reports 0 failed; `count` reads a check count from output that has no summary line.
import { stages as publicStages } from '../website/src/content/pipeline.mjs';

const commands = {
  facts: { run: [['node', 'website/build.mjs'], ['node', 'website/test/run-tests.mjs']] },
  // Packages the release candidate (the rehearsal deploys that tarball). A released version is built from source
  // without repackaging, and the verified archived upload is restored for the later stages.
  build: { run: [['node', 'portal/patch/apply.mjs', '--ci']], count: /patched \d+ files with (\d+) patches/ },
  static: { run: [['node', 'portal/patch/test.mjs']] },
  smoke: { run: [['node', 'portal/patch/smoke.mjs', '{work}/smoke']] },
  secrets: { run: [['node', 'ci/scan-secrets.mjs']] },
  deps: { run: [['node', 'ci/sbom.mjs', '{work}']] },
  rehearsal: {
    requires: 'docker',
    run: [
      ['docker', 'build', '-q', '-t', 'pdi-web3-sim', 'portal/patch/linux-sim'],
      ['docker', 'run', '--rm', '-v', '{repo}/portal:/portal:ro', 'pdi-web3-sim', 'bash', '/portal/patch/linux-sim/rehearse-linux.sh'],
    ],
  },
};

export const stages = publicStages.map((s) => {
  if (!commands[s.id]) throw new Error(`no command for public stage ${s.id}`);
  return { ...s, ...commands[s.id] };
});
for (const id of Object.keys(commands)) if (!publicStages.some((s) => s.id === id)) throw new Error(`command without a public stage: ${id}`);
