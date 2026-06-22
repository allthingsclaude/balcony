# Export Compliance — Balcony iOS

> ⚠️ **Not legal advice.** This is a practical checklist assembled from Apple's flow + US BIS / French ANSSI public guidance. For a shipping E2E product, have someone confirm the classification once.

## TL;DR — what's going on

Balcony implements its **own** end-to-end encryption (not just HTTPS), so it uses
**non-exempt encryption** under US export rules (EAR Category 5, Part 2). That triggers:

1. The App Store Connect "App Encryption Documentation" prompts (the dialogs you saw).
2. A one-time **export compliance documentation** upload (the *France = Yes* branch).
3. An **annual** US self-classification report (mass-market crypto).

Answering `France = Yes` is the honest answer — Balcony is distributed worldwide,
including France. `No` would be inaccurate.

## What's encrypted (paste this into any form that asks for a description)

> Balcony establishes an end-to-end encrypted channel between a paired macOS host and
> iPhone client to transport Claude Code session data (terminal output / transcripts).
> Key agreement: **X25519** (Curve25519 ECDH). Message encryption: **XChaCha20-Poly1305**
> (256-bit AEAD). Implemented via **libsodium** (swift-sodium). All algorithms are
> published, standard, and internationally accepted (not proprietary). Keys are held only
> by the two paired devices; any relay forwards opaque ciphertext only.

- **Symmetric key length:** 256-bit → above all EAR exemption thresholds → non-exempt.
- **ECCN:** **5D992.c** (mass-market encryption software), eligible under License
  Exception ENC, EAR §740.17(b)(1).
- **CCATS required?** No — qualifies for *self-classification* (§742.15(b)), not a formal
  classification request.

## The plist keys (stops the per-build prompts)

Already added to `BalconyiOS/Resources/Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

This skips the "what type of encryption?" questions on every build.

**After** Apple approves your uploaded documentation (step 1 below), Apple issues an
**export compliance code**. Add it so you're never prompted again:

```xml
<key>ITSEncryptionExportComplianceCode</key>
<string>«PASTE-CODE-FROM-APP-STORE-CONNECT»</string>
```

> Note: this is only added to **BalconyiOS** — the macOS app ships outside the App Store
> (Sparkle), so App Store Connect never prompts for it. The same product/self-classification
> still legally covers the Mac build.

---

## Step 1 — Upload export compliance documentation (App Store Connect)

The *France = Yes* dialog points you to **App Store Connect → your app → App Information →
App Encryption Documentation**. Upload a document that states your classification. A simple
one-page PDF works; include:

- Product: **Balcony** (com.balcony.ios)
- The encryption description above
- ECCN **5D992.c**, License Exception **ENC §740.17(b)(1)**
- A line: *"Self-classification report filed with BIS and NSA on «DATE» (see Step 2)."*

Apple reviews it, then issues the `ITSEncryptionExportComplianceCode`.

## Step 2 — US self-classification report (BIS + NSA) — annual

Required for mass-market (5x992.c) encryption. Free, email-based.

- **To:** `crypt-supp8@bis.doc.gov` **and** `enc@nsa.gov`
- **Subject:** `Self-Classification Report — Balcony`
- **Attachment:** a comma/tab-delimited file (per *Supplement No. 8 to EAR Part 742*) with one
  row per product. Fields to fill:

| Field | Value |
|---|---|
| (a) Point of contact | «Your name» |
| (b) Phone / email | «phone» / mail@markoradak.com |
| (c) Manufacturer | «Legal entity / your name» |
| (d) Product name | Balcony |
| (e) Model/type | Mobile + desktop application |
| (f) ECCN | 5D992.c |
| (g) Authorization type | Self-classification, §740.17(b)(1) |
| (h) Item description | E2E messaging/sync app; X25519 + XChaCha20-Poly1305 (libsodium) |
| (i) Non-standard crypto? | No |
| (j) Open cryptographic interface? | No |

- **Deadline:** by **Feb 1 each year**, covering products self-classified in the prior
  calendar year. (BIS §742.15(b).) Re-file annually while Balcony ships.

## Step 3 — France / ANSSI declaration (verify)

France (LCEN art. 30 / décret 2007-663) requires a **declaration** to ANSSI for *supplying*
a means of cryptology providing confidentiality. As the App Store distributor in France, you
are the supplier.

- File the "déclaration" via ANSSI's online portal (means of cryptology / confidentiality).
- Keep the receipt with this doc.
- ⚠️ **Confirm whether Balcony qualifies for an exemption** before filing — the rules have
  carve-outs. This is the one item most worth a lawyer's 10 minutes.

---

## Checklist

- [x] `ITSAppUsesNonExemptEncryption = true` in `BalconyiOS/Resources/Info.plist`
- [ ] Upload export-compliance doc in App Store Connect (Step 1)
- [ ] File US self-classification report → BIS + NSA (Step 2)
- [ ] Add `ITSEncryptionExportComplianceCode` once Apple issues it
- [ ] Confirm + file France/ANSSI declaration (Step 3)
- [ ] Re-file US self-classification report by **Feb 1** annually
