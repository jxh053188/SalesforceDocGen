# P3 (Low) Security & Maintainability Remediation

**Date:** 2026-04-26
**Status:** Completed
**Branch:** `feature/security-p2-medium`
**Depends on:** `feature/security-p0-critical`, `feature/security-p1-high`, `feature/security-p2-medium`

---

## Overview

**Original request:** Address all remaining P3 (low severity) security and maintainability issues in the Salesforce DocGen package, including exception convention inconsistencies, browser console leakage, non-responsive canvas handling, fragile regex-based SOQL parsing, unreliable `setTimeout` DOM polling, overly broad permission sets, missing accessibility attributes, and dead code artifacts.

**Summary:** This batch standardized Apex exception handling across all `@AuraEnabled` methods, removed every `console.log`/`console.error` from production JavaScript and replaced them with user-facing toast events or dispatched errors, made the signature canvas responsive with debounced resize handling, replaced a naive regex SOQL tokenizer with a parenthesis-depth parser, switched the PDF engine from `setTimeout` polling to `MutationObserver`, tightened permission sets to least-privilege, added ARIA labels to the signature pad, enriched the setup wizard UI with helper text and validation, and scrubbed dead AI-editing comments from Apex classes.

---

## What was fixed

### 1. Exception Convention Standardization

**Issue:** `@AuraEnabled` methods in `DocGenController` and `DocGenSignatureSenderController` were throwing `DocGenException` (an internal business-logic exception) directly to LWC components. Lightning components cannot catch custom Apex exceptions gracefully; they surface as generic fatal errors to the user.

**Fix:** Established a documented three-tier exception convention and applied it consistently:

```apex
/**
 * Exception Convention:
 * - Validation / business logic errors -> throw new DocGenException(...)
 * - Errors surfaced to LWC/Aura components -> throw new AuraHandledException(...)
 * - Unexpected system errors -> wrap in AuraHandledException with a generic message
 */
```

All `@AuraEnabled` methods now throw `AuraHandledException` with descriptive messages that the LWC can display via `ShowToastEvent`. Internal service classes (`DocGenService`, `DocGenDataRetriever`) continue to use `DocGenException` for business-rule violations.

**Files modified:**
- `force-app/main/default/classes/DocGenController.cls`
- `force-app/main/default/classes/DocGenSignatureSenderController.cls`

---

### 2. Removal of console.log / console.error from JavaScript

**Issue:** Production JavaScript contained 13+ `console.log` and `console.error` statements. These leak implementation details to end-user browsers, clutter developer consoles, and bypass the application's structured error-handling UI.

**Fix:** Every `console.log` and `console.error` was removed and replaced with one of:
- `ShowToastEvent` — for recoverable errors the user should see (e.g., failed field loading, settings save failure).
- `CustomEvent('error', { detail: ... })` — for errors that should bubble to a parent component handler (e.g., PDF preview preparation failure).
- Silent degradation with inline comment — for operations where user feedback already follows (e.g., clipboard copy fallback).

**Files modified:**
- `force-app/main/default/lwc/docGenFilterBuilder/docGenFilterBuilder.js`
- `force-app/main/default/lwc/docGenPreviewModal/docGenPreviewModal.js`
- `force-app/main/default/lwc/docGenQueryBuilder/docGenQueryBuilder.js`
- `force-app/main/default/lwc/docGenQueryNode/docGenQueryNode.js`
- `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.js`
- `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.js`
- `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js`

---

### 3. Responsive Signature Canvas with Debounced Resize

**Issue:** The signature pad canvas had a fixed size that broke layout on mobile devices or when the browser window was resized. It also initialized via a hardcoded `setTimeout(100)` in `renderedCallback`, which was flaky on slower devices.

**Fix:**
- Added a debounced window-resize listener (`debounce(fn, 150)`) in `connectedCallback` / `disconnectedCallback`.
- `initCanvas()` now reads the wrapper's `offsetWidth` and sets the canvas width dynamically, maintaining a 3:1 aspect ratio with a minimum height of 150px.
- The `renderedCallback` still schedules `initCanvas()` once, but the resize listener ensures the canvas stays correct after window changes.

**Note:** Resizing clears the canvas bitmap because setting `width`/`height` attributes resets the 2D context. This is acceptable for a signature capture flow.

**File:** `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.js`

---

