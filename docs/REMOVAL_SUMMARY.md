# DocGen Removal Summary: Loopback Callout & Bulk Generation

**Date:** 2026-04-25
**Branch:** `feature/remove-loopback-bulk`
**Version Impact:** Major — removes two entire feature areas

---

## What Was Removed and Why

This release removes the Loopback Callout infrastructure and Bulk Generation feature from the DocGen package. Both were identified as architectural debt during the API Callout Analysis (see `outputs/API_CALLOUT_ANALYSIS.md`). The decision aligns with **Option 7.1** from that analysis: force all PDF generation client-side and eliminate the fragile server-side rendition pipeline.

### Reasons for Removal

1. **Loopback Callout was the single most fragile component** in the async generation pipeline. It required a self-referential HTTP callout from Apex back to the same org's Connect API to convert DOCX to PDF. This introduced:
   - Hardcoded org-specific URLs in Named Credential metadata
   - A hardcoded OAuth consumer key in version control (security risk)
   - Complex post-deployment setup (Auth Provider, External Credential, Connected App)
   - Asynchronous delays (seconds to minutes) with no guaranteed success
   - Retry storms consuming daily async callout and Queueable limits
   - Poor portability between orgs

2. **Bulk Generation depended on the loopback** for PDF output and added its own scaling concerns. The `DocGenBatch` class processed records in chunks of 10, each potentially triggering Platform Events, Queueable jobs, and HTTP callouts. This was unsustainable for large data volumes.

3. **Client-side PDF conversion already existed** and produced better results with instant feedback. The LWC components (`docGenRunner`, `docGenAdmin`) use `docxtemplater` + `mammoth` + `html2pdf.js` to render DOCX to PDF entirely in the browser. Removing the server-side path simplifies the architecture without degrading the primary user experience.

---

## Deleted Components

### Apex Classes (8 classes, 16 files)

| Class | Purpose |
|-------|---------|
| `DocGenRenditionService` | Made the loopback HTTP callout to Salesforce Connect API `/connect/files/{id}/rendition?type=PDF` |
| `DocGenRenditionQueueable` | Async processor with retry logic (max 10 retries) for failed renditions |
| `DocGenBatch` | Batch Apex for bulk document generation |
| `DocGenBulkController` | Aura/LWC controller for the bulk generation UI |
| `DocGenBulkFlowAction` | Invocable Flow action for bulk generation |
| `DocGenBulkFlowActionTest` | Tests for the bulk Flow action |
| `DocGenBulkTests` | Tests for the bulk controller and batch |
| `LoopbackTestQueueable` | Experimental/test utility for loopback callouts |

### Apex Trigger (1 trigger, 2 files)

| Trigger | Purpose |
|---------|---------|
| `DocGenRenditionTrigger` | Platform Event trigger on `DocGen_Rendition_Event__e` that enqueued `DocGenRenditionQueueable` |

### Custom Objects (2 objects, 9 files)

| Object | Purpose |
|--------|---------|
| `DocGen_Job__c` | Tracked bulk generation jobs (status, query condition, success/error counts, total records) |
| `DocGen_Rendition_Event__e` | Platform Event published to trigger async PDF rendition |

Fields deleted with `DocGen_Job__c`:
- `Error_Count__c`
- `Query_Condition__c`
- `Status__c`
- `Success_Count__c`
- `Template__c` (lookup)
- `Total_Records__c`

### Auth / Callout Metadata (3 files)

| File | Purpose |
|------|---------|
| `DocGen_Loopback.namedCredential-meta.xml` | Named Credential pointing back to the org |
| `DocGen_Loopback_Auth.externalCredential-meta.xml` | External Credential for OAuth |
| `DocGen_Auth_Provider.authprovider-meta.xml` | Auth Provider with hardcoded consumer key |

### LWC Bundle (4 files)

| Component | Purpose |
|-----------|---------|
| `docGenBulkRunner` | UI for running bulk generation jobs |

### Tabs (2 files)

| Tab | Purpose |
|-----|---------|
| `DocGen_Bulk_Gen` | Bulk generation tab |
| `DocGen_Job__c` | Bulk job list tab |

### Static Resources (2 files)

| Resource | Purpose |
|----------|---------|
| `DocGen_Bulk_Screen` | Screenshot/image for bulk generation documentation |

