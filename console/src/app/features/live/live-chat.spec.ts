import { TestBed } from '@angular/core/testing';

import { ChatResult, LiveClient } from '../../core/live';
import { LiveChat } from './live-chat';

describe('LiveChat', () => {
  async function render(result: ChatResult, scopes: string[] = ['openid', 'profile']) {
    await TestBed.configureTestingModule({
      imports: [LiveChat],
      providers: [
        {
          provide: LiveClient,
          useValue: { me: () => Promise.resolve('offline'), chat: () => Promise.resolve(result) },
        },
      ],
    }).compileComponents();
    const fixture = TestBed.createComponent(LiveChat);
    fixture.componentRef.setInput('user', { username: 'alice', scopes });
    await fixture.whenStable();
    return fixture;
  }

  async function sendMessage(fixture: Awaited<ReturnType<typeof render>>, text: string) {
    const el = fixture.nativeElement as HTMLElement;
    const box = el.querySelector<HTMLInputElement>('.box');
    box!.value = text;
    el.querySelector<HTMLButtonElement>('.go')?.click();
    await fixture.whenStable();
    await fixture.whenStable();
  }

  it('sends a message and renders the answer; flow ends done', async () => {
    const fixture = await render({ answer: 'You are alice; I act as the agent.' });
    await sendMessage(fixture, 'who am I?');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('You are alice');
    expect(el.querySelector('.a.err')).toBeFalsy();
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('done');
  });

  it('renders an error turn when the chain refuses; flow marks the call failed', async () => {
    const fixture = await render({ error: 'exchange failed: HTTP 400' });
    await sendMessage(fixture, 'break');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.a.err')?.textContent).toContain('exchange failed');
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('error');
  });

  it('warns when the consented scopes lack mcp:audit', async () => {
    const fixture = await render({ answer: 'x' });
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('no mcp:audit');
  });
});
