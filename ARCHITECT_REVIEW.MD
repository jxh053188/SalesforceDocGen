# DocGen Package — Security & Maintainability Review

**Reviewer:** Senior Salesforce Developer (Claude Code)
**Date:** 2026-04-25
**Branch:** `feature/2026-04-25-docusign-esignature-integration`
**Scope:** Apex, LWC, Visualforce, Permission Sets, Flows, Static Resources

---

## Executive Summary

The DocGen package is a feature-rich document generation and e-signature solution with solid architecture for Word/PowerPoint/HTML templating, DocuSign integration, and native signature capture. However, there are **critical security vulnerabilities** that must be addressed before production deployment, primarily around XSS via the PDF engine and unsafe `postMessage` handling. There is also significant code duplication between components and several SOQL injection trust-boundary issues.

**Risk Summary:**
- **4 Critical (P0)** security issues requiring immediate remediation
- **6 High (P1)** security issues requiring remediation before production
- **8 Medium (P2)** security and maintainability issues
- **10 Low (P3)** code quality and usability issues

---

## 1. CRITICAL SECURITY ISSUES (Fix Before Production)

### 1.1 XSS via `innerHTML` in PDF Engine — CRITICAL
**File:** `force-app/main/default/pages/DocGenPDFEngine.page` (line 93)

```javascript
container.innerHTML = data.html;
```

The Visualforce page receives HTML from the parent LWC via `postMessage` and injects it directly into the DOM. A malicious HTML template can include `<script>` tags or event handlers that execute in the context of the PDF engine page. Since the PDF engine page is served from the Salesforce domain, any script execution inherits the user's Salesforce session.

**Impact:** An attacker with template creation access can craft an HTML template that executes arbitrary JavaScript in the victim's Salesforce session when rendered to PDF. This is a stored XSS vector.

**Recommendation:**
- Sanitize HTML before injection using DOMPurify or a similar library
- Render HTML in a sandboxed `srcdoc` iframe with no JavaScript execution
- At minimum, validate the message origin and sanitize the payload

---

### 1.2 `postMessage` Without Origin Validation — CRITICAL
**Files:**
- `force-app/main/default/pages/DocGenPDFEngine.page` (lines 59, 119, 123)
- `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js` (line 69)
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js` (line 432)

The PDF engine listens for messages from any origin:
```javascript
window.addEventListener('message', async function(event) { ... })
```

And the LWC sends messages to any origin:
```javascript
iframe.contentWindow.postMessage(payload, '*');
```

An attacker could embed the Salesforce page in an iframe and send malicious `docgen_success` or `generate` messages to manipulate document generation or exfiltrate data.

**Impact:** Cross-origin message injection could trigger unauthorized document generation, data exfiltration, or DOM manipulation.

**Recommendation:** Validate `event.origin` against a strict whitelist (`window.location.origin`) in both directions. The comment in `docGenPdfUtils.js` line 26 (`// Validate origin if needed`) indicates this was considered but never implemented.

---

