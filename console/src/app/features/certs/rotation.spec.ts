import { countdown, rotationView } from './rotation';

describe('rotation math', () => {
  const notBefore = '2026-07-31T10:00:00Z';
  const notAfter = '2026-07-31T11:00:00Z'; // 1h TTL, half-life 10:30

  it('computes time to expiry and to the half-life rotation estimate', () => {
    const now = Date.parse('2026-07-31T10:10:00Z');
    const v = rotationView(now, notBefore, notAfter);
    expect(v.expiresInMs).toBe(50 * 60_000);
    expect(v.rotationInMs).toBe(20 * 60_000);
  });

  it('goes negative once the rotation estimate has passed', () => {
    const now = Date.parse('2026-07-31T10:45:00Z');
    expect(rotationView(now, notBefore, notAfter).rotationInMs).toBeLessThan(0);
  });

  it('formats countdowns like a clock and says "due" when passed', () => {
    expect(countdown(20 * 60_000)).toBe('20:00');
    expect(countdown(83_000)).toBe('1:23');
    expect(countdown(3 * 3600_000 + 62_000)).toBe('3:01:02');
    expect(countdown(0)).toBe('due');
    expect(countdown(-5000)).toBe('due');
  });
});
