package internal.lab.agent;

import org.springframework.boot.SpringApplication;

/**
 * Entry point dispatcher. The M5-M9 CLI modes (url / token / mcp / svid) stay
 * exactly as the milestone checks exercise them — no Spring involved. Only the
 * M10 "chat" mode boots the Spring chassis with the agentic loop.
 */
public final class AgentMain {

    private AgentMain() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length >= 1 && "chat".equals(args[0])) {
            System.exit(SpringApplication.exit(SpringApplication.run(AgentApplication.class, args)));
        }
        McpCall.main(args);
    }
}