### 1.3 Handlebars Prototype Access Enabled — CRITICAL
**Files:**
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js` (lines 251-254)
- `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js` (lines 839-842)

```javascript
const renderedHtml = template(recordData, {
    allowProtoPropertiesByDefault: true,
    allowProtoMethodsByDefault: true
});
```

This setting allows templates to access JavaScript prototype properties/methods (e.g., `constructor`, `__proto__`, `toString`), which can lead to prototype pollution or remote code execution if an attacker controls template data.

**Impact:** A malicious HTML template could access the global scope and execute arbitrary code via prototype chain manipulation.

**Recommendation:** Set both options to `false`. If specific helpers are needed, register them explicitly with `Handlebars.registerHelper`.

---

### 1.4 SOQL Injection in `DocGenDataRetriever` — CRITICAL
**File:** `force-app/main/default/classes/DocGenDataRetriever.cls` (line 20)

```apex
String query = 'SELECT ' + fieldsPart + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';
List<SObject> results = Database.query(query, AccessLevel.USER_MODE);
```

The `fieldsPart` comes from `Query_Config__c` which is constructed client-side in `DocGenQueryBuilder.js`. While `USER_MODE` restricts row access, it does **not** prevent injection in the `SELECT` clause. A malicious user could inject subqueries, aggregate functions, or `TYPEOF` expressions.

**Impact:** A user with template creation access could craft a `fieldsPart` that extracts data from unrelated objects via subqueries or executes SOQL functions they should not have access to.

**Recommendation:** Parse and whitelist fields server-side before constructing the query. Use `Schema.DescribeFieldResult` to validate every field in `fieldsPart` against the object's schema. Never trust client-constructed SOQL strings for the SELECT clause.

---

## 2. HIGH SEVERITY SECURITY ISSUES

### 2.1 Client-Side SOQL Construction Trust Boundary — HIGH
**Files:**
- `force-app/main/default/lwc/docGenQueryBuilder/docGenQueryBuilder.js`
- `force-app/main/default/lwc/docGenFilterBuilder/docGenFilterBuilder.js`

The SOQL query is built recursively in JavaScript and passed to Apex as a string. The server concatenates the SELECT fields from metadata without re-validation. The filter builder performs naive string quoting:

```javascript
if (val && !val.startsWith("'") && !val.endsWith("'") && isNaN(val) && ...) {
    val = `'${val}'`;
}
soql += `${row.field} ${op} ${val}`;
```

This is vulnerable to quote escaping and injection. For example, a filter value of `Account' OR Name != 'Test` would break out of the string literal.

**Recommendation:** Build the SOQL server-side from structured metadata (JSON), not from a client-provided SOQL string. Pass field names, operators, and values as separate parameters and construct the query in Apex after validation.

---

### 2.2 Predictable Secure Token Generation — HIGH
**File:** `force-app/main/default/classes/DocGenSignatureSenderController.cls` (line 28)

```apex
Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(System.now().getTime()) + Math.random() + signerEmail));
String token = EncodingUtil.convertToHex(hash);
```

`Math.random()` is **not cryptographically secure** and reduces token entropy. An attacker who knows the approximate generation time and signer email can brute-force the token space.

**Impact:** Signature request tokens could be predictable, allowing unauthorized access to documents intended for other signers.

**Recommendation:** Use `Crypto.generateAesKey(256)` or `Crypto.getRandomInteger()` for entropy, not `Math.random()`.

---

### 2.3 `ContentDocumentLink.Visibility = 'AllUsers'` — HIGH
**Files:**
- `force-app/main/default/classes/DocGenController.cls` (line 57)
- `force-app/main/default/classes/DocGenSignatureService.cls` (line 103)

Generated documents are shared with all users in the org, bypassing record-level sharing:
```apex
cdl.Visibility = 'AllUsers';
```

**Impact:** Documents generated for private records become visible to all Salesforce users regardless of sharing rules.

**Recommendation:** Use `'InternalUsers'` or infer visibility from the parent record's sharing model. For guest users, use `'AllUsers'` only when absolutely necessary and document the exception.

---

### 2.4 `without sharing` Classes Exposing Sensitive Data — HIGH
**Files:**
- `force-app/main/default/classes/DocGenSignatureController.cls`
- `force-app/main/default/classes/DocGenAuthenticatorController.cls`
- `force-app/main/default/classes/DocGenSignatureService.cls`
- `force-app/main/default/classes/DocGenSignatureFinalizer.cls`

These classes bypass sharing rules. While this is necessary for guest-user flows, the `DocGenAuthenticatorController.verifyDocument` method allows anyone with a hash to query audit records. There is no rate limiting or CAPTCHA.

**Impact:** An attacker could brute-force SHA-256 hashes to discover signed documents and their metadata.

**Recommendation:**
- Add rate limiting or CAPTCHA to the public verification endpoint
- Consider requiring authentication for verification
- Document why `without sharing` is required for each class

---

### 2.5 Deprecated `{escape: false}` in Visualforce Remoting — HIGH
**File:** `force-app/main/default/pages/DocGenSign.page` (line 93)

```javascript
{escape: false}
```

This is deprecated and can expose the page to XSS if the returned data contains HTML/JS.

**Recommendation:** Remove `{escape: false}` and ensure Apex returns properly escaped data. The default `escape: true` should be sufficient.

---

## 3. MEDIUM SEVERITY SECURITY & MAINTAINABILITY ISSUES

### 3.1 Unchecked Base64 Uploads — MEDIUM
**Files:**
- `force-app/main/default/classes/DocGenSignatureController.cls` (line 131)
- `force-app/main/default/classes/DocGenController.cls` (line 42)

`base64Image` and `base64Data` parameters are decoded without validating content type. A user could upload executable content disguised as a PDF or image.

**Recommendation:** Validate MIME types and file signatures after decoding. For signatures, verify the decoded bytes represent a valid PNG image.

---

### 3.2 Silent Failure in Signature Submission — MEDIUM
**File:** `force-app/main/default/classes/DocGenSignatureService.cls` (lines 146-148)

```apex
} catch (Exception e) {
    System.debug('DocGen: Error in signature handling: ' + e.getMessage());
}
```

Failures in signature processing are silently swallowed. Administrators will never know a signature failed to be applied.

**Recommendation:** Throw the exception or log to a custom error object/Platform Event. Silent failures in signature workflows are unacceptable.

---

### 3.3 Flow Runs in `SystemModeWithoutSharing` — MEDIUM
**File:** `force-app/main/default/flows/DocGen_Signature_Submission.flow-meta.xml` (line 99)

```xml
<runInMode>SystemModeWithoutSharing</runInMode>
```

The Flow runs in System Mode without sharing. While this is necessary for guest users to create ContentVersion records, it bypasses all sharing and FLS rules.

**Recommendation:** Ensure this is intentional and documented. Consider whether the Flow could run in `SystemModeWithSharing` and use a privileged Apex action only for the specific DML that requires elevated access.

---

### 3.4 Massive Code Duplication Between `docGenRunner` and `docGenAdmin` — MEDIUM
**Files:**
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js`
- `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`