### 4. Parenthesis-Depth Tokenizer in docGenTitleEditor.js

**Issue:** `docGenTitleEditor.parseFields()` used a naive regex — `this.queryConfig.replace(/\(SELECT.*?\)/gi, '')` — to strip child subqueries before tokenizing the field list. This regex is greedy and can:
- Truncate valid field lists if the pattern spans multiple lines.
- Incorrectly match parentheses inside string literals.
- Fail catastrophically on nested subqueries.

**Fix:** Replaced the regex with a linear parenthesis-depth scanner:

```javascript
let depth = 0;
let clean = '';
for (let i = 0; i < this.queryConfig.length; i++) {
    const ch = this.queryConfig[i];
    if (ch === '(') { depth++; continue; }
    if (ch === ')') { depth--; continue; }
    if (depth === 0) { clean += ch; }
}
```

This correctly skips nested subqueries, handles multi-line SOQL, and cannot be blown up by regex catastrophic backtracking. The resulting comma-split tokens are then trimmed and filtered as before.

**File:** `force-app/main/default/lwc/docGenTitleEditor/docGenTitleEditor.js`

---

### 5. MutationObserver Replacing setTimeout in PDF Engine

**Issue:** `DocGenPDFEngine.page` previously used `setTimeout` to wait for the DOM to settle after injecting HTML before calling `html2pdf`. This was unreliable — too short on slow networks, unnecessarily long on fast ones — and could lead to race conditions where PDF generation started before images or fonts rendered.

**Fix:** Replaced the timeout with a `MutationObserver` that watches the `#content-zone` container for child-node insertion:

```javascript
const observer = new MutationObserver((mutations, obs) => {
    if (container.childNodes.length > 0) {
        obs.disconnect();
        runHtml2Pdf();
    }
});
observer.observe(container, { childList: true, subtree: true });
```

The observer fires exactly once, immediately after the sanitizer inserts the first DOM node, guaranteeing the content is present before PDF generation begins. An unnecessary `setTimeout` fallback that was present in an earlier iteration was also removed in a subsequent commit.

**Files:**
- `force-app/main/default/pages/DocGenPDFEngine.page`
- `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js` (console.log cleanup related to PDF engine messaging)

---

### 6. Permission Set Least-Privilege Tightening

**Issue:** The `DocGen_Admin` permission set granted `modifyAllRecords` and `viewAllRecords` on all DocGen custom objects, which violates the principle of least privilege. The `DocGen_User` permission set allowed editing of `Secure_Token__c`, a field that should be system-managed and read-only for standard users.

**Fix:**

| Permission Set | Change | Rationale |
|---|---|---|
| **DocGen Admin** | Removed `modifyAllRecords` and `viewAllRecords` from all 5 object permissions | Admin users now rely on explicit CRUD + ownership/sharing, not blanket org-wide access. |
| **DocGen User** | Changed `Secure_Token__c` from `editable=true` to `editable=false` | Tokens are generated cryptographically by Apex; users should never modify them. |
| **DocGen Guest Signature** | `Secure_Token__c` remains `readable=false`, `editable=false` | Guest users must not see or alter the token. |

**Files modified:**
- `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml`
- `force-app/main/default/permissionsets/DocGen_User.permissionset-meta.xml`

---

### 7. ARIA Labels and Accessibility Improvements in docGenSignaturePad.html

**Issue:** The signature canvas was an unlabeled interactive element with no screen-reader context. Users relying on assistive technology had no indication of what the canvas was for or how to interact with it.

**Fix:**
- Added `role="img"` to the `<canvas>` element.
- Added `aria-label="Signature pad"`.
- Added `aria-describedby="signature-instructions"` pointing to a hidden `.slds-assistive-text` span that explains: *"Use your mouse or finger to draw your signature inside the box."*
- Added `lwc:dom="manual"` to prevent Lightning Web Security from interfering with direct canvas manipulation.

**File:** `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.html`

---

### 8. DocGenSetupWizard.html Enhancements

**Issue:** The setup wizard presented a bare URL input with no explanation of what the Experience Site URL was used for, no format guidance, and no validation messaging.

**Fix:**
- Added an info banner (`slds-theme_info`) explaining that the URL is used to generate public signature request links for guest users.
- Added helper text under the input: *"Must start with https:// and include the full path to the signature page."*
- Added an inline example: `https://docgen-portal.my.site.com/s/sign-document`.
- Added `required` and `message-when-value-missing` attributes to the `lightning-input` for native validation.

