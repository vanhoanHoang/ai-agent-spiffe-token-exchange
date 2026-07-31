import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

import { App } from './app';
import { LiveClient, LiveState } from './core/live';
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

async function renderApp(live: LiveState = 'offline') {
  await TestBed.configureTestingModule({
    imports: [App],
    providers: [
      {
        provide: LiveClient,
        useValue: {
          me: () => Promise.resolve(live),
          chat: () => Promise.resolve({}),
          svid: () =>
            Promise.resolve({
              spiffeId: 'spiffe://lab.internal/agent-client',
              chain: [
                {
                  role: 'leaf',
                  subject: 'CN=agent-client',
                  issuer: 'CN=SPIRE Intermediate CA',
                  serial: 'ab12',
                  notBefore: '2026-07-31T10:00:00Z',
                  notAfter: '2026-07-31T11:00:00Z',
                  uriSans: ['spiffe://lab.internal/agent-client'],
                  sha256: 'deadbeef'.repeat(8),
                },
              ],
            }),
        },
      },
    ],
  }).compileComponents();
  const fixture = TestBed.createComponent(App);
  await fixture.whenStable();
  return fixture;
}

describe('App', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('renders the full run from a valid capture', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent).toContain('Two identities, one call');
    expect(el.textContent).toContain('spiffe://lab.internal');
    expect(el.querySelectorAll('dc-step-rail').length).toBe(1);
    expect(el.querySelectorAll('dc-rejection-grid').length).toBe(1);
  });

  it('tabs: rejections by default, server log after switching', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-rejection-grid')).toBeTruthy();
    expect(el.querySelector('dc-log-panel')).toBeFalsy();

    Array.from(el.querySelectorAll<HTMLButtonElement>('.tab'))
      .find((b) => b.textContent?.includes('MCP server log'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('dc-log-panel')).toBeTruthy();
    expect(el.querySelector('dc-rejection-grid')).toBeFalsy();
  });

  it('shows the login token card first, then the exchange card when selected', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-token-card')?.textContent).toContain("Alice's login token");

    Array.from(el.querySelectorAll<HTMLButtonElement>('.step'))
      .find((b) => b.textContent?.includes('Token exchange'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('dc-token-card')?.textContent).toContain('Delegation token');
    expect(el.querySelector('dc-token-card')?.textContent).toContain('act.sub');
  });

  it('renders the refusal (deny) message in the chat stage', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp();
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
    const fixture = await renderApp();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.error-state')).toBeTruthy();
    expect(el.querySelector('dc-run-header')).toBeFalsy();
  });

  it('renders the error state when the capture is missing', async () => {
    mockFetch(null, false);
    const fixture = await renderApp();
    expect((fixture.nativeElement as HTMLElement).querySelector('.error-state')).toBeTruthy();
  });

  it('offline: no live panel and no login banner', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp('offline');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
    expect(el.querySelector('.login-banner')).toBeFalsy();
  });

  it('anonymous (served by the agent, logged out): shows the login banner', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.login-banner')).toBeTruthy();
    expect(el.querySelector('a[href="/oauth2/authorization/keycloak"]')).toBeTruthy();
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
  });

  it('logged in: shows the live chat panel', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp({ username: 'alice', scopes: ['openid', 'profile'] });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-live-chat')?.textContent).toContain('alice');
    expect(el.querySelector('.login-banner')).toBeFalsy();
  });

  it('live: opening the SVID stage shows the current certificate chain', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp({ username: 'alice', scopes: ['openid'] });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-cert-panel')).toBeFalsy();
    Array.from(el.querySelectorAll<HTMLButtonElement>('.step'))
      .find((b) => b.textContent?.includes('Agent fetches SVIDs'))
      ?.click();
    await fixture.whenStable();
    await fixture.whenStable();
    expect(el.querySelector('dc-cert-panel')?.textContent).toContain('serial ab12');
    expect(el.querySelector('dc-custody-panel')).toBeTruthy();
  });

  it('offline: the SVID stage shows only the captured custody panel', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp('offline');
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.step'))
      .find((b) => b.textContent?.includes('Agent fetches SVIDs'))
      ?.click();
    await fixture.whenStable();
    await fixture.whenStable();
    expect(el.querySelector('dc-cert-panel')).toBeFalsy();
    expect(el.querySelector('dc-custody-panel')).toBeTruthy();
  });

  it('clicking a live hop opens the matching stage detail', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderApp({ username: 'alice', scopes: ['openid'] });
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.hop'))
      .find((b) => b.textContent?.includes('02'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('.stage h3')?.textContent).toContain('Agent fetches SVIDs');
    expect(el.querySelector('dc-custody-panel')).toBeTruthy();
  });
});
