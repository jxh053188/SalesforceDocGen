# P0 Critical Security Fixes — Design Requirements

**Branch:** `feature/security-p0-critical`
**Date:** 2026-04-25

---

## EXISTING METADATA REVIEW

- **Object** `DocGen_Template__c` has fields: `Query_Config__c` (stores SOQL field list), `Query_Metadata__c`, `Base_Object_API__c`, etc.
- **DocGenDataRetriever.cls** (line 20): `fieldsPart` is concatenated directly into a dynamic SOQL query: `SELECT ' + fieldsPart + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1`. It already uses `Database.query(query, AccessLevel.USER_MODE)` for sharing/FLS enforcement, but the string concatenation is still vulnerable to field-list injection (e.g. block-comment truncation, unwanted function calls).
- **DocGenPDFEngine.page** (line 93): `container.innerHTML = data.html;` injects raw HTML without sanitization. Also `postMessage` calls on lines 119 and 123 use target origin `*`.
- **docGenPdfUtils.js** (line 69): `iframe.contentWindow.postMessage(payload, '*')` sends messages without target origin restriction.
- **docGenRunner.js** (lines 251–254): `allowProtoPropertiesByDefault: true` and `allowProtoMethodsByDefault: true` in Handlebars compilation. Also `handleMessage` (line 432) listens to `message` events without origin validation.
- **docGenAdmin.js** (lines 839–842): Same Handlebars prototype-access flags set to `true`.
- **Static Resource** `DocGenEngine` is an `application/zip` containing `html2pdf.js`, `jszip.min.js`, `docx-preview.js`, `index.html`. No sanitization library is present.
- **Test class** `DocGenTests.cls` has existing tests for `DocGenDataRetriever.getRecordData` (simple fields, invalid params, no results). No tests currently cover injection attempts or complex field validation.
- Relevant constraints:
  - `Database.query` with `AccessLevel.USER_MODE` enforces object- and field-level security but does **not** prevent malicious query structure injection through the `fieldsPart` string.
  - The `fieldsPart` can contain parent-relationship paths (`Owner.Name`), child subqueries (`(SELECT Name FROM Contacts)`), and custom field names that must be preserved.
  - Handlebars is used with custom helpers (`each`, `ifList`) to work around LWS proxy issues. Setting `allowProtoPropertiesByDefault`/`allowProtoMethodsByDefault` to `false` is safe because `flattenData` in the LWC already creates plain JavaScript objects without prototypes.
  - The PDF engine iframe runs on the same Salesforce domain as the LWC. `window.location.origin` is the correct target/origin for all `postMessage` traffic.

---

## CLASSIFICATION

- **salesforce-admin**: None (no new metadata objects, fields, or permission sets required).
- **salesforce-developer**: All four fixes involve code changes (Apex, LWC JS, Visualforce JS). One new static-resource file (DOMPurify) must be added to the existing `DocGenEngine` zip.

---

## WHAT USER REQUESTED

1. **Fix XSS via `innerHTML` in PDF Engine** — sanitize HTML before DOM insertion.
2. **Fix `postMessage` without origin validation** — validate `event.origin` in listeners and restrict target origin in sends.
3. **Disable Handlebars prototype access** — change `allowProtoPropertiesByDefault` and `allowProtoMethodsByDefault` from `true` to `false`.
4. **Fix SOQL injection in `DocGenDataRetriever`** — server-side field whitelist/validation before constructing dynamic SOQL.

---

## DEPENDENCIES / CONSTRAINTS FOUND

1. DOMPurify must be added to the `DocGenEngine` static-resource folder so the Visualforce page can load it.
2. The SOQL field-validation logic must support:
   - Simple fields (`Name`, `Custom_Field__c`)
   - Parent-relationship paths (`Owner.Name`, `CreatedBy.Profile.Name`)
   - Child subqueries (`(SELECT Name FROM Contacts)`)
3. `AccessLevel.USER_MODE` already enforces FLS/OLS; validation is an additional structural-hardening layer.
4. All `postMessage` endpoints (send and receive) must use `window.location.origin`.
5. Handlebars proto-access changes must not break the existing `each`/`ifList` LWS workarounds (they operate on flattened plain objects, so `false` is safe).

---

## DEV WORK (salesforce-developer)

### 1. Add DOMPurify to DocGenEngine static resource
- **File to add**: `force-app/main/default/staticresources/DocGenEngine/purify.min.js`
- **Source**: DOMPurify latest stable minified build (e.g. v3.2.5). Use the standard distribution from `https://cdnjs.cloudflare.com/ajax/libs/dompurify/3.2.5/purify.min.js` or the GitHub release asset.
- **Scope**: No new static-resource metadata XML is needed; the existing `DocGenEngine.resource-meta.xml` (`contentType: application/zip`) will zip the folder contents on deploy.

