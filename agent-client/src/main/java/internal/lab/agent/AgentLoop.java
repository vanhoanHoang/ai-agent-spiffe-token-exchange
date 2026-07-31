package internal.lab.agent;

import io.modelcontextprotocol.client.McpSyncClient;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.mcp.McpToolNamePrefixGenerator;
import org.springframework.ai.mcp.SyncMcpToolCallbackProvider;
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

    private final ChatModel chatModel;
    private final McpSyncClient mcp;
    private final TokenExchange exchange;
    private final BearerHolder bearer;
    private boolean mcpInitialized;

    AgentLoop(ChatModel chatModel, McpSyncClient mcp, TokenExchange exchange, BearerHolder bearer) {
        this.chatModel = chatModel;
        this.mcp = mcp;
        this.exchange = exchange;
        this.bearer = bearer;
    }

    String ask(String subjectToken, String userMessage) throws Exception {
        bearer.set(exchange.exchange(subjectToken));
        try {
            ensureMcpInitialized();
            var tools = SyncMcpToolCallbackProvider.builder()
                    .mcpClients(mcp)
                    .toolNamePrefixGenerator(McpToolNamePrefixGenerator.noPrefix())
                    .build();
            String answer = ChatClient.builder(chatModel)
                    .defaultToolCallbacks(tools)
                    .build()
                    .prompt()
                    .system("You are the lab's demo agent. You have MCP tools from the lab's MCP server; "
                            + "use them to answer questions about identity, lab state, or audit history. "
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
            mcpInitialized = true;
        }
    }
}
