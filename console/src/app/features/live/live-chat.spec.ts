import { TestBed } from '@angular/core/testing';

import { ChatResult, LiveClient } from '../../core/live';
import { LiveChat } from './live-chat';

type OnEvent = (step: string, detail: string) => void;

const AGENT_SVID = 'JWT-SVID minted for spiffe://ai-agent.id.eviden.internal/agent-client';
const PKI_SVID = 'JWT-SVID minted for spiffe://ai-agent.id.eviden.internal/agent-pki';

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

  it('traces a single-hop chain as one hop, and lands the answer', async () => {
    const fixture = await render({ answer: 'You are alice; I act as the agent.' }, [
      ['svid', AGENT_SVID],
      ['exchange', 'RFC 8693 exchange done'],
      ['tool', 'whoami'],
    ]);
    await sendMessage(fixture, 'who am I?');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('You are alice');
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('done');
    expect(el.querySelectorAll('.hopgroup').length).toBe(1);
    expect(el.querySelector('.hopactor')?.textContent).toContain('agent-client');
    expect(el.textContent).toContain('whoami');
    // One hop is not delegation — the note must stay off.
    expect(el.querySelector('.delegnote')).toBeNull();
  });

  it('splits a two-hop chain into two groups and names the second workload', async () => {
    const fixture = await render({ answer: 'Certificate issued for john-laptop.' }, [
      ['svid', AGENT_SVID],
      ['exchange', 'act.sub=agent-client aud=agent-pki'],
      ['tool', 'onboard_employee'],
      ['svid', PKI_SVID],
      ['exchange', 'act nests: agent-pki over agent-client'],
      ['tool', 'issue_employee_cert'],
    ]);
    await sendMessage(fixture, 'onboard John, he starts Monday');
    const el = fixture.nativeElement as HTMLElement;
    const groups = el.querySelectorAll('.hopgroup');
    expect(groups.length).toBe(2);
    expect(groups[0].textContent).toContain('agent-client');
    expect(groups[1].textContent).toContain('agent-pki');
    expect(groups[1].getAttribute('data-hop')).toBe('2');
    expect(el.querySelector('.delegnote')).not.toBeNull();
  });

  it('reports the stage each event reached, so the diagram can follow the chain', async () => {
    const fixture = await render({ answer: 'done' }, [
      ['svid', AGENT_SVID],
      ['exchange', 'hop 1'],
      ['tool', 'onboard_employee'],
      ['svid', PKI_SVID],
      ['exchange', 'hop 2'],
      ['tool', 'issue_employee_cert'],
    ]);
    const seen: string[] = [];
    fixture.componentInstance.reached.subscribe((s: string) => seen.push(s));
    await sendMessage(fixture, 'onboard John');
    expect(seen).toEqual(['svid', 'exchange', 'call', 'svid2', 'exchange2', 'issue']);
  });

  it('shows the refusal in the thread when the chain is denied', async () => {
    const fixture = await render({ error: 'exchange failed: HTTP 400' }, [['svid', AGENT_SVID]]);
    await sendMessage(fixture, 'break');
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.bubble.err')?.textContent).toContain('exchange failed');
    expect(el.querySelector('.panel')?.getAttribute('data-phase')).toBe('error');
  });

  it('warns when the consented scopes lack mcp:audit', async () => {
    const fixture = await render({ answer: 'x' });
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('no mcp:audit');
  });
});
