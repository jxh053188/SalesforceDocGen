# Memory Bank

## DocGen Fix History

### 1. "Invalid token: FROM keyword detected" Error
**File:** `force-app/main/default/classes/DocGenDataRetriever.cls`
**Problem:** When users built queries via the Query Builder UI, the full SOQL (`SELECT ... FROM Account`) was stored in `Query_Config__c`. However, Apex validation logic (`validateSubquery()`) rejected any string containing `FROM`, causing saves to fail with "Invalid token: FROM keyword detected in fields configuration."
**Fix:**
- Added `indexOfTopLevelFrom()` helper to parse the full SOQL and extract only the field list (everything before `FROM`).
- Updated `validateSubquery()` to allow `WHERE`, `ORDER BY`, and `LIMIT` in subqueries, while still rejecting `UNION`, `;`, and nested `SELECT`.
- The field list (not full SOQL) is now passed to the validator.

---

### 2. PDF Preview Not Working for All Template Types
**Files:** `force-app/main/default/lwc/docGenEngine/docGenEngine.js`, `docGenAdmin.js`, `docGenRunner.js`
**Problem:** Preview only worked when the template's output format was explicitly set to `PDF`. For Word/PowerPoint templates with "Native" output, clicking Preview did nothing.
**Fix:**
- In `generateBlobFromDocx()`: Changed `isPDF = outputFormat === 'PDF' && !isPPT` to `isPDF = outputFormat === 'PDF'` so that PowerPoint templates can also generate PDF output.
- Rewrote preview logic in `docGenAdmin.js` and `docGenRunner.js` so that **Preview always generates a PDF** via the iframe engine, regardless of `templateOutputFormat` setting.

---

### 3. Cross-Origin postMessage Between LWC and Visualforce Iframe
**Files:** `force-app/main/default/lwc/docGenPdfUtils/docGenPdfUtils.js`, `pages/DocGenPDFEngine.page`
**Problem:** The PDF engine runs on a different Salesforce subdomain (Visualforce) than the LWC (Lightning). `postMessage` with `window.location.origin` as target failed because origins didn't match. Additionally, the LWC's `handleMessage` listener was double-handling responses.
**Fix:**
- Changed `postMessage` target origin from `window.location.origin` to `'*'` in `docGenPdfUtils.js`.
- Removed `event.origin` checks; instead verify message payload structure (`data.type === 'docgen_success'` or `'docgen_error'`).
- Added a 30-second timeout to the PDF generation Promise to fail gracefully if the engine never responds.
- Removed duplicate `handleMessage` listener from `docGenRunner.js` (the iframe utility handles the response already).

---

### 4. Offscreen Iframe PDF Generation Timeout
**Files:** `force-app/main/default/pages/DocGenPDFEngine.page`, `lwc/docGenAdmin/docGenAdmin.html`
**Problem:** The PDF engine iframe is positioned offscreen (`top: -20000px`) so it's invisible. Browsers skip paint cycles for offscreen elements, so `requestAnimationFrame` never fired, causing `html2pdf.js` (via `html2canvas`) to hang indefinitely.
**Fix:**
- In `DocGenPDFEngine.page`: Replaced `requestAnimationFrame(() => runHtml2Pdf())` with `window.setTimeout(() => runHtml2Pdf(), 0)`.
- In `docGenAdmin.html`: Changed iframe CSS from `visibility: hidden` to `opacity: 0; pointer-events: none` because `visibility: hidden` also blocks paint cycles.

---

### 5. Styling Stripped from PDF Output
**File:** `force-app/main/default/pages/DocGenPDFEngine.page`
**Problem:** `DOMPurify.sanitize()` was stripping `<style>` tags and inline `style` attributes, causing PDFs to render as unstyled/plain text.
**Fix:**
- Added explicit configuration to `DOMPurify.sanitize()`:
  ```js
  DOMPurify.sanitize(data.html, {
      ADD_TAGS: ['style'],
      ADD_ATTR: ['style', 'class', 'id'],
      FORCE_BODY: true
  })
  ```

---

### 6. Added Fields Disappear After Page Refresh (Save/Load Bug)
**Files:** `force-app/main/default/lwc/docGenAdmin/docGenAdmin.js`, `docGenAdmin.html`
**Problem:** `docGenAdmin` contains multiple `<c-doc-gen-query-builder>` instances in the DOM:
1. New Template Wizard builder (always present, even when hidden)
2. Edit Modal builder (outside tabset, the one users actually edit)
3. Tags/Preview builders (with `show-tags-only="true"`)

Methods `getEditModeQueryConfig()`, `getEditModeQueryMetadata()`, and `refreshEditQueryBuilder()` used `querySelectorAll('c-doc-gen-query-builder')`, which returns elements in **document order**. The wizard builder comes first, so saves were reading its stale/empty metadata instead of the edit modal's builder.
**Fix:**
- In `docGenAdmin.html`: Added `data-mode="edit"` to the edit modal's main query builder.
- In `docGenAdmin.js`: Updated all three methods to use `this.template.querySelector('c-doc-gen-query-builder[data-mode="edit"]')` instead of iterating over all builders.

---

### 7. Visualforce Page JavaScript Syntax Error
**File:** `force-app/main/default/pages/DocGenPDFEngine.page`
**Problem:** An orphaned closing brace `}` remained after refactoring an `if` block to a guard clause (`if (!data || data.type !== 'generate') return;`), causing a `SyntaxError: missing ) after argument list` on page load.
**Fix:** Removed the orphaned brace and restructured the event listener code properly.
