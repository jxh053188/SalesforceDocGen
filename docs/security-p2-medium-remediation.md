# P2 (Medium) Security & Maintainability Remediation

**Date:** 2026-04-26
**Status:** Completed
**Branch:** `feature/security-p2-medium`
**Depends on:** `feature/security-p0-critical`, `feature/security-p1-high`

---

## Overview

**Original request:** Address all remaining P2 security and maintainability issues in the Salesforce DocGen package, including hardcoded object API names, duplicated JavaScript code, a flow running in SystemModeWithoutSharing, silent binary data corruption in the admin preview panel, and missing concurrency controls on ContentDistribution creation.

**Summary:** This batch eliminated approximately 260 lines of duplicated LWC JavaScript by introducing a shared `docGenEngine` utility module, replaced scattered `if/else` object branching in DocuSign controllers with a strategy-pattern `DocGenObjectResolver` class, switched the Signature Submission flow to `SystemModeWithSharing`, added `FOR UPDATE` and static re-entry guards to prevent duplicate ContentDistribution records, and fixed a binary-data corruption bug in the admin DOCX preview path.

---

## What was fixed

### 1. Flow SystemModeWithoutSharing

**Issue:** `DocGen_Signature_Submission` flow ran in `SystemModeWithoutSharing`, which granted excessive implicit privileges to guest users in Experience Cloud.

**Fix:** Changed `<runInMode>` from `SystemModeWithoutSharing` to `SystemModeWithSharing`. The flow delegates all privileged DML and record access to underlying Apex invocable actions (`DocGenSignatureValidator`, `DocGenSignatureFinalizer`) that already use `WITH SYSTEM_MODE` SOQL and a `private without sharing` inner helper (`SystemModeHelper`). This means the flow respects sharing rules for its own context, while Apex still elevates privileges only where strictly necessary.

**File:** `force-app/main/default/flows/DocGen_Signature_Submission.flow-meta.xml`

---

### 2. Massive JavaScript Code Duplication

**Issue:** `docGenRunner.js` (540 lines) and `docGenAdmin.js` (1052 lines) each contained identical copies of:
- Handlebars helper registration (`each`, `ifList`) — ~100 lines
- docxtemplater configuration block — ~20 lines
- `flattenData()` — ~20 lines
- `base64ToUtf8String()` — ~8 lines
- PDF orchestration wrappers — ~10 lines

This made every template engine bug fix or LWS compatibility update require editing two files.

**Fix:** Extracted all shared logic into a new LWC utility module `c/docGenEngine`.

**New file:** `force-app/main/default/lwc/docGenEngine/docGenEngine.js`

**Exported functions:**

| Function | Purpose |
|---|---|
| `registerHandlebarsHelpers()` | Registers LWS-safe `each` and `ifList` helpers on `window.Handlebars` |
| `base64ToUtf8String(base64)` | Decodes base64 to UTF-8 text string (HTML templates only) |
| `base64ToBinaryUint8Array(base64)` | Decodes base64 to `Uint8Array` (DOCX/PPTX binary data) |
| `flattenData(obj)` | Deep-clones SOQL results, strips `attributes`, unwraps `{ totalSize, records }` arrays |
| `configureDocxtemplater(zipBuffer)` | Creates a configured `docxtemplater` instance from an `ArrayBuffer` |
| `renderDocxTemplate(templateBase64, recordData)` | Renders a DOCX/PPTX template and returns the doc instance |
| `renderHtmlTemplate(templateBase64, recordData)` | Renders an HTML template via Handlebars with `allowProtoPropertiesByDefault: false` |
| `generateBlobFromDocx(doc, templateType, outputFormat)` | Returns `{ blob, extension, isPDF, isPPT }` based on template type |
| `orchestratePdfGeneration(iframe, messageData)` | Thin wrapper around `generatePdfFromIframe` that injects `mode: 'returnBuffer'` |
| `downloadBlob(blob, fileName)` | Wraps `window.saveAs` with a clear error if the library is missing |

Both `docGenRunner.js` and `docGenAdmin.js` now import these functions instead of defining them inline.

