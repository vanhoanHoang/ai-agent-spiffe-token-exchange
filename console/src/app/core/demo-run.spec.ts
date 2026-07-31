import { parseDemoRun } from './demo-run';
import { demoRunFixture } from './testing/fixture';

describe('parseDemoRun (fail closed)', () => {
  it('accepts a well-formed capture', () => {
    expect(parseDemoRun(demoRunFixture()).actors.human.username).toBe('alice');
  });

  it('rejects a capture with missing rejections', () => {
    const bad = { ...demoRunFixture(), rejections: [] };
    expect(() => parseDemoRun(bad)).toThrowError(/rejections/);
  });

  it('rejects a capture whose token signature is not redacted', () => {
    const run = demoRunFixture();
    const bad = {
      ...run,
      tokens: [{ ...run.tokens[0], signature: 'sig-bytes' }, run.tokens[1]],
    };
    expect(() => parseDemoRun(bad)).toThrowError(/redacted/);
  });

  it('rejects a capture containing a JWT-shaped string anywhere', () => {
    const run = demoRunFixture();
    const jwt = 'a'.repeat(24) + '.' + 'b'.repeat(24) + '.' + 'c'.repeat(24);
    const bad = { ...run, log_tail: [...run.log_tail, `leaked ${jwt}`] };
    expect(() => parseDemoRun(bad)).toThrowError(/token-shaped/);
  });

  it('rejects the wrong trust domain', () => {
    const bad = { ...demoRunFixture(), trust_domain: 'spiffe://evil.example' };
    expect(() => parseDemoRun(bad)).toThrowError(/trust domain/);
  });
});
