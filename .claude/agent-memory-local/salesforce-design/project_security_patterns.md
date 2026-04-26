---
name: DocGen Security Patterns
description: Security constraints and patterns identified in the Salesforce DocGen package
type: project
---

The DocGen package has several security-sensitive areas that require careful handling:

1. **Dynamic SOQL in DocGenDataRetriever**: The `Query_Config__c` field is concatenated directly into SOQL. Any schema validation must support simple fields, parent paths (Owner.Name), and child subqueries ((SELECT Name FROM Contacts)). The fix is additive: `Database.query(..., AccessLevel.USER_MODE)` must remain.

2. **PDF Engine iframe (DocGenPDFEngine.page)**: Runs as a Visualforce page inside an iframe, communicating with LWCs via postMessage. HTML content is injected into the DOM via innerHTML. Any future changes to the engine must preserve DOMPurify sanitization and strict origin validation on postMessage.

3. **Handlebars template rendering (docGenRunner, docGenAdmin)**: Uses custom helpers to bypass LWS proxy restrictions on arrays. Prototype access is now disabled (`allowProtoPropertiesByDefault: false`). Record data is flattened to plain JS objects before templating, which makes this safe.

4. **Static Resource DocGenEngine**: An application/zip static resource containing JS libraries (html2pdf.js, docx-preview.js, jszip.min.js). Any new library added to this zip must be placed inside `force-app/main/default/staticresources/DocGenEngine/`.

**Why:** These constraints were discovered during a P0 security audit. Violating them re-introduces XSS, SOQL injection, or postMessage hijacking risks.

**How to apply:** Before any new feature touches DocGenDataRetriever, the PDF engine, or Handlebars rendering, re-read the current state of these files to ensure the hardening layers are still intact.
