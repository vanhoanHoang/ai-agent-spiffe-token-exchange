import { provideRouter } from '@angular/router';
import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

import { LiveClient, LiveState } from '../../core/live';
import { demoRunFixture } from '../../core/testing/fixture';
import { ConsolePage } from './console-page';

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

async function renderPage(live: LiveState = 'offline') {
  await TestBed.configureTestingModule({
    imports: [ConsolePage],
    providers: [
      provideRouter([{ path: '**', children: [] }]),
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
  const fixture = TestBed.createComponent(ConsolePage);
  await fixture.whenStable();
  return fixture;
}

describe('ConsolePage', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('renders the full run from a valid capture', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent).toContain('Two identities, one call');
    expect(el.textContent).toContain('spiffe://lab.internal');
    expect(el.querySelectorAll('dc-step-rail').length).toBe(1);
    expect(el.querySelectorAll('dc-rejection-grid').length).toBe(1);
  });

  it('tabs: rejections by default, server log after switching', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage();
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
    const fixture = await renderPage();
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
    const fixture = await renderPage();
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
    const fixture = await renderPage();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.error-state')).toBeTruthy();
    expect(el.querySelector('dc-run-header')).toBeFalsy();
  });

  it('anonymous (guest mode): shows the recorded-evidence note with a sign-in link', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.guest-note')?.textContent).toContain('Sign in');
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
  });

  it('offline: no live panel and no guest note', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage('offline');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
    expect(el.querySelector('.guest-note')).toBeFalsy();
  });

  it('logged in: shows the live chat panel', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid', 'profile'] });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-live-chat')?.textContent).toContain('alice');
    expect(el.querySelector('.guest-note')).toBeFalsy();
  });

  it('live: opening the SVID stage shows the current certificate chain', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
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

  it('clicking a live hop opens the matching stage detail', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.hop'))
      .find((b) => b.textContent?.includes('02'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('.stage h3')?.textContent).toContain('Agent fetches SVIDs');
    expect(el.querySelector('dc-custody-panel')).toBeTruthy();
  });
});
