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
          // The certificate the chain produced (D-036). Public material only:
          // there is no key field to assert, because none is ever issued out.
          issued: () =>
            Promise.resolve({
              role: 'employee device',
              subject: 'CN=john-laptop,O=eviden',
              issuer: 'CN=Eviden Issuing CA,O=eviden',
              serial: '4B2F9C11E07A35D8',
              notBefore: '2026-08-04T07:00:00Z',
              notAfter: '2028-08-03T07:00:00Z',
              uriSans: [],
              sha256: 'ab'.repeat(32),
              pem: '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n',
            }),
          // A two-hop chain, as the agent streams it (M12/D-032): one
          // svid+exchange pair per hop, each followed by its tool call.
          chatStream: (_m: string, onEvent: (s: string, d: string) => void) => {
            const chain: readonly [string, string][] = [
              ['svid', 'JWT-SVID for agent-client'],
              ['exchange', 'act.sub=agent-client aud=agent-pki'],
              ['tool', 'onboard_employee'],
              ['svid', 'JWT-SVID for agent-pki'],
              ['exchange', 'act nests: agent-pki over agent-client'],
              ['tool', 'issue_employee_cert'],
            ];
            for (const [s, d] of chain) {
              onEvent(s, d);
            }
            return Promise.resolve({ answer: 'Certificate issued for john-laptop.' });
          },
          svid: () =>
            Promise.resolve({
              spiffeId: 'spiffe://ai-agent.id.eviden.internal/agent-client',
              chain: [
                {
                  role: 'leaf',
                  subject: 'CN=agent-client',
                  issuer: 'CN=SPIRE Intermediate CA',
                  serial: 'ab12',
                  notBefore: '2026-07-31T10:00:00Z',
                  notAfter: '2026-07-31T11:00:00Z',
                  uriSans: ['spiffe://ai-agent.id.eviden.internal/agent-client'],
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
    expect(el.textContent).toContain('spiffe://ai-agent.id.eviden.internal');
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

  it('anonymous: defaults to the recorded view with the provenance banner', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.provenance')?.textContent).toContain('not your session');
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
  });

  it('anonymous: the Live tab asks for sign-in instead of showing recorded data', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.vtab'))
      .find((b) => b.textContent?.includes('Live session'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('.guest-note')?.textContent).toContain('Sign in');
    expect(el.querySelector('dc-token-card')).toBeFalsy();
    expect(el.querySelector('.provenance')).toBeFalsy();
  });

  it('logged in: defaults to the live view with chat and NO captured artifacts', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid', 'profile'] });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-live-chat')?.textContent).toContain('alice');
    expect(el.querySelector('dc-token-card')).toBeFalsy();
    expect(el.querySelector('.awaiting')).toBeTruthy();
    expect(el.querySelector('.provenance')).toBeFalsy();
  });

  it('logged in: switching to the recorded tab shows the captured run under the banner', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.vtab'))
      .find((b) => b.textContent?.includes('Recorded run'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('.provenance')).toBeTruthy();
    expect(el.querySelector('dc-token-card')?.textContent).toContain("Alice's login token");
    expect(el.querySelector('dc-live-chat')).toBeFalsy();
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
    expect(el.querySelector('dc-custody-panel')).toBeFalsy();
  });

  async function runLiveChain(fixture: Awaited<ReturnType<typeof renderPage>>) {
    const el = fixture.nativeElement as HTMLElement;
    const box = el.querySelector<HTMLInputElement>('.box');
    box!.value = 'onboard John, he starts Monday';
    el.querySelector<HTMLButtonElement>('.go')?.click();
    await fixture.whenStable();
    await fixture.whenStable();
    return el;
  }

  it('follows the live chain onto the diagram, widening it to the second hop', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
    const el = await runLiveChain(fixture);
    // The chain delegated, so the trace splits and the diagram reaches the
    // issuance edge — scenery a single-hop run must never light.
    expect(el.querySelectorAll('.hopgroup').length).toBe(2);
    expect(el.querySelector('#p-issue')?.classList.contains('on')).toBe(true);
    expect(el.querySelector('#p-call')?.classList.contains('on')).toBe(false);
  });

  it('shows the issued certificate with an openssl-style view and a download', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
    const el = await runLiveChain(fixture);
    const panel = el.querySelector('dc-issued-cert');
    expect(panel).not.toBeNull();
    expect(panel?.textContent).toContain('john-laptop');
    // The openssl layout, not a bespoke second renderer.
    expect(panel?.querySelector('dc-cert-detail')?.textContent).toContain('Serial Number:');
    const dl = panel?.querySelector<HTMLAnchorElement>('a.download');
    expect(dl?.getAttribute('href')).toBe('/api/issued/download');
    expect(dl?.getAttribute('download')).toBe('john-laptop.pem');
    // A certificate is public; a key never is. Nothing key-shaped may appear.
    expect(panel?.textContent).not.toContain('PRIVATE KEY');
  });

  it('clicking a step in the live trace opens the matching stage detail', async () => {
    mockFetch(demoRunFixture());
    const fixture = await renderPage({ username: 'alice', scopes: ['openid'] });
    const el = await runLiveChain(fixture);
    Array.from(el.querySelectorAll<HTMLButtonElement>('.hopgroup[data-hop="1"] .tstep'))
      .find((b) => b.textContent?.includes('proved which workload'))
      ?.click();
    await fixture.whenStable();
    await fixture.whenStable();
    expect(el.querySelector('.stage h3')?.textContent).toContain('Agent fetches SVIDs');
    expect(el.querySelector('dc-cert-panel')).toBeTruthy();
  });
});