### Ad-Hoc Scripts (9 files)

Various Python and Apex scripts in the project root used for one-off metadata fixes, permission updates, and callout experiments. These were not part of the SFDX package.

---

## Modifications to Surviving Components

### `DocGenService.cls`

- Removed the `format` parameter from `saveFile()`.
- Removed the `if (format == 'PDF')` block that called `DocGenRenditionService.addPendingRendition()`.
- The method now always returns a DOCX (or PPTX) `ContentDocumentId`, regardless of template `Output_Format__c`.

### `DocGenFlowAction.cls`

- Removed the `DocGenRenditionService.enqueueRenditions(true)` call at the end of `generateDocument()`.
- Flow actions now return a DOCX `ContentDocumentId` synchronously. No async rendition is triggered.

### `DocGenSignatureService.cls`

- Removed calls to `DocGenRenditionService.addPendingRendition()` and `enqueueRenditions()` from `handleSignatureSubmission()`.
- Replaced the placeholder audit hash `'PENDING_RENDITION:' + signedCvId` with an actual SHA-256 hash computed from the signed DOCX `VersionData`.
- E-signature async path no longer depends on deleted rendition service.

### `docGenWelcome.js` / `.html`

- Removed the `navigateToBulk()` method and the corresponding Bulk Generation navigation button.
- Welcome page now only directs users to the Template Manager.

### `docGenSetupWizard.js` / `.html`

- Removed the multi-step progress indicator and loopback setup steps.
- Removed `getOrgUrl` wire/import and `callbackUrl` getter.
- Reduced to a single-step card: Experience Site URL input + Save button.

### Permission Sets

- `DocGen_Admin` and `DocGen_User`: Removed class access, field permissions, object permissions, and tab settings for all deleted components. Removed `externalCredentialPrincipalAccesses` for `DocGen_Loopback_Auth`.
- `DocGen_Guest_Signature`: Removed `objectPermissions` for `DocGen_Rendition_Event__e`.

### Custom Application

- `DocGen.app-meta.xml`: Removed `DocGen_Bulk_Gen` and `DocGen_Job__c` tabs.

### Manifest

- `manifest/package.xml`: Removed all entries for deleted components.
- Updated API version references to 66.0 where applicable.

---

## Test Coverage Additions

New test classes were added to ensure comprehensive coverage of all surviving signature-related classes:

- `DocGenSignatureServiceTest` — Tests `stampSignatureToBlob`, `stampSignature`, `handleSignatureSubmission` (including edge cases for already-signed/cancelled/invalid tokens), and `DocGenSignatureSubmitter`.
- `DocGenSignatureControllerTest` — Tests `DocGenSignatureController` token validation, document fetching, stamping, finish upload, `DocGenSignatureFinalizer`, `DocGenSignatureSenderController`, `DocGenSignatureSubmitter`, `DocGenSignatureValidator`, and `DocGenAuthenticatorController`.

Existing `DocGenTests` was updated to reflect the removal of rendition-dependent behavior and to add tests for HTML template handling.

---

## Security Improvements

- **Eliminated hardcoded OAuth consumer key** from version control.
- **Eliminated hardcoded org URL** from Named Credential metadata.
- **Removed External Credential and Auth Provider**, reducing the attack surface.
- **Audit hash is now a real SHA-256** of the signed document, not a placeholder string.
- **No more `with sharing` / Named Principal confusion** in async callout context.

---

## Known Limitations

1. **Flow actions and any server-side generation always produce DOCX/PPTX.** If a template's `Output_Format__c` is set to PDF, the server still generates DOCX. PDF conversion only happens in the browser when using the LWC UI (`docGenRunner`, `docGenAdmin`).
2. **Bulk generation is no longer available.** Users who need to generate documents for many records must use the LWC component record-by-record or build their own batch Flow using `DocGenFlowAction`.
3. **E-signature final documents are DOCX.** The signed document returned after e-signature is a DOCX with the signature image injected. PDF conversion of the signed document, if needed, must happen client-side.
4. **No server-side HTML-to-PDF conversion.** HTML templates are supported only in the single-record client-side path.

---

## Files Referenced

- `outputs/API_CALLOUT_ANALYSIS.md` — Full security and architecture analysis that motivated this removal.
- `agent-output/design-requirements.md` — Implementation plan for this feature branch.
