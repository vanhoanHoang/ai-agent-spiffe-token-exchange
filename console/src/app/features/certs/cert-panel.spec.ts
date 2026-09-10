import { TestBed } from '@angular/core/testing';

import { DemoToken } from '../../core/demo-run';
import { LiveSvid } from '../../core/live';
import { CertPanel } from './cert-panel';

const SVID: LiveSvid = {
  spiffeId: 'spiffe://ai-agent.id.eviden.internal/agent-client',
  chain: [
    {
      role: 'leaf',
      subject: 'CN=agent-client,O=lab',
      issuer: 'CN=SPIRE Intermediate CA,O=lab',
      serial: 'ab12cd',
      notBefore: '2026-07-31T10:00:00Z',
      notAfter: '2026-07-31T11:00:00Z',
      uriSans: ['spiffe://ai-agent.id.eviden.internal/agent-client'],
      sha256: 'deadbeef'.repeat(8),
      details: {
        version: 3,
        signatureAlgorithm: 'SHA256withECDSA',
        publicKey: 'EC, 256 bit (P-256)',
        extensions: [
          {
            oid: '2.5.29.17',
            name: 'Subject Alternative Name',
            critical: false,
            value: 'URI:spiffe://ai-agent.id.eviden.internal/agent-client',
          },
        ],
      },
    },
    {
      role: 'intermediate',
      subject: 'CN=SPIRE Intermediate CA,O=eviden',
      issuer: 'CN=Eviden Root CA,O=eviden',
      serial: '02',
      notBefore: '2026-01-01T00:00:00Z',
      notAfter: '2028-01-01T00:00:00Z',
      uriSans: [],
      sha256: 'beef0123'.repeat(8),
      details: {
        version: 3,
        signatureAlgorithm: 'SHA256withECDSA',
        publicKey: 'EC, 256 bit (P-256)',
        extensions: [
          {
            oid: '2.5.29.30',
            name: 'Name Constraints',
            critical: true,
            value: 'Permitted: URI:ai-agent.id.eviden.internal',
          },
        ],
      },
    },
    {
      role: 'trust-anchor',
      subject: 'CN=Eviden Root CA,O=eviden',
      issuer: 'CN=Eviden Root CA,O=eviden',
      serial: '01',
      notBefore: '2026-01-01T00:00:00Z',
      notAfter: '2036-01-01T00:00:00Z',
      uriSans: [],
      sha256: 'cafe0123'.repeat(8),
    },
  ],
};

const JWT: DemoToken = {
  name: 'JWT-SVID',
  description: 'The same workload, as a signed claim set.',
  header: { alg: 'ES256', typ: 'JWT' },
  claims: {
    sub: 'spiffe://ai-agent.id.eviden.internal/agent-client',
    aud: ['http://keycloak:8080/realms/ai-agents'],
    exp: 1790000000,
  },
  signature: 'REDACTED',
};

async function render(jwt: DemoToken | null = JWT) {
  await TestBed.configureTestingModule({ imports: [CertPanel] }).compileComponents();
  const fixture = TestBed.createComponent(CertPanel);
  fixture.componentRef.setInput('svid', SVID);
  fixture.componentRef.setInput('jwt', jwt);
  await fixture.whenStable();
  return fixture;
}

describe('CertPanel', () => {
  it('renders the X.509-SVID card: the leaf in the openssl view', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    const card = el.querySelector('dc-cert-card');
    expect(card?.querySelector('.bar')?.textContent).toContain('X.509-SVID · agent-client');
    expect(card?.querySelector('.lead')?.textContent).toContain(
      'spiffe://ai-agent.id.eviden.internal/agent-client',
    );
    expect(card?.querySelector('dc-cert-detail')?.textContent).toContain('Serial Number: ab12cd');
    expect(card?.querySelector('dc-cert-detail')?.textContent).toContain(
      'URI:spiffe://ai-agent.id.eviden.internal/agent-client',
    );
  });

  it('lists the chain with the intermediate name constraint on its line', async () => {
    const fixture = await render();
    const card = (fixture.nativeElement as HTMLElement).querySelector('dc-cert-card');
    const rows = Array.from(card?.querySelectorAll('details.chain li') ?? []).map((li) => li.textContent ?? '');
    expect(rows.length).toBe(3);
    expect(rows[1]).toContain('SPIRE Intermediate CA');
    // The demo's technical control stays visible without opening anything else.
    expect(rows[1]).toContain('Permitted: URI:ai-agent.id.eviden.internal');
    expect(rows[2]).toContain('Eviden Root CA');
    expect(rows[2]).toContain('self-signed');
  });

  it('shows the rotation countdown in the lead line', async () => {
    const fixture = await render();
    const lead = (fixture.nativeElement as HTMLElement).querySelector('.lead')?.textContent ?? '';
    expect(lead).toContain('Expires in');
    expect(lead).toContain('rotation expected in about');
  });

  it('emits reload when refresh is clicked', async () => {
    const fixture = await render();
    let reloaded = false;
    fixture.componentInstance.reload.subscribe(() => (reloaded = true));
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.reload')?.click();
    expect(reloaded).toBe(true);
  });

  it('renders the JWT-SVID as decoded claims in the token card — never a token', async () => {
    const fixture = await render();
    const jwt = (fixture.nativeElement as HTMLElement).querySelector('dc-token-card');
    expect(jwt?.textContent).toContain('JWT-SVID');
    expect(jwt?.textContent).toContain('spiffe://ai-agent.id.eviden.internal/agent-client');
    expect(jwt?.textContent).toContain('http://keycloak:8080/realms/ai-agents');
    expect(jwt?.textContent).toContain('redacted');
    expect(jwt?.textContent).not.toMatch(/[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/);
  });

  it('without a JWT-SVID: the X.509 card alone, no empty token card', async () => {
    const fixture = await render(null);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-cert-card')).toBeTruthy();
    expect(el.querySelector('dc-token-card')).toBeNull();
    expect(el.textContent).not.toContain('PRIVATE KEY');
  });
});
