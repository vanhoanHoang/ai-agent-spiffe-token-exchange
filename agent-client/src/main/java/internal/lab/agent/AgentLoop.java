package internal.lab.agent;

import java.util.Arrays;
import java.util.Set;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import internal.lab.delegation.DelegatedExchange;
import io.modelcontextprotocol.client.McpSyncClient;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ToolContext;
import org.springframework.ai.mcp.McpToolNamePrefixGenerator;
import org.springframework.ai.mcp.SyncMcpToolCallbackProvider;
import org.springframework.ai.tool.ToolCallback;
import org.springframework.ai.tool.definition.ToolDefinition;
import org.springframework.ai.tool.metadata.ToolMetadata;
import org.springframework.stereotype.Component;

/**
 * The M10 agentic loop. The model decides WHAT tool to call; the SVID ->
 * exchange -> mTLS path decides AS WHOM. This class sees only the
 * provider-neutral {@link ChatModel}/{@link ChatClient} — the provider is a
 * starter dependency plus properties, never code.
 *
 * Everything token-shaped is per message (P2.5 rule): exchange with the
 * subject token as argument, bearer scoped to this call via
 * {@link BearerHolder}, nothing cached across messages.
 */
@Component
public class AgentLoop {

    /**
     * agent-pki reports the hop it performed; this is how we recognise it.
     * Nothing is emitted unless the PKI agent actually said it acted (D-034).
     *
     * The quotes may arrive escaped: the tool's result is JSON that itself
     * travels inside a JSON text content, so the same field reads as
     * {@code "actor":"..."} or {@code \"actor\":\"..."} depending on how many
     * layers the SDK has peeled. Tolerate both rather than depend on it.
     */
    private static final Pattern HOP2_ACTOR =
            Pattern.compile("\\\\?\"actor\\\\?\"\\s*:\\s*\\\\?\"(spiffe://[^\"\\\\]+/agent-pki)");
    private static final Pattern HOP2_SCOPE =
            Pattern.compile("\\\\?\"scope\\\\?\"\\s*:\\s*\\\\?\"([^\"\\\\]*:[^\"\\\\]*)");

    private final ChatModel chatModel;
    private final McpSyncClient mcp;
    private final McpSyncClient pki;
    private final TokenExchange exchange;
    private final BearerHolder bearer;
    private final IssuedCertHolder issued;
    private boolean mcpInitialized;

    /**
     * M15 consent-on-demand (D-038): the tool that opens the delegation chain,
     * and the scopes that chain needs end to end. When the model picks that
     * tool and the human never granted those scopes, the call is refused
     * BEFORE anything runs — no half-done side effects — with a `consent`
     * step naming what is missing. Identity-only questions (whoami, audit)
     * never hit this wall. UX preflight, not enforcement: the AS refuses an
     * unconsented exchange regardless (D-031/D-033).
     */
    private final String chainTool;
    private final Set<String> chainScopes;

    AgentLoop(ChatModel chatModel,
            @Qualifier("mcpSyncClient") McpSyncClient mcp,
            @Qualifier("pkiMcpClient") McpSyncClient pki,
            TokenExchange exchange, BearerHolder bearer, IssuedCertHolder issued) {
        this.chatModel = chatModel;
        this.mcp = mcp;
        this.pki = pki;
        this.exchange = exchange;
        this.bearer = bearer;
        this.issued = issued;
        this.chainTool = System.getenv().getOrDefault("CHAIN_TOOL", "onboard_employee");
        this.chainScopes = Arrays.stream(System.getenv()
                        .getOrDefault("CHAIN_REQUIRED_SCOPES", "onboard:initiate issue:employee-cert")
                        .split("[ ,]+"))
                .filter(s -> !s.isBlank())
                .collect(Collectors.toUnmodifiableSet());
    }

    /** The chain scopes the human has NOT granted this session (empty = all set). */
    private String missingScopes(String subjectToken) {
        Set<String> granted = Arrays.stream(DelegatedExchange.delegatedScope(subjectToken).split("\\s+"))
                .collect(Collectors.toUnmodifiableSet());
        return chainScopes.stream()
                .filter(s -> !granted.contains(s))
                .sorted()
                .reduce((a, b) -> a + " " + b)
                .orElse("");
    }

    String ask(String subjectToken, String userMessage) throws Exception {
        return ask(subjectToken, userMessage, e -> { });
    }

