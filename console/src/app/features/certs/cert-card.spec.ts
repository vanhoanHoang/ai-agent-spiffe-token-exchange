import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';

import { LiveCert } from '../../core/live';
import { CertCard } from './cert-card';

const LEAF: LiveCert = {
  role: 'leaf',
  subject: 'CN=antoine,O=eviden',
  issuer: 'CN=Eviden Root CA,O=eviden',
  serial: '790586A98B7E5D76',
  notBefore: '2026-09-10T23:07:04Z',
  notAfter: '2028-09-09T23:07:03Z',
  uriSans: [],
  sha256: '91d4ce88'.repeat(8),
  details: {
    version: 3,
    signatureAlgorithm: 'SHA256withECDSA',
    publicKey: 'EC, 256 bit (P-256)',
    extensions: [{ oid: '2.5.29.19', name: 'Basic Constraints', critical: true, value: 'CA:FALSE' }],
  },
};

const ROOT: LiveCert = {
  role: 'trust-anchor',
  subject: 'CN=Eviden Root CA,O=eviden',
  issuer: 'CN=Eviden Root CA,O=eviden',
  serial: '01',
  notBefore: '2026-01-01T00:00:00Z',
  notAfter: '2036-01-01T00:00:00Z',
  uriSans: [],
  sha256: 'cafe0123'.repeat(8),
};

/** A host so inputs can be driven the way the page drives them. */
@Component({
  imports: [CertCard],
  template: `<dc-cert-card
    [kicker]="kicker"
    [lead]="lead"
    [cert]="cert"
    [chain]="chain()"
    [pem]="pem()"
    [downloadHref]="href()"
    [downloadName]="name()"
  />`,
})
class Host {
  kicker = 'Issued certificate · antoine';
  lead = 'Signed by the corporate CA at the end of the chain.';
  cert = LEAF;
  chain = signal<readonly LiveCert[]>([LEAF, ROOT]);
  pem = signal<string | null>('-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n');
  href = signal<string | null>('/api/issued/download');
  name = signal<string | null>('antoine.pem');
}

async function render() {
  await TestBed.configureTestingModule({ imports: [Host] }).compileComponents();
  const fixture = TestBed.createComponent(Host);
  await fixture.whenStable();
  return { fixture, el: fixture.nativeElement as HTMLElement, host: fixture.componentInstance };
}

describe('CertCard', () => {
  it('renders the kicker, the lead and the openssl view', async () => {
    const { el } = await render();
    expect(el.querySelector('.bar')?.textContent).toContain('Issued certificate · antoine');
    expect(el.querySelector('.lead')?.textContent).toContain('corporate CA');
    // One renderer for every certificate on the page, not a second layout.
    expect(el.querySelector('dc-cert-detail')?.textContent).toContain('Serial Number:');
  });

  it('lists the chain and offers the PEM and the download', async () => {
    const { el } = await render();
    const chain = el.querySelector('details.chain');
    expect(chain?.querySelector('summary')?.textContent).toContain('chain (2)');
    const rows = Array.from(chain?.querySelectorAll('li') ?? []).map((li) => li.textContent ?? '');
    expect(rows[0]).toContain('leaf');
    expect(rows[0]).toContain('antoine');
    expect(rows[1]).toContain('trust-anchor');
    expect(rows[1]).toContain('Eviden Root CA');
    expect(el.querySelector('details.pem pre')?.textContent).toContain('BEGIN CERTIFICATE');
    const dl = el.querySelector<HTMLAnchorElement>('a.download');
    expect(dl?.getAttribute('href')).toBe('/api/issued/download');
    expect(dl?.getAttribute('download')).toBe('antoine.pem');
  });

  it('with a lone certificate and no PEM: no chain, no PEM, no download — and never a key', async () => {
    const { fixture, el, host } = await render();
    host.chain.set([LEAF]);
    host.pem.set(null);
    host.href.set(null);
    host.name.set(null);
    await fixture.whenStable();
    expect(el.querySelector('details.chain')).toBeNull();
    expect(el.querySelector('details.pem')).toBeNull();
    expect(el.querySelector('a.download')).toBeNull();
    expect(el.querySelector('dc-cert-detail')?.textContent).toContain('antoine');
    expect(el.textContent).not.toContain('PRIVATE KEY');
  });
});
