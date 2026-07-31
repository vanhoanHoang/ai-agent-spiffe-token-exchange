package internal.lab.agent;

import java.util.Arrays;

import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

/**
 * P2 interface: one-shot CLI chat ("the show surface is M11"). Usage:
 * {@code chat <natural language...>} with the human's token in SUBJECT_TOKEN.
 * Deliberately thin — P2.5 adds a browser session on top of the same
 * {@link AgentLoop} without touching it.
 */
@Component
public class ChatRunner implements CommandLineRunner {

    private final AgentLoop loop;

    ChatRunner(AgentLoop loop) {
        this.loop = loop;
    }

    @Override
    public void run(String... args) throws Exception {
        String prompt = String.join(" ", Arrays.copyOfRange(args, 1, args.length)).trim();
        if (prompt.isEmpty()) {
            throw new IllegalArgumentException("usage: chat <message>");
        }
        String subjectToken = System.getenv("SUBJECT_TOKEN");
        System.out.println(loop.ask(subjectToken, prompt));
    }
}
