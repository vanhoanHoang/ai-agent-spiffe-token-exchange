import { TestBed } from '@angular/core/testing';

import { ChatResult, LiveClient } from '../../core/live';
import { LiveChat } from './live-chat';

type OnEvent = (step: string, detail: string) => void;

describe('LiveChat', () => {
  async function render(
    result: ChatResult,
    events: readonly [string, string][] = [],
    scopes: string[] = ['openid', 'profile'],
  ) {
    await TestBed.configureTestingModule({
      imports: [LiveChat],
      providers: [
        {
          provide: LiveClient,
          useValue: {
            me: () => Promise.resolve('offline'),
            chatStream: (_m: string, onEvent: OnEvent) => {
              for (const [s, d] of events) {
                onEvent(s, d);
              }
              return Promise.resolve(result);
            },
          },
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

  it('streams real events: hops complete in order, feed shows details, answer lands', async () => {
    const fixture = await render({ answer: 'You are alice; I act as the agent.' }, [
      ['svid', 'JWT-SVID minted for spiffe://lab.internal/agent-client'],
      ['exchange', 'RFC 8693 exchange done'],
      ['tool', 'whoami'],
    ]);
    await sendMessage(fixture, 'who am I?');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('You are alice');
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('done');
    expect(el.querySelector('.hop.workload')?.getAttribute('data-s')).toBe('done');
    expect(el.querySelector('.hop.bridge')?.getAttribute('data-s')).toBe('done');
    expect(el.textContent).toContain('04 mTLS tool call · whoami');
    expect(el.querySelector('.feed')?.textContent).toContain('JWT-SVID minted');
  });

  it('marks the in-flight hop failed when the chain refuses', async () => {
    const fixture = await render({ error: 'exchange failed: HTTP 400' }, [
      ['svid', 'JWT-SVID minted for spiffe://lab.internal/agent-client'],
    ]);
    await sendMessage(fixture, 'break');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.bubble.err')?.textContent).toContain('exchange failed');
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('error');
    expect(el.querySelector('.hop.bridge')?.getAttribute('data-s')).toBe('failed');
  });

  it('warns when the consented scopes lack mcp:audit', async () => {
    const fixture = await render({ answer: 'x' });
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('no mcp:audit');
  });
});
