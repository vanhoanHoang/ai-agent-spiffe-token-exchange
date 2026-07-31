import { TestBed } from '@angular/core/testing';

import { demoRunFixture } from '../../core/testing/fixture';
import { TokenCard } from './token-card';

describe('TokenCard', () => {
  async function render(tokenName: string) {
    await TestBed.configureTestingModule({ imports: [TokenCard] }).compileComponents();
    const fixture = TestBed.createComponent(TokenCard);
    const token = demoRunFixture().tokens.find((t) => t.name === tokenName);
    fixture.componentRef.setInput('token', token);
    fixture.componentRef.setInput('role', 'bridge');
    fixture.componentRef.setInput('kicker', 'kicker');
    fixture.componentRef.setInput('title', 'title');
    await fixture.whenStable();
    return fixture;
  }

  it('flattens act to act.sub and always shows the redacted signature', async () => {
    const fixture = await render('exchanged_token');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('act.sub');
    expect(el.textContent).toContain('spiffe://lab.internal/agent-client');
    expect(el.textContent).toContain('…redacted…');
  });

  it('expands to all claims on toggle', async () => {
    const fixture = await render('subject_token');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).not.toContain('iss');
    el.querySelector<HTMLButtonElement>('.toggle')?.click();
    await fixture.whenStable();
    expect(el.textContent).toContain('iss');
    expect(el.textContent).toContain('http://keycloak:8080/realms/lab');
  });
});