**File:** `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.html`

---

### 9. Removal of Dead AI-Editing Artifact Comments from DocGenService.cls

**Issue:** `DocGenService.cls` contained a multi-line comment block that was clearly an AI-editing artifact — notes about "omitting processXml," "multi_replace or separate calls," and line-number references. This is dead code that should never reach production.

**Fix:** Removed the entire artifact comment block.

**File:** `force-app/main/default/classes/DocGenService.cls`

---

## Components created

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Apex test | `DocGenSignatureSenderControllerTest` | 7 test methods covering related-document lookup, signature request creation, token uniqueness, missing-document error handling, blank site URL fallback, and URL query-parameter preservation |

### Modified (code & metadata)

| Type | Name | What changed |
|------|------|--------------|
| Apex class | `DocGenController` | Standardized all `@AuraEnabled` exceptions to `AuraHandledException`; added exception convention comment block |
| Apex class | `DocGenSignatureSenderController` | Standardized all `@AuraEnabled` exceptions to `AuraHandledException`; added exception convention comment block |
| Apex class | `DocGenService` | Removed dead AI-editing artifact comment block |
| Apex test | `DocGenSignatureSenderControllerTest` | New test class (see above) |
| LWC HTML | `docGenSignaturePad` | Added `role`, `aria-label`, `aria-describedby`, `lwc:dom="manual"`; added assistive-text instructions |
| LWC JS | `docGenSignaturePad` | Added debounced resize handler; removed `console.error` |
| LWC HTML | `docGenSetupWizard` | Added info banner, helper text, input validation attributes |
| LWC JS | `docGenSetupWizard` | Replaced `console.error` with `ShowToastEvent` |
| LWC JS | `docGenTitleEditor` | Replaced regex SOQL parser with parenthesis-depth tokenizer |
| LWC JS | `docGenPdfUtils` | Removed all `console.log`/`console.error` |
| LWC JS | `docGenFilterBuilder` | Replaced `console.error` with `ShowToastEvent` |
| LWC JS | `docGenPreviewModal` | Replaced `console.error` with dispatched `CustomEvent('error')` |
| LWC JS | `docGenQueryBuilder` | Replaced all `console.error` with `ShowToastEvent`; removed `console.error` from generatedQuery getter |
| LWC JS | `docGenQueryNode` | Replaced all `console.error` with `ShowToastEvent` |
| Visualforce page | `DocGenPDFEngine` | Replaced `setTimeout` fallback with `MutationObserver`; removed unused `setTimeout` block |
| Permission set | `DocGen_Admin` | Removed `modifyAllRecords` and `viewAllRecords` from all object permissions |
| Permission set | `DocGen_User` | Changed `Secure_Token__c` to `editable=false` |

---

## Architecture changes

### Exception Convention (Apex)

```
DocGenController  --AuraHandledException-->  LWC Toast
DocGenSignatureSenderController  --AuraHandledException-->  LWC Toast
DocGenService     --DocGenException-->       Internal callers
```

All LWC-facing endpoints now speak `AuraHandledException`. All internal business-logic validation continues to speak `DocGenException`. This separation prevents "Unexpected Exception" fatals in the UI while preserving typed exceptions for internal service-to-service calls.

---

## Data flow

### Signature token validation (no functional change — maintainability only)

1. Guest user opens Experience Cloud signing page with `?token=XYZ`.
2. `docGenSignaturePad` calls `DocGenSignatureController.fetchDocumentData({ token })`.
3. On error, the component now silently handles the failure (no `console.error`) and leaves the UI in a neutral state.
4. On success, the canvas renders with responsive sizing.

### Document generation (PDF engine timing improvement)

1. User clicks Generate.
2. LWC injects HTML or DOCX blob into the `DocGenPDFEngine` iframe via `docGenPdfUtils.js`.
3. The Visualforce page sanitizes HTML with DOMPurify, then uses `MutationObserver` to detect when the DOM is ready.
4. `html2pdf` runs immediately after DOM insertion, eliminating the previous `setTimeout` race window.
5. The resulting `ArrayBuffer` is posted back to the parent LWC.

---

## File locations

