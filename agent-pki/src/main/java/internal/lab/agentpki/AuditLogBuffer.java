package internal.lab.agentpki;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.stereotype.Component;

/**
 * In-memory ring of audited calls, so the scope-gated {@code read_audit_log}
 * tool has something real to return. Holds identities and verdicts only —
 * never tokens or credentials.
 */
@Component
public class AuditLogBuffer {

    private static final int CAPACITY = 200;
    private final Deque<String> entries = new ArrayDeque<>(CAPACITY);

    public synchronized void record(String line) {
        if (entries.size() == CAPACITY) {
            entries.removeFirst();
        }
        entries.addLast(line);
    }

    public synchronized List<String> recent(int n) {
        return entries.stream().skip(Math.max(0, entries.size() - n)).collect(Collectors.toList());
    }
}
