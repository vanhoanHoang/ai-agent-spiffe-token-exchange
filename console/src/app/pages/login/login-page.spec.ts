import { Router, provideRouter } from '@angular/router';
import { TestBed } from '@angular/core/testing';

import { LiveClient, LiveState } from '../../core/live';
import { SessionService } from '../../core/session';
import { LoginPage } from './login-page';

async function renderLogin(live: LiveState) {
  await TestBed.configureTestingModule({
    imports: [LoginPage],
    providers: [
      provideRouter([{ path: '**', children: [] }]),
      { provide: LiveClient, useValue: { me: () => Promise.resolve(live) } },
    ],
  }).compileComponents();
  const fixture = TestBed.createComponent(LoginPage);
  await fixture.whenStable();
  return fixture;
}

describe('LoginPage', () => {
  it('anonymous: offers exactly one sign-in, identity only (no audit variant, no guest path)', async () => {
    const fixture = await renderLogin('anonymous');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('a[href="/oauth2/authorization/keycloak"]')).toBeTruthy();
    expect(el.querySelector('a[href="/oauth2/authorization/keycloak-audit"]')).toBeFalsy();
    expect(el.querySelector('.browse')).toBeFalsy();
    expect(el.querySelectorAll('.step').length).toBe(3);
    // Identity only: one link, no scope hint to read — the consent screen says the rest.
    expect(el.querySelector('.hint')).toBeNull();
  });

  it('offline: explains live mode is unavailable, offers the recorded evidence', async () => {
    const fixture = await renderLogin('offline');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('a[href="/oauth2/authorization/keycloak"]')).toBeFalsy();
    expect(el.textContent).toContain('live sign-in is unavailable');
    expect(el.querySelector('.btn.alt')).toBeTruthy();
  });

  it('guest path (offline only): sets guest mode and navigates to the console', async () => {
    const fixture = await renderLogin('offline');
    const session = TestBed.inject(SessionService);
    const router = TestBed.inject(Router);
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.btn.alt')?.click();
    await fixture.whenStable();
    expect(session.guest()).toBe(true);
    expect(router.url).toBe('/');
  });

  it('already signed in: redirects to the console', async () => {
    const fixture = await renderLogin({ username: 'alice', scopes: ['openid'] });
    await fixture.whenStable();
    expect(TestBed.inject(Router).url).toBe('/');
  });
});
