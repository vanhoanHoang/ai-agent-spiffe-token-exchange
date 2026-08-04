import { TestBed } from '@angular/core/testing';

import { FlowDiagram } from './flow-diagram';

describe('FlowDiagram', () => {
  async function render(stage: string, hops = 1) {
    await TestBed.configureTestingModule({ imports: [FlowDiagram] }).compileComponents();
    const fixture = TestBed.createComponent(FlowDiagram);
    fixture.componentRef.setInput('stage', stage);
    fixture.componentRef.setInput('hops', hops);
    await fixture.whenStable();
    return fixture;
  }

  it('renders every architecture node, both hops', async () => {
    const fixture = await render('login');
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    const nodes = [
      'alice',
      'Keycloak',
      'agent-client',
      'agent-pki',
      'cert-service',
      'SPIRE Server',
      'Eviden Root CA',
      'MCP server',
    ];
    for (const n of nodes) {
      expect(text).toContain(n);
    }
  });

  it('lights only the selected stage edges and their packets', async () => {
    const fixture = await render('exchange');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('#p-exch')?.classList.contains('on')).toBe(true);
    expect(el.querySelector('#p-login')?.classList.contains('on')).toBe(false);
    expect(el.querySelectorAll('.packet.on').length).toBeGreaterThan(0);
  });

  it('moves the lit edges when the stage changes', async () => {
    const fixture = await render('login');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('#p-login')?.classList.contains('on')).toBe(true);
    fixture.componentRef.setInput('stage', 'call');
    await fixture.whenStable();
    expect(el.querySelector('#p-login')?.classList.contains('on')).toBe(false);
    expect(el.querySelector('#p-call')?.classList.contains('on')).toBe(true);
  });

  // ── second hop (M12/D-032) ──

  it('sends the assistant to agent-pki instead of the MCP server once the chain has two hops', async () => {
    const fixture = await render('call', 2);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('#p-hand')?.classList.contains('on')).toBe(true);
    expect(el.querySelector('#p-call')?.classList.contains('on')).toBe(false);
  });

  it('lights the second exchange and the issuance only at their own stages', async () => {
    const fixture = await render('exchange2', 2);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('#p-exch2')?.classList.contains('on')).toBe(true);
    expect(el.querySelector('#p-issue')?.classList.contains('on')).toBe(false);
    fixture.componentRef.setInput('stage', 'issue');
    await fixture.whenStable();
    expect(el.querySelector('#p-issue')?.classList.contains('on')).toBe(true);
  });

  // The negative is the point: an edge nobody can see proves nothing, so the
  // refused path must be in the DOM even while it is not the selected stage.
  it('draws the refused agent-client to cert-service path at all times', async () => {
    const fixture = await render('login', 2);
    const el = fixture.nativeElement as HTMLElement;
    const forbidden = el.querySelector('#p-forbid');
    expect(forbidden).not.toBeNull();
    expect(forbidden?.classList.contains('on')).toBe(false);
    fixture.componentRef.setInput('stage', 'refused');
    await fixture.whenStable();
    expect(forbidden?.classList.contains('on')).toBe(true);
  });

  it('dims the workloads that took no part in the run', async () => {
    const oneHop = await render('call', 1);
    const el = oneHop.nativeElement as HTMLElement;
    // agent-pki and cert-service exist, but this run never reached them.
    expect(el.querySelectorAll('.node.dim').length).toBeGreaterThan(0);
    oneHop.componentRef.setInput('hops', 2);
    await oneHop.whenStable();
    // Now the MCP server is the bystander instead.
    const dimmedText = Array.from(el.querySelectorAll('.node.dim'))
      .map((n) => n.textContent ?? '')
      .join(' ');
    expect(dimmedText).toContain('MCP server');
    expect(dimmedText).not.toContain('agent-pki');
  });

  it('shows the scope each workload may hold', async () => {
    const fixture = await render('call', 2);
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('issue:employee-cert');
    expect(text).toContain('onboard:initiate');
  });
});