### 2. Sanitize HTML in DocGenPDFEngine.page
- **File**: `force-app/main/default/pages/DocGenPDFEngine.page`
- **Changes**:
  - Add `<script src="{!URLFOR($Resource.DocGenEngine, 'purify.min.js')}"></script>` inside `<head>`, after the existing library scripts.
  - In the inline `<script>` block, before `container.innerHTML = data.html;` (line 93), sanitize the HTML:
    ```javascript
    const cleanHtml = DOMPurify.sanitize(data.html);
    container.innerHTML = cleanHtml;
    ```
  - In the `window.addEventListener('message', ...)` handler (line 59), add at the very top:
    ```javascript
    if (event.origin !== window.location.origin) return;
    ```
  - In `sendError` (line 119), change:
    ```javascript
    window.parent.postMessage({ type: 'docgen_error', message: msg }, '*');
    ```
    to:
    ```javascript
    window.parent.postMessage({ type: 'docgen_error', message: msg }, window.location.origin);
    ```
  - In `sendSuccess` (line 123), change:
    ```javascript
    window.parent.postMessage({ type: 'docgen_success', blob: blob, fileName: fileName }, '*');
    ```
    to:
    ```javascript
    window.parent.postMessage({ type: 'docgen_success', blob: blob, fileName: fileName }, window.location.origin);
    ```

### 3. Fix postMessage origin validation in docGenPdfUtils.js
- **File**: `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js`
- **Changes**:
  - In the `messageHandler` (around line 25), add as the first statement inside the handler:
    ```javascript
    if (event.origin !== window.location.origin) return;
    ```
  - On line 69, change:
    ```javascript
    iframe.contentWindow.postMessage(payload, '*');
    ```
    to:
    ```javascript
    iframe.contentWindow.postMessage(payload, window.location.origin);
    ```

### 4. Fix postMessage origin validation in docGenRunner.js
- **File**: `force-app/main/default/lwc/docGenRunner/docGenRunner.js`
- **Changes**:
  - In `handleMessage` (around line 432), add as the first statement:
    ```javascript
    if (event.origin !== window.location.origin) return;
    ```

### 5. Disable Handlebars prototype access in docGenRunner.js
- **File**: `force-app/main/default/lwc/docGenRunner/docGenRunner.js`
- **Changes**:
  - Lines 251–254 currently read:
    ```javascript
    const renderedHtml = template(recordData, {
        allowProtoPropertiesByDefault: true,
        allowProtoMethodsByDefault: true
    });
    ```
    Change both booleans to `false`:
    ```javascript
    const renderedHtml = template(recordData, {
        allowProtoPropertiesByDefault: false,
        allowProtoMethodsByDefault: false
    });
    ```

### 6. Disable Handlebars prototype access in docGenAdmin.js
- **File**: `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`
- **Changes**:
  - Lines 839–842 currently read:
    ```javascript
    const renderedHtml = template(recordData, {
        allowProtoPropertiesByDefault: true,
        allowProtoMethodsByDefault: true
    });
    ```
    Change both booleans to `false`.

### 7. SOQL injection hardening in DocGenDataRetriever.cls
- **File**: `force-app/main/default/classes/DocGenDataRetriever.cls`
- **Changes**:
  - Create a new private static helper method `validateFieldsConfig(String fieldsConfig, String baseObject)` that returns a sanitized, reconstructed field list string.
  - **Logic requirements**:
    1. Trim input. If it starts with `SELECT ` (case-insensitive), strip it.
    2. Remove any block comments (`/* ... */`). If an unclosed comment is detected, throw `AuraHandledException`.
    3. Tokenize by commas **only at the top level** (commas inside parentheses belong to subqueries and must not split tokens).
    4. For each token:
       - **Subquery** (token starts with `(` and ends with `)`):
         - Validate format: `(SELECT <fields> FROM <relationshipName>)` using a strict regex or parser.
         - Extract `<relationshipName>`. Verify it exists in the base object's `getChildRelationships()`.
         - Determine the child object API name from the relationship.
         - Recursively validate the inner `<fields>` against the child object's schema.
         - Reconstruct the subquery with validated inner fields.
       - **Parent path** (token contains `.`):
         - Split by `.`. Validate the first segment against the base object's fields. The field must be a reference field (`getReferenceTo()` not empty) or have a valid relationship name.
         - Walk the relationship chain: for each subsequent segment, validate against the parent object's fields.
         - Reconstruct the dot-separated path.
       - **Simple field**:
         - Validate that the token exactly matches an accessible field name on the base object (case-sensitive check against `Schema.DescribeSObjectResult.fields.getMap()` keys after trimming).
         - Include it if valid.
    5. If any token fails validation, throw `AuraHandledException('Invalid field or subquery in query configuration: ' + token)`.
    6. Return the reconstructed comma-separated field list.
  - In `getRecordData`, replace the direct concatenation on line 20 with:
    ```apex
    String validatedFields = validateFieldsConfig(fieldsConfig, baseObject);
    String query = 'SELECT ' + validatedFields + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';
    ```
  - **Governor limits**: Use `Schema.getGlobalDescribe()` once per invocation. Cache the base object's `DescribeSObjectResult` in a local variable. Relationship walking may consume extra describe calls — keep them minimal and avoid queries inside loops.