    /** Same loop, narrated: emits each REAL step (svid, exchange, every tool
     *  call) as it completes — the P6.1 live display. Labels only, no tokens. */
    String ask(String subjectToken, String userMessage, Consumer<StepEvent> events) throws Exception {
        String missing = missingScopes(subjectToken);
        bearer.set(exchange.exchange(subjectToken, events));
        try {
            ensureMcpInitialized();
            var tools = SyncMcpToolCallbackProvider.builder()
                    .mcpClients(mcp, pki)
                    .toolNamePrefixGenerator(McpToolNamePrefixGenerator.noPrefix())
                    .build();
            ToolCallback[] narrated = Arrays.stream(tools.getToolCallbacks())
                    .map(t -> narrating(t, events, issued, chainTool, missing))
                    .toArray(ToolCallback[]::new);
            String answer = ChatClient.builder(chatModel)
                    .defaultToolCallbacks(narrated)
                    .build()
                    .prompt()
                    .system("You are Eviden's agent assistant. Use the MCP tools available to you to "
                            + "answer questions about identity, state, or audit history. "
                            + "To onboard a new employee, call onboard_employee with their device "
                            + "name — you cannot issue certificates yourself, the PKI agent does "
                            + "that, and calling the tool is how you delegate to it. "
                            + "Never describe steps you did not actually perform with a tool. "
                            + "If a tool call is refused, report the refusal honestly.")
                    .user(userMessage)
                    .call()
                    .content();
            if (answer == null || answer.isBlank()) {
                throw new IllegalStateException("model returned no content");
            }
            return answer;
        }
        finally {
            bearer.clear();
        }
    }

    /** MCP initialize needs a bearer in scope, so it is lazy — first message. */
    private synchronized void ensureMcpInitialized() {
        if (!mcpInitialized) {
            mcp.initialize();
            pki.initialize();
            mcpInitialized = true;
        }
    }

    /**
     * Relay the second hop to the live display, from what the PKI agent
     * REPORTED about itself (its {@code hop2} block). This agent never
     * witnesses that exchange — it happens inside another workload — so
     * nothing is emitted unless agent-pki said it acted. A console that
     * narrated an unwitnessed hop would be showing a plausible lie.
     *
     * Emitted as a fresh svid/exchange/tool triple, which is exactly what the
     * console's hop attribution reads as a new hop (console/core/hops.ts).
     */
    private static void relayReportedHop(String toolResult, Consumer<StepEvent> events) {
        if (toolResult == null) {
            return;
        }
        Matcher actor = HOP2_ACTOR.matcher(toolResult);
        if (!actor.find()) {
            return;
        }
        String id = actor.group(1);
        Matcher scope = HOP2_SCOPE.matcher(toolResult);
        String granted = scope.find() ? scope.group(1) : "(scope not reported)";
        events.accept(new StepEvent("svid",
                "JWT-SVID minted for " + id + " — a different workload, proving its own identity"));
        events.accept(new StepEvent("exchange",
                "RFC 8693 exchange done: act nests " + id + " over the assistant, scope=" + granted));
        events.accept(new StepEvent("tool", "issue_employee_cert"));
    }

    /** Wraps a tool callback so the REAL invocation (the model's decision,
     *  going out over mTLS with the exchanged bearer) is announced — and so
     *  the chain-opening tool hits the consent wall when scopes are missing. */
    private static ToolCallback narrating(ToolCallback delegate, Consumer<StepEvent> events,
            IssuedCertHolder issued, String chainTool, String missingScopes) {
        return new ToolCallback() {
            @Override
            public ToolDefinition getToolDefinition() {
                return delegate.getToolDefinition();
            }

            @Override
            public ToolMetadata getToolMetadata() {
                return delegate.getToolMetadata();
            }

            /** Non-null = the wall: the tool never runs, the console gets the
             *  `consent` step, the model gets an honest refusal to relay. */
            private String consentWall() {
                if (missingScopes.isEmpty() || !delegate.getToolDefinition().name().equals(chainTool)) {
                    return null;
                }
                events.accept(new StepEvent("consent", missingScopes));
                return "REFUSED: consent_required. This task needs the human's approval for: "
                        + missingScopes + ". Tell the user you cannot proceed until they approve "
                        + "— their approval prompt is already on screen. Do not retry.";
            }

            @Override
            public String call(String toolInput) {
                String wall = consentWall();
                if (wall != null) {
                    return wall;
                }
                events.accept(new StepEvent("tool", delegate.getToolDefinition().name()));
                String result = delegate.call(toolInput);
                relayReportedHop(result, events);
                return issued.captureFrom(result);
            }

            @Override
            public String call(String toolInput, ToolContext toolContext) {
                String wall = consentWall();
                if (wall != null) {
                    return wall;
                }
                events.accept(new StepEvent("tool", delegate.getToolDefinition().name()));
                String result = delegate.call(toolInput, toolContext);
                relayReportedHop(result, events);
                return issued.captureFrom(result);
            }
        };
    }
}
