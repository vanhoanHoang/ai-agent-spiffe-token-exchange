# Conventions

Read before writing Java. Kept deliberately short; anything not covered here follows idiomatic Spring Boot 3 / Java 21 defaults.

## Java

- Java 21, Spring Boot 3.x — exact versions pinned in `docs/VERSIONS.md` only.
- Base package: `internal.lab.<module>` (`internal.lab.mcp`, `internal.lab.agent`, `internal.lab.kcspi`).
- Constructor injection only; no field `@Autowired`. Prefer records for value types.
- Dependencies: Nimbus JOSE for any hand-rolled JWT work; `java-spiffe` for Workload API and SSLContext — never hand-roll SVID plumbing.

## Validation code (the rules that are actually about security)

- **No catch-and-permit, ever.** A validation path either passes explicitly or throws. `catch (Exception e) { return true; }` and its cousins are always a bug.
- Fail closed with a *specific* exception naming which check failed (`aud`, `exp`, signature, trust-domain, allowlist).
- The assertion-type URN `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe` exists as **one constant**: `internal.lab.agent.SpiffeClientAuth.ASSERTION_TYPE`. Nothing else may inline that string. (If the M0(b) fallback SPI is built, its one additional constant is recorded in `DECISIONS.md`.)
- JWT-SVID validation lives behind one interface; callers see pass/fail, not draft internals.
- Never extend a TTL/lifetime or widen a check to make a test pass.

## Unverified facts

Any statement not backed by `specs/`, `docs/`, or CLAUDE.md §3 gets a marker on the line it affects:

```java
// VERIFY: <what> against <source>
```

Zero markers is a milestone gate. Markers are removed only by citing the source in the commit that removes them.

## Tests

- Exit-criterion checks are written **before** implementation and live in `scripts/` (shell) or the module's test tree (JUnit 5).
- Negative tests are first-class: every accept path has at least one companion reject test. The four M9 rejections are the model.
- Test names say the behavior: `rejectsTokenWithWrongAudience`, not `testAud2`.

## Git

- One branch per milestone: `m4-mcp-resource-server`. One milestone per session.
- Workstreams A (`mcp-server/`), B (`keycloak-spiffe-spi/`), C (`infra/`) in separate worktrees; no cross-workstream edits without asking.
- Never commit: secrets, tokens, private keys (`infra/pki/*-key.pem` is gitignored), anything under `specs/` modified by hand.
- Commit messages: imperative subject, body cites spec section or `DECISIONS.md` entry when the change is validation-relevant.
