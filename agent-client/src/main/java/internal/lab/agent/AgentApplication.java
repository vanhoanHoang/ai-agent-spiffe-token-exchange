package internal.lab.agent;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * M10 chassis. The LLM provider is a deployment detail: it enters through the
 * starter dependency and application.properties only — no provider type
 * appears in this package (scripts/check-p2.sh greps for exactly that).
 */
@SpringBootApplication
public class AgentApplication {
}
