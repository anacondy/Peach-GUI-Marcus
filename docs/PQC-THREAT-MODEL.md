# Post-quantum threat model for Marcus Mix

This maps the (otherwise general) post-quantum discussion onto **this specific
system** — a Sway desktop live/installer ISO for a laptop — and separates what is
a real exposure, what is an upstream gap you cannot fix, and what is noise.

The scanner that produces the evidence is `scripts/pqc-audit`. Run it on the
target after install: `./scripts/pqc-audit` (or `--json`).

## The one-line model

Shor breaks the *asymmetric* primitives — RSA, DH, ECDH, ECDSA, EdDSA — outright.
It does **not** meaningfully break the *symmetric* ones: AES-256 keeps ~128 bits
under Grover, SHA-2/3 halve in search time. So the migration is entirely about
**key exchange** and **signatures**, and the pragmatic answer for both today is a
**hybrid**: a classical primitive plus a lattice one (ML-KEM for exchange, ML-DSA/
SLH-DSA for signatures), so you are never worse off than today even if the new
math is later broken.

The threat that gives this urgency is **harvest-now-decrypt-later**: ciphertext
recorded today is worthless today and readable in 10–15 years. Whether you care is
a property of *the secret's lifetime*, not of the attacker's current capability.

## Applied to this system

### Already fine (do nothing)

* **Disk encryption.** LUKS with AES-256-XTS and a passphrase-derived key is
  already considered quantum-adequate: Grover halves it to 128 bits. There is no
  "wrap the LUKS master key in Kyber" feature in cryptsetup, and adding one would
  not help — the attack surface is the *passphrase and the KDF*, not the cipher.
  The popular advice to "make LUKS quantum-safe with Kyber" is theatre; the
  correct action is a long passphrase. `pqc-audit` says this plainly instead of
  pretending there is a quantum fix to apply.
* **TLS key exchange (in practice).** Firefox has shipped X25519ML-KEM768 by
  default since 132, and OpenSSL ≥3.5 carries the finalised FIPS 203/204/205
  algorithms. Real web traffic is therefore already hybrid on a current system.

### Fixed in this repo

* **OpenSSH key exchange.** OpenSSH 9.9 made `sntrup761x25519-sha512` the
  default; 10.0 prefers `mlkem768x25519-sha256`. Arch's current OpenSSH is in that
  range, so session *confidentiality* is already harvest-resistant. The audit
  checks the KEX list actually offered (`ssh -Q kex`) and flags a pinned
  `KexAlgorithms` in `sshd_config` that would silently disable it — a
  configuration regression you *can* cause and the test therefore guards.

### Upstream gaps — not yours to fix, plan around them

* **SSH / GPG signatures.** No SSH or stable GnuPG release offers post-quantum
  *signatures*. Every host and identity key you have — including Ed25519, the
  best classical option — is forgeable by a future quantum adversary. This is the
  `ssh-identity` and `gpg` "exposed" lines. There is no setting that changes it;
  the plan is: keep keys short-lived, and re-sign / rotate once ML-DSA support
  lands in OpenSSH and GnuPG. Conflating "KEX is hybrid" with "signatures are
  safe" is the most common error in this space; the audit deliberately keeps the
  two findings separate.
* **Package signing.** pacman verifies with GPG (RSA/EdDSA). A quantum adversary
  could forge a package signature; no PQC-signed Arch repository exists. Nothing
  to do today except keep the keyring current and prefer the official repos over
  unsigned AUR builds. This is also why `scripts/install-swayfx.sh` makes you
  *read the PKGBUILD* rather than blindly trusting it.
* **Secure Boot.** The shim→bootloader→kernel chain is verified with RSA PKCS#7;
  no PQC-signed shim exists upstream. Its integrity guarantee expires at Q-day
  like every other RSA signature. Not actionable yet.

### Configuration exposures the audit catches (these are yours)

* `sshd_config` pinning `KexAlgorithms` without a post-quantum entry.
* `pacman.conf` weakened to `SigLevel = Never` / `TrustAll`.
* An unencrypted disk (a classical problem that dwarfs the quantum ones).
* An OpenSSL too old to negotiate hybrid TLS (upgrade to ≥3.5).

## What I deliberately did NOT do

I did **not** add a "quantum-resistant" dependency, fork pacman, or bolt a KEM
onto LUKS. Each of those is either impossible against the official repos, or
security theatre that adds an unreviewed code path to a desktop ISO. The honest,
defensible posture for a student project that a reviewer will take seriously is:
hybrid KEX everywhere it exists today, correct symmetric crypto, short-lived
classical signatures, and a scanner that makes the residual (upstream) risk
visible. That is what `pqc-audit` and this document provide.

## Roadmap (aligned with the analysis you were handed, corrected)

1. **Now:** ship `pqc-audit`; fix the four configuration exposures it can find.
2. **When OpenSSH ships ML-DSA:** rotate SSH identity and host keys, re-sign.
3. **When GnuPG ships post-quantum:** re-sign long-lived and package-signing keys.
4. **Contribute upstream** (liboqs, oqs-provider, OpenSSH) if you want the resume
   value — that is where the genuinely publishable work is, not in a custom ISO.
