import { provideRouter } from '@angular/router';
import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';

import { App } from './app';
import { LiveClient, LiveState } from './core/live';

async function renderShell(live: LiveState) {
  await TestBed.configureTestingModule({
    imports: [App],
    providers: [
      provideRouter([{ path: '**', children: [] }]),
      { provide: LiveClient, useValue: { me: () => Promise.resolve(live) } },
    ],
  }).compileComponents();
  const fixture = TestBed.createComponent(App);
  await fixture.whenStable();
  return fixture;
}

describe('App shell', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('shows the brand and trust domain; no session controls when logged out', async () => {
    const fixture = await renderShell('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.brand')?.textContent).toContain('Identity Console');
    expect(el.querySelector('.env')?.textContent).toContain('spiffe://ai-agent.id.eviden.internal');
    expect(el.querySelector('.logout')).toBeFalsy();
  });

  it('shows the user and logout when signed in', async () => {
    const fixture = await renderShell({ username: 'alice', scopes: ['openid', 'profile'] });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.who')?.textContent).toContain('alice');
    expect(el.querySelector('.scopes')?.textContent).toContain('openid');
    expect(el.querySelector('.logout')).toBeTruthy();
  });
});
