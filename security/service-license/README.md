# NKTouch paid-service license foundation v0.1

This module is an **isolated prototype** for paid server features such as cloud sync or priority support. It does not change or gate NKTouch's GPL-3.0-or-later Lua Core.

## Implemented

- Ed25519 signed service leases, max lifetime 7 days, strict key ID and audience validation.
- Public-key-only signature verification and short validity periods.
- P-256 installation-key fingerprints (SHA-256 of SPKI, not a persistent hardware ID).
- P-256 nonce + action + license ID + device-key bound challenge-response proof.
- Negative tests for tampering, wrong key, wrong device, expiry, invalid scope and replay simulation.

Run tests with Node.js 20+:

    node --test security/service-license/test/*.test.mjs

## Not production-ready yet

The server APIs and authoritative database checks are **not implemented**. Before using this for real customer licenses:

1. Implement Vercel challenge/activate/renew/deactivate endpoints with server-side authentication.
2. Verify paid entitlement, active license, seat count, suspension and revocation in Supabase. Never trust paid scopes asserted by the client.
3. Store challenges with a short TTL (60-120 seconds) and consume them **atomically** in a database transaction to prevent replay and concurrency issues.
4. Apply API rate limits and log only necessary license events.
5. Store Ed25519 private keys and Supabase service-role keys exclusively in server-side secrets or a KMS. Distribute only public verification keys.
6. Integrate a native P-256 device signing key with iOS Secure Enclave where available; verify on real jailbroken devices. Implement a safe key-recovery / device-transfer policy.
7. Validate behavior under reinstall, clock rollback, offline operation, revoked licenses, lost keys and modified clients.

## Trust boundaries

- A jailbroken client is untrusted; local checks can be patched.
- Service authorization happens on the server. The signed lease is not sufficient authorization for a valuable server operation when revoked.
- Device proof verifies possession of a key, not a person's identity and not the integrity of a jailbroken app.
- No background network calls or license checks inside Lua execution, `tap`, `inputText`, `findColor` or `findImage`.
- Never terminate SpringBoard, break other tweaks or block running scripts due to license/network errors.

## License boundaries

This repo and its upstream ZXTouch components are GPL-3.0-or-later. Selling distribution or support is allowed, but recipients keep the GPL rights to corresponding source, modification and redistribution. This module is intended to control access to **separate server services**, not to negate those rights. Obtain legal review before commercial release or linking proprietary components into GPL-covered modules.

## Next milestone

An audited server-side license lifecycle with atomic nonce storage, seat-limit enforcement, activation recovery and iOS native verification tests, still isolated from NKTouch Lua Core.