Both files contain nearly identical implementations of:
- Handlebars `each` and `ifList` helper registration (~100 lines each)
- docxtemplater configuration (paragraphLoop, linebreaks, delimiters, nullGetter, parser)
- `flattenData()` function
- `base64ToUtf8String()` function
- PDF generation via iframe `postMessage`
- File saving logic

This represents approximately **400+ lines of duplicated code**.

**Recommendation:** Extract all shared document generation logic into a single shared LWC utility module (e.g., `docGenEngine.js`).

---

### 3.5 Hardcoded Object API Names — MEDIUM
**Files:**
- `force-app/main/default/classes/DocGenDocuSignController.cls` (lines 16, 22, 36)
- `force-app/main/default/classes/DocGenDocuSignService.cls` (lines 94, 101, 108)

Multiple instances of string literal comparisons:
```apex
if (objectApiName == 'Opportunity') { ... }
else if (objectApiName == 'Account') { ... }
```

**Recommendation:** Use `Schema.SObjectType` tokens or a configurable resolver pattern to avoid brittle string matching.

---

### 3.6 Hardcoded "Self-Healing" Sample Data — MEDIUM
**File:** `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js` (lines 689-693)

```javascript
if (this.editTemplateName === 'Sample Quote Template' && ...) {
    this.editTemplateQuery += ', (SELECT Product2.Name, Description, Quantity, UnitPrice, TotalPrice FROM QuoteLineItems)';
}
```

Magic strings and hardcoded field references are brittle and confusing.

**Recommendation:** Remove self-healing logic or move it to a proper sample data template configuration.

---

### 3.7 No Rate Limiting on ContentDistribution Creation — MEDIUM
**File:** `force-app/main/default/classes/DocGenSignatureController.cls` (lines 97-118)

Every call to `validateToken` for a new document creates a new `ContentDistribution` record if one doesn't exist. Repeated validations will create duplicate distributions.

**Recommendation:** Add duplicate prevention logic (e.g., check for existing distributions before creating) or implement rate limiting.

---

### 3.8 Dead/Artifact Comments in Apex — MEDIUM
**File:** `force-app/main/default/classes/DocGenService.cls` (lines 84-88)

```apex
// ... (processXml etc omitted, assuming unchanged relative position) ...
// Wait, replacing lines 49-52 and 255-264
// Using multi_replace or separate calls?
// I can do it in two calls.
```

This appears to be leftover from an AI-assisted editing session and should be removed.

---

## 4. LOW SEVERITY CODE QUALITY & USABILITY ISSUES

### 4.1 Duplicate Property Declarations
**File:** `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.js` (lines 22-25)

```javascript
isDrawing = false;
isCanvasEmpty = true;
isDrawing = false;
isCanvasEmpty = true;
```

**Recommendation:** Remove duplicate declarations.

---

### 4.2 Fixed Canvas Dimensions
**File:** `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.js` (line 70)

```javascript
canvas.height = 300;
```

The signature pad has a fixed height and no responsive handling for mobile devices.

**Recommendation:** Use responsive sizing based on container width.

---

### 4.3 Fixed `setTimeout` Delays in PDF Engine
**File:** `force-app/main/default/pages/DocGenPDFEngine.page` (lines 94, 110)

```javascript
setTimeout(function() { ... }, 500);
setTimeout(runHtml2Pdf, 1000);
```

Relies on arbitrary timeouts for rendering. On slow devices or large documents, the conversion may fail or produce blank pages.

**Recommendation:** Use `MutationObserver` or the `onload` event of the rendered content instead of fixed timeouts.

---

### 4.4 No Accessibility Labels on Canvas
**File:** `force-app/main/default/lwc/docGenSignaturePad/docGenSignaturePad.html`

