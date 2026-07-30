# infra/pki/ — human/agent file contract (M3)

Human runs EJBCA issuance and places files EXACTLY here; everything else consumes these paths.

| File | What | Produced by |
|---|---|---|
| `ejbca-root.pem` | EJBCA root CA cert | human, once |
| `spire-intermediate.pem` | Name-constrained intermediate (permittedSubtrees: URI:spiffe://lab.internal/) | human, M3 |
| `spire-intermediate-key.pem` | Its key. chmod 600. NEVER committed (.gitignore'd) | human, M3 |
| `chain.pem` | intermediate + root, in that order | human, M3 |

SPIRE `disk` UpstreamAuthority points at these container paths under /opt/spire/pki/.
Agent: if a file is missing, stop and ask — do not generate a self-signed substitute silently.
