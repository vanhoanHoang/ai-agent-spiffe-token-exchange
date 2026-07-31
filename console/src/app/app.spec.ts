import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

import { App } from './app';
import { demoRunFixture } from './core/testing/fixture';

function mockFetch(body: unknown, ok = true): void {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok,
      status: ok ? 200 : 404,
      json: () => Promise.resolve(body),
    }),
  );
}

describe('App', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('renders the full run from a valid capture', async () => {
    mockFetch(demoRunFixture());
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent).toContain('Two identities, one call');
    expect(el.textContent).toContain('spiffe://lab.internal');
    expect(el.querySelectorAll('dc-step-rail').length).toBe(1);
    expect(el.querySelectorAll('dc-rejection-grid').length).toBe(1);
    expect(el.querySelectorAll('dc-log-panel').length).toBe(1);
  });

  it('shows the login token card first, then the exchange card when selected', async () => {
    mockFetch(demoRunFixture());
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-token-card')?.textContent).toContain("Alice's login token");

    const exchangeBtn = Array.from(el.querySelectorAll<HTMLButtonElement>('.step')).find((b) =>
      b.textContent?.includes('Token exchange'),
    );
    exchangeBtn?.click();
    await fixture.whenStable();
    expect(el.querySelector('dc-token-card')?.textContent).toContain('Delegation token');
    expect(el.querySelector('dc-token-card')?.textContent).toContain('act.sub');
  });

  it('renders the refusal (deny) message in the chat stage', async () => {
    mockFetch(demoRunFixture());
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.step'))
      .find((b) => b.textContent?.includes('end-to-end'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('dc-chat-panel')?.textContent).toContain('insufficient_scope');
    expect(el.querySelector('dc-chat-panel .msg.deny')).toBeTruthy();
  });

  it('renders the error state — never a partial run — for a malformed capture', async () => {
    mockFetch({ version: 1 });
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.error-state')).toBeTruthy();
    expect(el.querySelector('dc-run-header')).toBeFalsy();
  });

  it('renders the error state when the capture is missing', async () => {
    mockFetch(null, false);
    await TestBed.configureTestingModule({ imports: [App] }).compileComponents();
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    expect((fixture.nativeElement as HTMLElement).querySelector('.error-state')).toBeTruthy();
  });
});