The signature `<canvas>` lacks ARIA labels or descriptive text for screen readers.

**Recommendation:** Add `aria-label` and descriptive text for accessibility compliance.

---

### 4.5 Naive SOQL Parser in Title Editor
**File:** `force-app/main/default/lwc/docGenTitleEditor/docGenTitleEditor.js`

The SOQL parser uses regex that cannot handle nested subqueries, which will produce incorrect field lists for complex templates.

**Recommendation:** Use a proper SOQL parsing approach or validate the output against the query builder metadata.

---

### 4.6 Minimal Setup Wizard
**File:** `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.html`

The setup wizard only contains a single URL field. For a package of this complexity, admins would benefit from guided setup for permissions, site configuration, and DocuSign connection.

---

### 4.7 Hidden Query Builder DOM Workaround
**File:** `force-app/main/default/lwc/docGenAdmin/docGenAdmin.html`

The query builder component is placed outside the tabset and toggled with `slds-hide` so it stays in the DOM. This is a workaround for LWC re-rendering issues but is fragile.

---

### 4.8 Mixed Exception Types
The codebase throws `DocGenException`, `AuraHandledException`, and generic `Exception` inconsistently across classes.

**Recommendation:** Standardize on a custom exception hierarchy.

---

### 4.9 Missing Dedicated Test Class
There is no `DocGenSignatureSenderControllerTest.cls` for `DocGenSignatureSenderController`.

---

### 4.10 Permission Set Issues
**File:** `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml`

- Grants `modifyAllRecords` and `viewAllRecords` on all custom objects — overly broad

**File:** `force-app/main/default/permissionsets/DocGen_User.permissionset-meta.xml`

- Grants edit access to `DocGen_Signature_Request__c.Secure_Token__c` — token field should be read-only for standard users

**File:** `force-app/main/default/permissionsets/DocGen_Guest_Signature.permissionset-meta.xml`

- Grants read access to `Secure_Token__c` on Signature Requests — guest users should not need to read tokens

---

## 5. PRIORITY RECOMMENDATIONS

| Priority | Issue | File(s) |
|----------|-------|---------|
| P0 | XSS via `innerHTML` in PDF engine | `DocGenPDFEngine.page` |
| P0 | `postMessage` without origin validation | `DocGenPDFEngine.page`, `docGenPdfUtils.js` |
| P0 | Handlebars prototype access enabled | `DocGenRunner.js`, `DocGenAdmin.js` |
| P0 | SOQL injection in SELECT clause | `DocGenDataRetriever.cls` |
| P1 | Client-side SOQL trust boundary | `DocGenQueryBuilder.js`, `DocGenFilterBuilder.js` |
| P1 | Predictable token generation | `DocGenSignatureSenderController.cls` |
| P1 | `ContentDocumentLink.Visibility = 'AllUsers'` | `DocGenController.cls`, `DocGenSignatureService.cls` |
| P1 | `without sharing` exposing sensitive data | `DocGenAuthenticatorController.cls` |
| P1 | Deprecated `{escape: false}` | `DocGenSign.page` |
| P2 | Massive JS code duplication | `DocGenRunner.js`, `DocGenAdmin.js` |
| P2 | Silent exception swallowing | `DocGenSignatureService.cls` |
| P2 | Unchecked base64 uploads | `DocGenSignatureController.cls`, `DocGenController.cls` |
| P2 | Flow SystemModeWithoutSharing | `DocGen_Signature_Submission.flow-meta.xml` |
| P3 | Dead/artifact comments | `DocGenService.cls` |
| P3 | Duplicate property declarations | `DocGenSignaturePad.js` |
| P3 | Hardcoded object names | `DocGenDocuSignController.cls`, `DocGenDocuSignService.cls` |

---

## 6. POSITIVE FINDINGS

1. **Sharing Model:** Most Apex classes correctly use `with sharing` and `WITH USER_MODE` for database queries
2. **Input Validation:** `DocGenController` validates null/blank inputs before processing
3. **DocuSign Integration:** Uses the managed package `dfsle` namespace correctly with proper error handling
4. **Template Versioning:** The active-version snapshotting pattern is well-implemented
5. **Test Coverage:** The project includes comprehensive test classes with 90%+ coverage targets
6. **Audit Trail:** SHA-256 hashing of documents provides tamper evidence
7. **Schema Safety:** `DocGenController.getObjectFields` and `getObjectOptions` respect `isAccessible()` and `isFilterable()`

---

*This report was generated from a fresh static code review of the current branch. No files were modified during this review.*