### 8. Apex test coverage for SOQL injection fix
- **File**: `force-app/main/default/classes/DocGenTests.cls`
- **Add test methods**:
  - `testGetRecordDataValidatesSimpleFields` — ensure `Name, AccountSource` still works.
  - `testGetRecordDataValidatesParentField` — ensure `Owner.Name` still works.
  - `testGetRecordDataValidatesSubquery` — ensure `(SELECT Name FROM Contacts)` still works.
  - `testGetRecordDataRejectsInvalidField` — pass `Name, BadField__c` and assert exception thrown.
  - `testGetRecordDataRejectsInjectionComment` — pass `Id /*` and assert exception thrown.
  - `testGetRecordDataRejectsInjectionFromKeyword` — pass `Id FROM Account` and assert exception thrown.
  - `testGetRecordDataRejectsInjectionWhereKeyword` — pass `Id WHERE Name='x'` and assert exception thrown.

---

## EXECUTION ORDER

1. Add `purify.min.js` to `staticresources/DocGenEngine/`.
2. Update `DocGenPDFEngine.page` (load DOMPurify, sanitize HTML, fix postMessage origins).
3. Update `docGenPdfUtils.js` (fix postMessage target origin, add listener origin check).
4. Update `docGenRunner.js` (fix postMessage listener origin check, disable Handlebars proto access).
5. Update `docGenAdmin.js` (disable Handlebars proto access).
6. Update `DocGenDataRetriever.cls` (add `validateFieldsConfig` and use it).
7. Update `DocGenTests.cls` (add injection/validation test cases).

---

## IMPLEMENTATION NOTES FOR ALL AGENTS

- **Do not** attempt to write to formula fields — none are involved.
- **Do not** change `DocGenEngine.resource-meta.xml`; simply add the new JS file to the folder.
- When validating fields in Apex, remember that `Schema.SObjectType.fields.getMap()` keys are case-sensitive API names. Validate tokens after trimming whitespace.
- `Database.query(query, AccessLevel.USER_MODE)` must remain in place; the validation layer is additive.
- All JavaScript origin checks must use exact string equality: `event.origin === window.location.origin`. Do **not** use `endsWith` or other relaxed checks.
- DOMPurify sanitization should be applied only to the HTML path in the PDF engine (line 93). The DOCX path (line 102) uses `docx.renderAsync` which generates its own DOM — no raw `innerHTML` there.
- Handlebars `allowProtoPropertiesByDefault: false` is safe because `flattenData` recursively builds plain `{}` objects and `Array.from` arrays before passing them to the template.
- Commit all changes to branch `feature/security-p0-critical`. Do **not** deploy.

---

## PROMPT FOR salesforce-developer

"You are fixing four P0 security issues on branch `feature/security-p0-critical`. Commit all changes to this branch; do not deploy.

1. **XSS in PDF Engine**: Download DOMPurify v3.2.5 minified build and add it as `force-app/main/default/staticresources/DocGenEngine/purify.min.js`. In `force-app/main/default/pages/DocGenPDFEngine.page`, load the script via `{!URLFOR($Resource.DocGenEngine, 'purify.min.js')}`, then replace `container.innerHTML = data.html;` with `container.innerHTML = DOMPurify.sanitize(data.html);`.

2. **postMessage origin validation**: In `DocGenPDFEngine.page`, add `if (event.origin !== window.location.origin) return;` at the top of the message listener. Change both `window.parent.postMessage(..., '*')` calls to use `window.location.origin` as the target. In `docGenPdfUtils.js`, add the same origin check in the `messageHandler` and change `iframe.contentWindow.postMessage(payload, '*')` to use `window.location.origin`. In `docGenRunner.js`, add the same origin check at the start of `handleMessage`.

3. **Handlebars prototype access**: In `docGenRunner.js` and `docGenAdmin.js`, find the `template(recordData, { allowProtoPropertiesByDefault: true, allowProtoMethodsByDefault: true })` calls and change both booleans to `false`.

4. **SOQL injection in DocGenDataRetriever**: In `DocGenDataRetriever.cls`, create a private static `validateFieldsConfig(String fieldsConfig, String baseObject)` method that parses the field list, strips comments, tokenizes by top-level commas, and validates each token against the Salesforce schema (simple fields, parent paths, and child subqueries). Reconstruct a validated field string. Replace line 20's direct concatenation with the validated string. Throw `AuraHandledException` for any invalid token or unclosed comment.

5. **Tests**: Add test methods to `DocGenTests.cls` covering: (a) valid simple fields, (b) valid parent path, (c) valid subquery, (d) invalid field rejection, (e) comment injection rejection, (f) `FROM` keyword injection rejection, (g) `WHERE` keyword injection rejection."
