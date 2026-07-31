package internal.lab.agent;

/**
 * One REAL event from the per-message chain, for live display (P6.1/D-018).
 * Steps: svid (JWT-SVID fetched), exchange (RFC 8693 done), tool (an MCP tool
 * actually invoked), answer/error (terminal). Details are identity labels and
 * names — never token material.
 */
public record StepEvent(String step, String detail) {
}
