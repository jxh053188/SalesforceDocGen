# P0 Critical Security Remediation — DocGen Security Hardening

**Date:** 2026-04-25
**Status:** Completed
**Branch:** `feature/security-p0-critical`

---

## Executive Summary

Four P0 critical vulnerabilities were identified in the Document Generation (DocGen) package that could allow cross-site scripting (XSS), cross-origin data leakage, prototype-pollution-based remote code execution, and SOQL injection. All four issues were remediated in a single branch with zero new metadata dependencies, relying entirely on code-level hardening and one additional static-resource file (DOMPurify). The fixes are additive — no existing functionality was removed, and all changes are backward-compatible for legitimate use cases.

---

## Vulnerability Details

### 1. XSS via `innerHTML` in PDF Engine (CVE-class: Stored / Reflected XSS)

**Location:** `DocGenPDFEngine.page`, line 93 (original)

**Risk:** The Visualforce-based PDF engine accepted raw HTML strings from the LWC and injected them directly into the DOM using `container.innerHTML = data.html;`. A malicious template or compromised record data containing `<script>` tags, event handlers, or `javascript:` URIs would execute in the context of the Visualforce page, which runs under the Salesforce domain. This grants the payload access to the user's session cookie and any `window.parent` postMessage APIs.

**Severity:** P0 — Active exploitation could lead to full session hijacking and data exfiltration.

---

### 2. `postMessage` Without Origin Validation (CVE-class: Cross-Origin Communication / Data Leakage)

**Locations:**
- `DocGenPDFEngine.page` — listener (line 59), `sendError` (line 119), `sendSuccess` (line 123)
- `docGenPdfUtils.js` — `messageHandler` (line 25), `postMessage` send (line 69)
- `docGenRunner.js` — `handleMessage` (line 432)

**Risk:** All `postMessage` endpoints used wildcard origin (`*`) for both sending and receiving. Any third-party iframe or tab opened by the user could:
1. Send forged `docgen_success` / `docgen_error` messages to the LWC, tricking it into saving attacker-controlled blobs to Salesforce records.
2. Receive binary PDF blobs or error messages from the PDF engine that were intended only for the parent LWC.

**Severity:** P0 — Could enable data leakage and unauthorized record modification.

---

### 3. Handlebars Prototype Access Enabled (CVE-class: Prototype Pollution / Template Injection)

**Locations:**
- `docGenRunner.js` (original lines 251–254)
- `docGenAdmin.js` (original lines 839–842)

**Risk:** Handlebars was compiled with `allowProtoPropertiesByDefault: true` and `allowProtoMethodsByDefault: true`. This permits templates to access properties and methods on `Object.prototype` (e.g., `constructor`, `__proto__`, `toString`). A malicious HTML template could traverse the prototype chain to execute arbitrary JavaScript in the user's browser.

**Severity:** P0 — Remote code execution in the context of the Lightning Experience domain.

---

### 4. SOQL Injection in `DocGenDataRetriever` (CVE-class: Data Exfiltration / Unauthorized Record Access)

**Location:** `DocGenDataRetriever.cls` (original line 20)

**Risk:** The `fieldsConfig` parameter (sourced from `DocGen_Template__c.Query_Config__c`) was concatenated directly into a dynamic SOQL string:

```apex
String query = 'SELECT ' + fieldsPart + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';
```

Although `Database.query(query, AccessLevel.USER_MODE)` enforces object- and field-level security, it does **not** prevent malicious query-structure injection. An attacker with template-edit permissions could craft a `Query_Config__c` value such as:

- `Id /*` — truncate the query with an unclosed block comment, causing a runtime error (DoS).
- `Id, Name FROM Account WHERE Name != null /*` — break out of the SELECT clause and append arbitrary SOQL clauses, potentially returning records other than the one specified by `recordId`.
- `Id, (SELECT Id FROM Contacts WHERE Name = 'x')` — inject arbitrary WHERE clauses into child subqueries.

**Severity:** P0 — Could allow unauthorized data access and query manipulation.

---

## Remediation Approach

### 1. XSS Remediation — DOMPurify Sanitization

**File:** `force-app/main/default/pages/DocGenPDFEngine.page`

**Changes:**
- Added DOMPurify v3.2.5 minified build to the existing `DocGenEngine` static resource folder:
  `force-app/main/default/staticresources/DocGenEngine/purify.min.js`
- Loaded the library in the Visualforce page `<head>`:
  ```html
  <script src="{!URLFOR($Resource.DocGenEngine, 'purify.min.js')}"></script>
  ```
- Replaced raw `innerHTML` assignment with sanitized output:
  ```javascript
  // BEFORE
  container.innerHTML = data.html;

  // AFTER
  container.innerHTML = DOMPurify.sanitize(data.html);
  ```

**Why DOMPurify:** It is the industry-standard DOM-only sanitizer. It runs entirely client-side, requires no external callouts, and strips dangerous tags/attributes while preserving legitimate formatting markup needed for document generation.

---

