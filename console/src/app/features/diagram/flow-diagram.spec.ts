import { TestBed } from '@angular/core/testing';

import { FlowDiagram } from './flow-diagram';

describe('FlowDiagram', () => {
  async function render(stage: string) {
    await TestBed.configureTestingModule({ imports: [FlowDiagram] }).compileComponents();
    const fixture = TestBed.createComponent(FlowDiagram);
    fixture.componentRef.setInput('stage', stage);
    await fixture.whenStable();
    return fixture;
  }

  it('renders the six architecture nodes', async () => {
    const fixture = await render('login');
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    for (const n of ['alice', 'Keycloak', 'agent-client', 'SPIRE Server', 'Lab Root CA', 'MCP server']) {
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
});