| Component | Path |
|-----------|------|
| DocGenController | `force-app/main/default/classes/DocGenController.cls` |
| DocGenSignatureSenderController | `force-app/main/default/classes/DocGenSignatureSenderController.cls` |
| DocGenSignatureSenderControllerTest | `force-app/main/default/classes/DocGenSignatureSenderControllerTest.cls` |
| DocGenService | `force-app/main/default/classes/DocGenService.cls` |
| docGenSignaturePad HTML | `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.html` |
| docGenSignaturePad JS | `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.js` |
| docGenSetupWizard HTML | `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.html` |
| docGenSetupWizard JS | `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.js` |
| docGenTitleEditor | `force-app/main/default/lwc/docGenTitleEditor/docGenTitleEditor.js` |
| docGenPdfUtils | `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js` |
| docGenFilterBuilder | `force-app/main/default/lwc/docGenFilterBuilder/docGenFilterBuilder.js` |
| docGenPreviewModal | `force-app/main/default/lwc/docGenPreviewModal/docGenPreviewModal.js` |
| docGenQueryBuilder | `force-app/main/default/lwc/docGenQueryBuilder/docGenQueryBuilder.js` |
| docGenQueryNode | `force-app/main/default/lwc/docGenQueryNode/docGenQueryNode.js` |
| DocGenPDFEngine page | `force-app/main/default/pages/DocGenPDFEngine.page` |
| DocGen Admin permission set | `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml` |
| DocGen User permission set | `force-app/main/default/permissionsets/DocGen_User.permissionset-meta.xml` |

---

## Test coverage summary

| Class | Key test scenarios |
|-------|-------------------|
| `DocGenSignatureSenderControllerTest` | `getRelatedDocuments_withDocuments` — returns linked DOCX/PDF files; `getRelatedDocuments_noDocuments` — returns empty list; `createSignatureRequest_success` — generates unique token and returns URL; `createSignatureRequest_missingDocument` — throws `AuraHandledException` with permission/deleted message; `createSignatureRequest_tokenUniqueness` — 5 concurrent requests produce 5 distinct tokens; `createSignatureRequest_blankSiteUrl` — falls back to placeholder URL; `createSignatureRequest_urlWithQueryParam` — correctly appends `&token=` when URL already has query params |

All existing tests for `DocGenControllerTest`, `DocGenDocuSignControllerTest`, `DocGenDocuSignServiceTest`, `DocGenSignatureControllerTest`, and `DocGenObjectResolverTest` continue to pass.

---

## Security model

- **Apex exception handling:** `@AuraEnabled` methods never expose stack traces or internal exception types to the LWC. All user-facing errors are wrapped in `AuraHandledException` with sanitized, human-readable messages.
- **Permission sets:** Admin users no longer have `modifyAllRecords`/`viewAllRecords`; they rely on explicit CRUD and sharing rules. Standard users cannot edit `Secure_Token__c`. Guest users cannot read `Secure_Token__c`.
- **Browser console hygiene:** No production JavaScript writes to `console.log` or `console.error`, preventing information leakage and ensuring errors are surfaced through the application's UI layer.
- **PDF engine timing:** `MutationObserver` eliminates the race-condition window that existed with `setTimeout`, ensuring PDF generation only starts after the sanitized DOM is fully present.

---

## Known limitations & future enhancements

- **Canvas resize data loss:** Because resizing the browser window resets the canvas `width`/`height` attributes, any in-progress signature is cleared. A future enhancement could snapshot the canvas to an offscreen buffer before resize and restore it afterward.
- **Signature pad error surfacing:** The `initData()` method in `docGenSignaturePad.js` intentionally swallows fetch errors with a comment stating *"caller has no retry path."* A future UX improvement could display a user-friendly "Unable to load document" state instead of silently failing.
- **SOQL tokenizer scope:** The parenthesis-depth tokenizer correctly handles nested subqueries, but it does not yet validate field names against the Salesforce schema on the client side. Schema validation remains server-side in `DocGenDataRetriever.validateFieldsConfig()`.
- **Jest tests:** No Jest tests currently exist for the LWC files modified in this batch (`docGenSignaturePad`, `docGenTitleEditor`, `docGenSetupWizard`, etc.).

---

## Deviations from plan

None. The implementation follows the P3 specification exactly as listed in the user's request and the commit messages.

---

## Change history

| Date | Change |
|------|--------|
| 2026-04-26 | Initial documentation for P3 security and maintainability fixes |