### 2. postMessage Origin Lockdown

**Files changed:**
- `force-app/main/default/pages/DocGenPDFEngine.page`
- `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js`
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js`

**Pattern applied everywhere:** Exact-string-match origin validation using `window.location.origin`.

#### Receiving (listener) hardening:
```javascript
// BEFORE
window.addEventListener('message', async function(event) {
    const data = event.data;
    ...
});

// AFTER
window.addEventListener('message', async function(event) {
    if (event.origin !== window.location.origin) return;
    const data = event.data;
    ...
});
```

Applied in:
- `DocGenPDFEngine.page` (PDF engine listener)
- `docGenPdfUtils.js` (`messageHandler`)
- `docGenRunner.js` (`handleMessage`)

#### Sending (target) hardening:
```javascript
// BEFORE
window.parent.postMessage({ type: 'docgen_error', message: msg }, '*');
iframe.contentWindow.postMessage(payload, '*');

// AFTER
window.parent.postMessage({ type: 'docgen_error', message: msg }, window.location.origin);
iframe.contentWindow.postMessage(payload, window.location.origin);
```

Applied in:
- `DocGenPDFEngine.page` — `sendError` and `sendSuccess`
- `docGenPdfUtils.js` — `iframe.contentWindow.postMessage`

**Additional null guard:** Added `if (!event.data) return;` in `docGenRunner.js` `handleMessage` to prevent null-reference exceptions from stray postMessage events.

---

### 3. Handlebars Prototype Access Disabled

**Files changed:**
- `force-app/main/default/lwc/docGenRunner/docGenRunner.js`
- `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`

**Change:**
```javascript
// BEFORE
const renderedHtml = template(recordData, {
    allowProtoPropertiesByDefault: true,
    allowProtoMethodsByDefault: true
});

// AFTER
const renderedHtml = template(recordData, {
    allowProtoPropertiesByDefault: false,
    allowProtoMethodsByDefault: false
});
```

**Safety justification:** Setting these to `false` is safe because `flattenData()` in `docGenRunner.js` recursively builds plain JavaScript objects (`{}`) and native arrays (`Array.from`) before passing data to Handlebars. There are no prototype-dependent properties that templates legitimately need to access.

---

### 4. SOQL Injection Hardening — Schema-Aware Field Validation

**File:** `force-app/main/default/classes/DocGenDataRetriever.cls`

**Change:** Replaced direct string concatenation with a validated field builder:

```apex
// BEFORE
String query = 'SELECT ' + fieldsPart + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';

// AFTER
String validatedFields = validateFieldsConfig(fieldsPart, baseObject);
String query = 'SELECT ' + validatedFields + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';
```

The new `validateFieldsConfig` method performs a multi-stage parse-and-validate pipeline:

1. **Comment stripping** — Removes block comments (`/* ... */`), line comments (`//`), and SQL-style single-line comments (`--`). Unclosed block comments throw `AuraHandledException`.
2. **Top-level tokenization** — Splits the field list by commas, but **only at parenthesis depth zero**. This ensures commas inside child subqueries (`(SELECT Name, Email FROM Contacts)`) are not treated as field separators.
3. **Keyword injection detection** — Rejects any top-level token containing `from` or `where` (unless it is a properly enclosed subquery).
4. **Schema validation per token:**
   - **Simple fields** — Verified against `Schema.DescribeSObjectResult.fields.getMap()` (case-insensitive key check).
   - **Parent-relationship paths** (`Owner.Name`, `CreatedBy.Profile.Name`) — Walked segment by segment; each segment must exist on the current object, and intermediate segments must be reference fields with a valid `getReferenceTo()` target.
   - **Child subqueries** (`(SELECT Name FROM Contacts)`) — Parsed with a strict regex, the relationship name is verified against `getChildRelationships()`, and inner fields are recursively validated against the child object's schema.
5. **Reconstruction** — Returns a cleaned, comma-separated field string guaranteed to contain only validated schema tokens.

**Governor limit optimization:** `Schema.getGlobalDescribe()` is called once per invocation and cached in a local variable (`gd`). A helper `getDescribeResult` centralizes object resolution and avoids redundant describe calls.

---

## Schema Validation Details

### `validateFieldsConfig(String fieldsConfig, String baseObject)`

| Step | Method | Description |
|------|--------|-------------|
| 1 | `stripComments` | Removes `/* */`, `//`, and `--` comments. Throws on unclosed `/*`. |
| 2 | `tokenizeByTopLevelCommas` | Character-by-character parser tracking `(` depth. Only splits on commas when `depth == 0`. |
| 3 | Keyword guard | Inline check for `from` / `where` on non-subquery tokens. |
| 4 | Token classification | Delegates to `validateSubquery`, `validateParentPath`, or `validateSimpleField`. |
| 5 | Reconstruction | Joins validated tokens with `, ` and returns the sanitized SELECT clause. |

### `validateSubquery(String subquery, String objectName, Map<String, Schema.SObjectType> gd)`