**Refactored files:**
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js`
- `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`

---

### 3. Hardcoded Object API Names

**Issue:** `DocGenDocuSignController.getRelatedContacts()` and `DocGenDocuSignService.resolveDefaultRecipient()` contained repetitive `if (recordType == Opportunity.SObjectType)` branching blocks for `Opportunity`, `Account`, and `Contract`. This pattern was brittle and required touching multiple files to add support for a new object.

**Fix:** Introduced a strategy-pattern resolver class.

**New file:** `force-app/main/default/classes/DocGenObjectResolver.cls`

- Defines a private `IContactResolver` interface with two methods: `getRelatedContacts(Id)` and `resolveDefaultRecipient(Id)`.
- Implements three private inner resolver classes:
  - `OpportunityResolver` — queries `OpportunityContactRole` and `Opportunity.ContactId`
  - `AccountResolver` — handles PersonAccount fields (`IsPersonAccount`, `PersonContactId`) and `AccountContactRole`
  - `ContractResolver` — queries `CustomerSignedId` and `ContractContactRole`
- Exposes a static `Map<Schema.SObjectType, IContactResolver> RESOLVERS` lookup table.
- Public static methods `getRelatedContacts(Id)` and `resolveDefaultRecipient(Id)` delegate to the appropriate resolver. Unsupported object types return an empty list or `null` safely.
- All SOQL inside resolvers uses `WITH USER_MODE`.

**Modified files:**
- `force-app/main/default/classes/DocGenDocuSignController.cls` — `getRelatedContacts()` now delegates to `DocGenObjectResolver.getRelatedContacts(recordId)`.
- `force-app/main/default/classes/DocGenDocuSignService.cls` — `resolveDefaultRecipient()` now delegates to `DocGenObjectResolver.resolveDefaultRecipient(recordId)`.

---

### 4. Hardcoded Self-Healing Sample Data

**Issue:** `docGenAdmin.js` contained a magic-string block that auto-injected `QuoteLineItems` into sample queries when the template name matched `'Sample Quote Template'`:

```javascript
if (this.editTemplateName === 'Sample Quote Template' && ... ) {
    console.log('DEBUG: Auto-healing sample query config...');
    this.editTemplateQuery += ', (SELECT Product2.Name ... FROM QuoteLineItems)';
}
```

This was unmaintainable, caused unexpected query mutation for users, and leaked hardcoded template names into production code.

**Fix:** Removed the entire self-healing block. The admin query builder and manual query field are now the single source of truth for query configuration.

**File:** `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`

---

### 5. Rate Limiting on ContentDistribution Creation

**Issue:** `DocGenSignatureController.validateToken()` queried for existing `ContentDistribution` records and created one if missing, with no concurrency control. Under rapid guest-user reloads or duplicate flow Apex action invocations, this could create multiple `ContentDistribution` records for the same `ContentVersion`.

**Fix:** Implemented two-layer protection:

1. **Record-level locking:** Added `FOR UPDATE` to the first `DocGen_Signature_Request__c` query:
   ```apex
   SELECT ... FROM DocGen_Signature_Request__c
   WHERE Secure_Token__c = :token
   WITH SYSTEM_MODE LIMIT 1 FOR UPDATE
   ```
   This serializes concurrent requests for the same token across separate transactions.

2. **Transaction-level re-entry guard:** Added a static `Set<String>`:
   ```apex
   private static final Set<String> TOKENS_IN_PROGRESS = new Set<String>();
   ```
   If `validateToken` is called twice within the same Apex transaction (e.g., flow re-invocation), the second call returns immediately with:
   > "Token validation is already in progress. Please wait."

   The token is added to the set at the start of the `ContentDistribution` lookup block and removed in a `finally` clause to guarantee cleanup.

**File:** `force-app/main/default/classes/DocGenSignatureController.cls`

---

### 6. Binary Data Corruption Bug (DOCX Admin Preview)

**Issue:** In `docGenAdmin.js`, the DOCX preview path incorrectly used `base64ToUtf8String()` to decode a DOCX binary payload before passing it to `PizZip`. UTF-8 decoding corrupts binary Office Open XML data, which caused malformed or unreadable generated documents in the admin test panel.

**Fix:** The shared `docGenEngine` module exposes `base64ToBinaryUint8Array()`, which decodes via `atob()` + `charCodeAt()` into a raw `Uint8Array`. The `renderDocxTemplate()` function uses this internally. Both `docGenRunner.js` and `docGenAdmin.js` now call `renderDocxTemplate()` for DOCX/PPTX generation, eliminating the corruption path entirely.

**Files:**
- `force-app/main/default/lwc/docGenEngine/docGenEngine.js`
- `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`

---

## Components created

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Apex class | `DocGenObjectResolver` | Strategy-pattern resolver for object-specific contact lookups (Opportunity, Account, Contract) |
| Apex test | `DocGenObjectResolverTest` | 16 test methods covering all three supported objects, unsupported objects, PersonAccount paths, and null-contact edge cases |
| LWC JS utility | `docGenEngine` | Shared module exporting template rendering, binary decoding, PDF orchestration, and download helpers |

### Modified (code & metadata)

| Type | Name | What changed |
|------|------|--------------|
| Apex class | `DocGenDocuSignController` | Replaced hardcoded `if/else` branches with `DocGenObjectResolver` delegation |
| Apex class | `DocGenDocuSignService` | Replaced hardcoded `if/else` branches with `DocGenObjectResolver` delegation |
| Apex class | `DocGenSignatureController` | Added `FOR UPDATE`, static `TOKENS_IN_PROGRESS` guard, and `try/finally` around `ContentDistribution` creation |
| Apex test | `DocGenSignatureControllerTest` | Added `testValidateToken_ConcurrentDuplicatePrevention` asserting exactly one `ContentDistribution` per `ContentVersion` after double invocation |
| LWC JS | `docGenRunner` | Removed duplicated helpers/blocks; imports from `c/docGenEngine` |
| LWC JS | `docGenAdmin` | Removed self-healing block and duplicated helpers/blocks; imports from `c/docGenEngine`; DOCX path now uses binary decoding |
| Flow | `DocGen_Signature_Submission` | `runInMode` changed from `SystemModeWithoutSharing` to `SystemModeWithSharing`; description updated to document Apex delegation model |

---

## Architecture changes

### DocGenObjectResolver — Strategy Pattern

Before:
```
DocGenDocuSignController
  getRelatedContacts()
    if Opportunity -> query OCR
    else if Account -> query ACR + PersonAccount
    else if Contract -> query CCR + CustomerSignedId

