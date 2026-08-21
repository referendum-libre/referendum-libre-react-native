import { execFileSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';

const SCRIPT = resolve(__dirname, 'secret-scan.sh');
const HEX64 = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'; // nosec: dummy test vector
const ADDRESS = '0x61aa5b68D811884dA4FEC2De4a7AA0464df166E1'; // nosec: public contract address

/** Stage `content` in a throwaway repo and run the real hook script against it. */
function blocks(content: string): boolean {
  const repo = mkdtempSync(join(tmpdir(), 'secret-scan-'));
  try {
    execFileSync('git', ['init', '-q'], { cwd: repo });
    writeFileSync(join(repo, 'candidate.ts'), content);
    execFileSync('git', ['add', 'candidate.ts'], { cwd: repo });
    execFileSync('sh', [SCRIPT], { cwd: repo, encoding: 'utf8' });
    return false;
  } catch {
    return true;
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

describe('secret-scan hook', () => {
  it('blocks secret-shaped strings', () => {
    expect(blocks(`const k = '${HEX64}'\n`)).toBe(true); // 64 hex
    expect(blocks(`const k = '0x${HEX64}'\n`)).toBe(true); // 0x-prefixed
    expect(blocks(`const k = '${HEX64.slice(0, 32)}'\n`)).toBe(true); // 128-bit
    expect(blocks('const k = 8474929182734859302847n\n')).toBe(true); // nosec: bigint fixture
    expect(blocks("const k = '14206245783295726894872618756472634587263545'\n")).toBe(true); // nosec: decimal fixture
  });

  it('allows benign values', () => {
    expect(blocks('const x = 42\n')).toBe(false);
    expect(blocks(`const toAddress = '${ADDRESS}'\n`)).toBe(false); // eth address is public
    expect(blocks(`const k = '${HEX64.slice(0, 40)}'\n`)).toBe(false); // 40 hex, unlabelled
    expect(blocks("const short = 'deadbeef'\n")).toBe(false);
  });

  it('honours `nosec:` only when a reason is given', () => {
    expect(blocks(`const k = '${HEX64}' // nosec: test vector\n`)).toBe(false);
    expect(blocks(`KEY=${HEX64} # nosec: fixture\n`)).toBe(false);
    expect(blocks(`const k = '${HEX64}' // nosec:\n`)).toBe(true);
  });
});