1. Strips outer parentheses.
2. Verifies the inner string starts with `SELECT ` (case-insensitive).
3. Uses a strict regex `(?i)\bFROM\s+([a-zA-Z_]\w*)` to extract the relationship name.
4. Validates that **nothing** follows the relationship name (rejects trailing WHERE, ORDER BY, LIMIT, etc.).
5. Looks up the relationship name in `getChildRelationships()` and resolves the child object API name.
6. Recursively tokenizes and validates the inner field list against the child object.
7. Returns a **reconstructed** subquery string containing only validated fields:
   ```apex
   return '(SELECT ' + String.join(validatedSubFields, ', ') + ' FROM ' + childRelName + ')';
   ```

### `validateParentPath(String path, String objectName, Map<String, Schema.SObjectType> gd)`

1. Splits the path on `.`.
2. For each segment (except the last):
   - Confirms the field exists on the current object.
   - Confirms `fieldDesc.getReferenceTo()` is non-empty.
   - Advances `currentObject` to the first referenced object type.
3. For the final segment, confirms only that the field exists on the current object.
4. Throws `AuraHandledException` on any mismatch.

### `validateSimpleField(String fieldName, String objectName, Map<String, Schema.SObjectType> gd)`

1. Retrieves the object's describe result.
2. Checks `fieldMap.containsKey(fieldName.toLowerCase())`.
3. Throws `AuraHandledException` if the field is not found.

---

## Testing

Seven new test methods were added to `force-app/main/default/classes/DocGenTests.cls` to verify the SOQL injection hardening and ensure legitimate query patterns continue to work.

| Test Method | Purpose | Expected Result |
|-------------|---------|-----------------|
| `testValidateFieldsConfigValidSimpleFields` | Verifies `Id, Name, AccountSource` on Account | Success; data returned |
| `testValidateFieldsConfigValidParentPath` | Verifies `Owner.Name` parent traversal | Success; data returned |
| `testValidateFieldsConfigValidSubquery` | Verifies `(SELECT Id FROM Contacts)` child query | Success; data returned |
| `testValidateFieldsConfigInvalidFieldRejection` | Injects `InvalidField__c` | `AuraHandledException` with "Invalid field" |
| `testValidateFieldsConfigCommentInjectionRejection` | Injects `Id /* unclosed comment` | `AuraHandledException` with "Unclosed block comment" |
| `testValidateFieldsConfigFromKeywordInjectionRejection` | Injects `Id, Name FROM Account` | `AuraHandledException` with "FROM keyword" |
| `testValidateFieldsConfigWhereKeywordInjectionRejection` | Injects `Id, Name WHERE Name = 'x'` | `AuraHandledException` with "WHERE keyword" |

All existing tests in `DocGenTests.cls` continue to pass, confirming backward compatibility.

**Coverage impact:** The new validation logic and tests push DocGenDataRetriever coverage above the 75% minimum and toward the 90%+ project target.

---

## Deployment Notes

1. **Static Resource Addition:** `purify.min.js` is placed inside the existing `DocGenEngine` folder (`force-app/main/default/staticresources/DocGenEngine/`). No new `.resource-meta.xml` file is required; the existing `DocGenEngine` metadata (`contentType: application/zip`) will zip the folder contents on deploy. Ensure the deployment target's static resource is refreshed after deployment.

2. **Visualforce Page Caching:** Browsers may cache the `DocGenPDFEngine.page` JavaScript. After deployment, advise users to clear their browser cache or perform a hard refresh (`Ctrl+Shift+R` / `Cmd+Shift+R`) to ensure the updated origin checks and DOMPurify load.

3. **Handlebars Templates:** The change from `allowProtoPropertiesByDefault: true` to `false` is safe for all existing templates because `flattenData()` produces plain objects. No template migration is needed.

4. **SOQL Validation Rollout:** `validateFieldsConfig` is additive — it runs before `Database.query`. Existing templates with valid field configurations will work identically. Only templates with malformed or malicious `Query_Config__c` values will now throw exceptions (which is the desired security behavior).

5. **No Permission Set Changes:** These fixes do not introduce new objects, fields, or Apex entry points. No permission set updates are required.

6. **Scratch Org Validation Recommended:** Because the validation logic relies on `Schema.getGlobalDescribe()` and `getChildRelationships()`, test in an org that contains the standard objects and relationships used by your templates (e.g., Account, Contact, Opportunity) to confirm describe-call behavior.

---

## Change History

| Date | Commit | Change |
|------|--------|--------|
| 2026-04-25 | `4b4deb5` | Initial security fix: DOMPurify, postMessage origins, Handlebars proto disable, SOQL validation |
| 2026-04-25 | `d9fd3f3` | Security review follow-up: subquery reconstruction, single globalDescribe call, null guard on event.data |

---

## Sign-off

- All four P0 vulnerabilities remediated.
- Zero breaking changes for legitimate usage.
- Tests added and passing.
- Branch ready for PR merge and subsequent DevOps deployment.