DocGenDocuSignService
  resolveDefaultRecipient()
    if Opportunity -> return ContactId
    else if Account -> return Primary ACR / PersonContactId
    else if Contract -> return CustomerSignedId
```

After:
```
DocGenObjectResolver
  IContactResolver (interface)
    OpportunityResolver
    AccountResolver
    ContractResolver
  RESOLVERS Map<SObjectType, IContactResolver>
  getRelatedContacts(Id) -> lookup + delegate
  resolveDefaultRecipient(Id) -> lookup + delegate

DocGenDocuSignController
  getRelatedContacts() -> DocGenObjectResolver.getRelatedContacts()

DocGenDocuSignService
  resolveDefaultRecipient() -> DocGenObjectResolver.resolveDefaultRecipient()
```

Adding a new object (e.g., `Quote`, `Case`) now requires creating one new inner resolver class and registering it in the `RESOLVERS` map. No changes are needed in the calling controllers.

### docGenEngine — Shared LWC Utility Module

Before:
```
docGenRunner.js  --- duplicates --->  helper logic
docGenAdmin.js   --- duplicates --->  identical helper logic
```

After:
```
              docGenEngine.js (shared)
                 /           \
         docGenRunner.js   docGenAdmin.js
```

Component-specific logic (Apex calls, toast events, state management) remains in each component. All template engine mechanics (Handlebars, docxtemplater, PizZip, PDF orchestration) live in the shared module.

---

## Data flow

### Signature token validation (rate-limited)

1. Guest user opens Experience Cloud signing page with `?token=XYZ`.
2. Flow `DocGen_Signature_Submission` (now `SystemModeWithSharing`) calls Apex action `DocGenSignatureValidator`.
3. `DocGenSignatureController.validateToken('XYZ')`:
   a. Checks static `TOKENS_IN_PROGRESS` — returns early if same token is already being validated in this transaction.
   b. Queries `DocGen_Signature_Request__c` with `FOR UPDATE` to serialize concurrent transactions.
   c. Queries existing `ContentDistribution` for the `ContentVersion`.
   d. If none exists, creates one via `SystemModeHelper.insertContentDistribution()`.
   e. Removes token from `TOKENS_IN_PROGRESS` in `finally`.
4. Flow proceeds to Signature Screen with the public `DistributionPublicUrl`.

### Document generation (shared engine)

1. User selects template and clicks Generate (runner) or Test Generate (admin).
2. Component calls Apex `DocGenController.generateDocumentData()` to fetch base64 template and SOQL record data.
3. Component calls `flattenData()` from `c/docGenEngine` to sanitize the SOQL payload.
4. **HTML path:** `renderHtmlTemplate()` registers helpers, decodes base64 to UTF-8, compiles with Handlebars (`allowProtoPropertiesByDefault: false`), and returns HTML string.
5. **DOCX/PPTX path:** `renderDocxTemplate()` decodes base64 to `Uint8Array` via `base64ToBinaryUint8Array()`, configures docxtemplater, and renders. `generateBlobFromDocx()` returns the correct blob type.
6. If PDF output is requested, `orchestratePdfGeneration()` passes the blob/HTML to the `DocGenPDFEngine` Visualforce iframe with `mode: 'returnBuffer'`.
7. Component calls `downloadBlob()` or saves to Salesforce via Apex.

---

## File locations

| Component | Path |
|-----------|------|
| DocGenObjectResolver | `force-app/main/default/classes/DocGenObjectResolver.cls` |
| DocGenObjectResolver meta | `force-app/main/default/classes/DocGenObjectResolver.cls-meta.xml` |
| DocGenObjectResolverTest | `force-app/main/default/classes/DocGenObjectResolverTest.cls` |
| docGenEngine LWC | `force-app/main/default/lwc/docGenEngine/docGenEngine.js` |
| docGenEngine LWC meta | `force-app/main/default/lwc/docGenEngine/docGenEngine.js-meta.xml` |
| DocGenDocuSignController | `force-app/main/default/classes/DocGenDocuSignController.cls` |
| DocGenDocuSignService | `force-app/main/default/classes/DocGenDocuSignService.cls` |
| DocGenSignatureController | `force-app/main/default/classes/DocGenSignatureController.cls` |
| DocGenSignatureControllerTest | `force-app/main/default/classes/DocGenSignatureControllerTest.cls` |
| docGenRunner | `force-app/main/default/lwc/docGenRunner/docGenRunner.js` |
| docGenAdmin | `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js` |
| Signature Submission Flow | `force-app/main/default/flows/DocGen_Signature_Submission.flow-meta.xml` |

---

## Test coverage summary

| Class | Key test scenarios |
|-------|-------------------|
| `DocGenObjectResolverTest` | Opportunity with/without ContactId; Account with ACRs and PersonAccount path; Contract with/without CustomerSignedId; unsupported object returns empty/null |
| `DocGenSignatureControllerTest` | `testValidateToken_ConcurrentDuplicatePrevention` — calls `validateToken` twice for the same token and asserts exactly one `ContentDistribution` exists |

All existing tests for `DocGenDocuSignControllerTest` and `DocGenDocuSignServiceTest` continue to pass unchanged because the public method signatures and observable behavior are preserved.

---

## Security model

- **Flow sharing:** `DocGen_Signature_Submission` now runs in `SystemModeWithSharing`. Guest users must have explicit sharing access or the flow must be consumed via a profile/permission set that grants Read on `DocGen_Signature_Request__c`.
- **Apex sharing:** `DocGenObjectResolver` is `public with sharing`. All resolver SOQL uses `WITH USER_MODE` for FLS/OLS enforcement.
- **Privilege elevation:** `DocGenSignatureController` retains its `private without sharing SystemModeHelper` for DML on `ContentDistribution`, `ContentVersion`, `DocGen_Signature_Request__c`, and `DocGen_Signature_Audit__c`. This elevation is scoped to a single inner class and is only invoked from `validateToken`, `stampAndReturnSource`, and `finishSignatureUpload`.
- **Concurrency:** `FOR UPDATE` on `DocGen_Signature_Request__c` prevents race-condition duplicates of `ContentDistribution` across transactions.
- **Handlebars hardening:** `renderHtmlTemplate` enforces `allowProtoPropertiesByDefault: false` and `allowProtoMethodsByDefault: false`, preventing prototype pollution attacks in templates.

---

## Known limitations & future enhancements

- **Guest user flow access:** If Experience Cloud guest users lose access after the `SystemModeWithSharing` change, a permission set granting Read on `DocGen_Signature_Request__c` for the Guest User profile may be required. This should be validated in a sandbox before production deployment.
- **Resolver extensibility:** Adding new objects (e.g., `Quote`, `Lead`) requires a code change to add a new inner resolver class and map entry. A future enhancement could use Custom Metadata Types or a configurable mapping to make this declarative.
- **Jest tests:** No Jest tests currently exist for `docGenEngine`, `docGenRunner`, or `docGenAdmin`. Consider adding LWC unit tests for the shared module functions (`flattenData`, `base64ToBinaryUint8Array`, `generateBlobFromDocx`).
- **ContentDistribution duplicate rules:** The concurrency guard relies on record locking (`FOR UPDATE`) and a static transaction guard. `ContentDistribution` does not support robust custom External ID fields, so an upsert-based approach is not viable.

---

## Deviations from plan

None. The implementation follows the `agent-output/design-plan-p2.md` specification exactly.

---

## Change history

| Date | Change |
|------|--------|
| 2026-04-26 | Initial documentation for P2 security and maintainability fixes |
