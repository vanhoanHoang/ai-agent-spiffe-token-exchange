#!/usr/bin/env python
"""Assemble demo-run.json (DEMO_RUN schema v1) from the pieces capture-run.sh
collected in a work dir. Tokens are decoded here and NEVER copied whole: the
signature field is always the literal REDACTED, and the assembled document is
scanned to prove no JWT-shaped string survived."""
import base64
import datetime
import json
import re
import sys
from pathlib import Path

AGENT_ID = "spiffe://ai-agent.id.eviden.internal/agent-client"
MCP_ID = "spiffe://ai-agent.id.eviden.internal/mcp-server"
RESOURCE_ID = "https://mcp.ai-agent.id.eviden.internal:8443"

# The five M9 rejection lines as acceptance.sh prints them (infra/acceptance.sh).
REJECTIONS = [
    ("no-client-cert", "no client cert -> rejected at TLS handshake"),
    ("wrong-audience", "wrong-audience token -> 401"),
    ("svid-as-bearer", "JWT-SVID as bearer -> 401"),
    ("unlisted-workload", "unlisted SPIFFE ID -> 403"),
    ("token-replay", "token replay by other workload -> 403 (act!=peer)"),
]


def b64url_json(seg: str) -> dict:
    return json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))


def decode(token: str, name: str, description: str) -> dict:
    header_seg, claims_seg, _sig = token.strip().split(".")
    return {
        "name": name,
        "description": description,
        "header": b64url_json(header_seg),
        "claims": b64url_json(claims_seg),
        "signature": "REDACTED",
    }


def log_lines(path: Path) -> list[str]:
    lines = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "tool=" in raw or "act=" in raw:
            lines.append(raw.split("| ", 1)[-1].strip())
    return lines


def main(work: Path, out_path: Path) -> None:
    subject = decode((work / "subject.jwt").read_text(), "subject_token",
                     "alice's login token: issued to alice for the agent "
                     "(aud = agent-client), before any exchange")
    exchanged = decode((work / "exchanged.jwt").read_text(), "exchanged_token",
                       "RFC 8693 exchange, client-authenticated with the agent's JWT-SVID "
                       "(jwt-spiffe): sub = alice, act.sub = the agent, aud = the MCP server")

    acceptance = (work / "acceptance.txt").read_text(encoding="utf-8", errors="replace")
    rejections = []
    for rid, title in REJECTIONS:
        m = re.search(re.escape(title) + r"\s+(PASS|FAIL)", acceptance)
        verdict = "deny-as-designed" if (m and m.group(1) == "PASS") else "FAILED-TO-DENY"
        rejections.append({"id": rid, "title": title, "verdict": verdict, "source": "infra/acceptance.sh"})

    custody_ok = bool(re.search(r"SVID chains to EJBCA root.*PASS", acceptance))

    doc = {
        "version": 1,
        "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "trust_domain": "spiffe://ai-agent.id.eviden.internal",
        "actors": {
            "human": {"username": "alice", "sub": subject["claims"]["sub"]},
            "agent": {"spiffe_id": AGENT_ID},
            "mcp_server": {"spiffe_id": MCP_ID, "resource_id": RESOURCE_ID},
        },
        "tokens": [subject, exchanged],
        "steps": [
            {
                "id": "login", "kind": "login", "verdict": "pass",
                "title": "alice logs in",
                "detail": "scripted sign-in used for this capture; the live demo "
                          "uses the browser login with consent",
                "token_ref": "subject_token",
            },
            {
                "id": "exchange", "kind": "exchange", "verdict": "pass",
                "title": "jwt-spiffe token exchange (RFC 8693)",
                "detail": "client authentication is the agent's JWT-SVID. No client secret exists",
                "token_ref": "exchanged_token",
            },
            {
                "id": "chat-whoami", "kind": "chat", "verdict": "pass",
                "title": "natural language -> MCP tool call (whoami)",
                "prompt": (work / "prompt1.txt").read_text().strip(),
                "answer": (work / "answer1.txt").read_text(encoding="utf-8", errors="replace").strip(),
                "log_lines": log_lines(work / "logs1.txt"),
            },
            {
                "id": "chat-audit-refused", "kind": "chat", "verdict": "deny",
                "title": "scope refusal: read_audit_log without mcp:audit",
                "detail": "the model attempts the call and the token refuses it. "
                          "Enforcement is tokens, not model behavior",
                "prompt": (work / "prompt2.txt").read_text().strip(),
                "answer": (work / "answer2.txt").read_text(encoding="utf-8", errors="replace").strip(),
                "log_lines": log_lines(work / "logs2.txt"),
            },
        ],
        "rejections": rejections,
        "chain_of_custody": {
            "verified": custody_ok,
            "notes": "fresh SVID chains to the EJBCA root. The intermediate's URI name "
                     "constraint (URI:ai-agent.id.eviden.internal) is present and critical",
            "source": "infra/acceptance.sh",
        },
        "log_tail": log_lines(work / "logtail.txt"),
    }

    text = json.dumps(doc, indent=2)
    # No complete token may survive into a capture: three dot-separated base64url
    # segments of meaningful length is a JWT wherever it appears.
    if re.search(r"[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", text):
        sys.exit("REFUSING to write capture: JWT-shaped string present after redaction")
    out_path.write_text(text + "\n", encoding="utf-8")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
