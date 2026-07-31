import { TestBed } from '@angular/core/testing';

import { LiveSvid } from '../../core/live';
import { CertPanel } from './cert-panel';

const SVID: LiveSvid = {
  spiffeId: 'spiffe://lab.internal/agent-client',
  chain: [
    {
      role: 'leaf',
      subject: 'CN=agent-client,O=lab',
      issuer: 'CN=SPIRE Intermediate CA,O=lab',
      serial: 'ab12cd',
      notBefore: '2026-07-31T10:00:00Z',
      notAfter: '2026-07-31T11:00:00Z',
      uriSans: ['spiffe://lab.internal/agent-client'],
      sha256: 'deadbeef'.repeat(8),
      details: {
        version: 3,
        signatureAlgorithm: 'SHA256withECDSA',
        publicKey: 'EC, 256 bit (P-256)',
        extensions: [
          { oid: '2.5.29.15', name: 'Key Usage', critical: true, value: 'Digital Signature' },
          {
            oid: '2.5.29.17',
            name: 'Subject Alternative Name',
            critical: false,
            value: 'URI:spiffe://lab.internal/agent-client',
          },
        ],
      },
    },
    {
      role: 'trust-anchor',
      subject: 'CN=Lab Root CA,O=lab',
      issuer: 'CN=Lab Root CA,O=lab',
      serial: '01',
      notBefore: '2026-01-01T00:00:00Z',
      notAfter: '2036-01-01T00:00:00Z',
      uriSans: [],
      sha256: 'cafe0123'.repeat(8),
      details: {
        version: 3,
        signatureAlgorithm: 'SHA256withECDSA',
        publicKey: 'EC, 256 bit (P-256)',
        extensions: [
          {
            oid: '2.5.29.30',
            name: 'Name Constraints',
            critical: true,
            value: 'Permitted: URI:lab.internal',
          },
        ],
      },
    },
  ],
};

async function render() {
  await TestBed.configureTestingModule({ imports: [CertPanel] }).compileComponents();
  const fixture = TestBed.createComponent(CertPanel);
  fixture.componentRef.setInput('svid', SVID);
  await fixture.whenStable();
  return fixture;
}

describe('CertPanel', () => {
  it('renders the live chain: SPIFFE ID, URI SAN, serial, validity, issuer CN', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.id')?.textContent).toContain('spiffe://lab.internal/agent-client');
    expect(el.querySelectorAll('.cert').length).toBe(2);
    expect(el.textContent).toContain('URI SAN: spiffe://lab.internal/agent-client');
    expect(el.textContent).toContain('serial ab12cd');
    expect(el.textContent).toContain('issued by SPIRE Intermediate CA');
    expect(el.textContent).toContain('Lab Root CA');
  });

  it('emits reload when refresh is clicked', async () => {
    const fixture = await render();
    let reloaded = false;
    fixture.componentInstance.reload.subscribe(() => (reloaded = true));
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.reload')?.click();
    expect(reloaded).toBe(true);
  });

  it('shows the rotation countdown line for the leaf', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.rotation')?.textContent).toContain('leaf expires in');
    expect(el.querySelector('.rotation')?.textContent).toContain('rotation expected in');
  });

  it('expands a certificate into the full openssl-style detail', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('dc-cert-detail')).toBeFalsy();

    Array.from(el.querySelectorAll<HTMLButtonElement>('.expand')).at(-1)?.click();
    await fixture.whenStable();
    const detail = el.querySelector('dc-cert-detail');
    expect(detail?.textContent).toContain('Signature Algorithm: SHA256withECDSA');
    expect(detail?.textContent).toContain('Name Constraints (critical):');
    expect(detail?.textContent).toContain('Permitted: URI:lab.internal');
    expect(detail?.textContent).toContain('Fingerprint (SHA-256):');
  });
});
