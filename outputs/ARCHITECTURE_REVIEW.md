# DocGen Architecture Review

**Date:** 2026-04-25
**Package:** SalesforceDocGen (Document Generation for Salesforce)
**Reviewer:** Claude Code (Architectural Analysis)
**Scope:** Full codebase review covering PDF generation, API integrations, Lightning UX, security, and code quality.

---

## 1. Executive Summary

### Overview
DocGen is a Salesforce unmanaged package that enables users to generate documents (Word, PowerPoint, HTML) by merging Salesforce record data into templates. It supports single-record generation via Lightning Web Components, bulk generation via batch Apex, and an e-signature workflow via Experience Cloud.

### Major Strengths
1. **Dual Rendering Architecture** — Client-side (browser) for interactive use and server-side (Apex) for bulk operations provides flexibility.
2. **Template Versioning** — Built-in version control with active version management allows safe template iteration.
3. **Query Builder UX** — The recursive visual query builder with field selection, parent lookups, child relationships, and live preview is sophisticated and user-friendly.
4. **Flow Integration** — Invocable methods for both single and bulk generation enable declarative automation.
5. **Signature Audit Trail** — SHA-256 hashing and audit records provide tamper evidence for signed documents.

### Critical Issues
1. **Self-Referential Loopback API Call** — The package makes HTTP callouts back into the same Salesforce org to retrieve PDF renditions, requiring an Auth Provider with a **hardcoded Consumer Key** and a Named Credential with a **hardcoded org URL**. This is a security risk and deployment blocker.
2. **Insufficient Test Coverage** — Only 4 test methods exist in the entire package. Most critical classes (batch, queueable, signature service) have zero coverage.
3. **Massive Code Duplication** — The client-side document generation logic (`flattenData`, `base64ToUtf8String`, Handlebars helpers, docxtemplater init) is copy-pasted between `docGenRunner.js` and `docGenAdmin.js`.
4. **Security Gaps** — Dynamic SOQL construction lacks comprehensive injection protection; `without sharing` classes bypass security without clear documentation of why; hardcoded credentials in metadata.
5. **No Bulk Error Detail** — Batch failures are only counted, not logged per record.

---

## 2. Current Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SALESFORCE ORG                                 │
│                                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │   LWC Pages  │────▶│  DocGenController │───▶│ DocGenService │          │
│  │ (Runner/Admin)│    │  (Apex)      │     │  (Apex)       │                │
│  └──────────────┘     └──────────────┘     └──────┬───────┘                │
│         │                                          │                        │
│         │                    ┌─────────────────────┘                        │
│         │                    ▼                                              │
│         │            ┌──────────────┐     ┌──────────────┐                 │
│         │            │DocGenDataRetriever│ │DocGenTemplateManager│            │
│         │            │  (Dynamic SOQL)   │ │  (ContentVersion)   │            │
│         │            └──────────────┘     └──────────────┘                 │
│         │                                                                   │
│         ▼                    ┌────────────────────────────────────┐        │
│  ┌──────────────┐            │          BULK PATH                 │        │
│  │ DocGenPDFEngine│         │  DocGenBatch ──▶ DocGenService      │        │
│  │  (VF Page)   │            │  (batch size: 10)                   │        │
│  │  iframe      │            └────────────────────────────────────┘        │
│  └──────┬───────┘                                                           │
│         │                                                                   │
│         │         ┌────────────────────────────────────────────────────┐   │
│         │         │          PDF RENDITION PATH                        │   │
│         │         │  DocGenRenditionService ──▶ HTTP Callout          │   │
│         │         │       │                    (Named Credential       │   │
│         │         │       ▼                     "DocGen_Loopback")       │   │
│         │         │  Platform Event ──▶ Queueable ──▶ Connect API      │   │
│         │         │  (/connect/files/{id}/rendition?type=PDF)          │   │
│         │         └────────────────────────────────────────────────────┘   │
│         │                                                                   │
│         │         ┌────────────────────────────────────────────────────┐   │
│         │         │          SIGNATURE PATH                            │   │
│         │         │  DocGenSignatureSender ──▶ Signature Request       │   │
│         │         │       │                                            │   │
│         │         │       ▼                                            │   │
│         │         │  Experience Cloud Flow ──▶ Signature Pad LWC     │   │
│         │         │       │                                            │   │
│         │         │       ▼                                            │   │
│         │         │  DocGenSignatureFinalizer ──▶ DocGenSignatureService│   │
│         │         │  (stamp DOCX + enqueue PDF rendition)              │   │
│         │         └────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Inventory

| Category | Count | Key Artifacts |
|----------|-------|---------------|
| Apex Classes | 21 | DocGenController, DocGenService, DocGenBatch, DocGenRenditionQueueable, DocGenSignatureService, DocGenSignatureController, DocGenSignatureFinalizer, DocGenSignatureSubmitter, DocGenSignatureValidator, DocGenSignatureSenderController, DocGenAuthenticatorController, DocGenSetupController, DocGenBulkController, DocGenBulkFlowAction, DocGenFlowAction, DocGenDataRetriever, DocGenTemplateManager, DocGenRenditionService, DocGenException, LoopbackTestQueueable |
| LWC Components | 14 | docGenAdmin, docGenRunner, docGenQueryBuilder, docGenQueryNode, docGenFilterBuilder, docGenSignaturePad, docGenSignatureSender, docGenAuthenticator, docGenSetupWizard, docGenWelcome, docGenTitleEditor, docGenSharing, docGenBulkRunner, docGenPreviewModal, pdfjsViewer, docGenPdfUtils |
| Aura Apps | 2 | DocGenSignOut, DocGenVerifyApp |
| Visualforce Pages | 3 | DocGenPDFEngine, DocGenSign, DocGenVerify |
| Custom Objects | 7 | DocGen_Template__c, DocGen_Template_Version__c, DocGen_Job__c, DocGen_Saved_Query__c, DocGen_Signature_Request__c, DocGen_Signature_Audit__c, DocGen_Settings__c |
| Platform Events | 1 | DocGen_Rendition_Event__e |
| Static Resources | 12 | docxtemplater, handlebars, html2pdf, jszip, pizzip, mammoth, filesaver, pdfjs, DocGenEngine (bundle), sample docs |
| Flows | 1 | DocGen_Signature_Submission |
| Permission Sets | 3 | DocGen_Admin, DocGen_User, DocGen_Guest_Signature |

---

## 3. Detailed Findings

### A. PDF Generation System

#### Current Implementation
The package supports three template types with different rendering paths:

**1. Word (.docx) — Server-Side (Bulk & Flow)**
- `DocGenService.processXml()` performs string-based placeholder replacement in the OOXML
- Uses `Compression.ZipReader/ZipWriter` to manipulate the ZIP structure
- Supports loops (`{#Key}...{/Key}`) with smart table row expansion
- Handles child record lists by repeating XML sections

**2. Word (.docx) — Client-Side (LWC)**
- Uses `docxtemplater` library loaded via static resource
- More robust templating than server-side string replacement
- Generates DOCX blob, optionally sends to PDF Engine iframe

**3. HTML — Client-Side Only**
- Uses `Handlebars` library for templating
- Rendered HTML is sent to `DocGenPDFEngine` Visualforce page via `postMessage`
- VF page uses `html2pdf.js` or `docx-preview.js` to render and convert to PDF

**4. PowerPoint (.pptx)**
- Same server-side/client-side split as Word
- Only slides XML is processed for placeholder replacement

#### Strengths
- **Browser-side PDF conversion** avoids governor limits on CPU/heap for complex documents
- The `docx-preview.js` path provides high-fidelity DOCX-to-PDF rendering
- Template type flexibility (Word/HTML/PPT) accommodates different user skill levels

#### Limitations & Issues
1. **HTML Templates Fail Server-Side** — `DocGenService.generateDocument()` throws an exception for HTML templates (`"HTML templates are only supported when generating from a single record"`). This means bulk generation and Flow actions cannot use HTML templates, creating a confusing user experience inconsistency.
2. **Server-Side XML Parsing is Fragile** — `processXml()` uses primitive string scanning (`indexOf('{')`) rather than a proper XML parser. Complex nested structures, curly braces in content, or malformed tags will break rendering.
3. **No Row Expansion for PowerPoint** — The smart table row expansion logic only checks for `<w:tr>` (Word table rows). PowerPoint tables use different OOXML structure and are not handled.
4. **PDF Engine Relies on Timeouts** — `DocGenPDFEngine.page` uses `setTimeout(500)` and `setTimeout(1000)` to wait for rendering. This is unreliable on slow networks or complex documents.
5. **Blob Transfer Over postMessage** — Large documents passing ArrayBuffers through `postMessage` between LWC and VF iframe could hit browser memory limits or serialization issues.

#### Refactoring Recommendations
1. **Unify client-side generation** — Move all single-record generation to the client-side path (docxtemplater/Handlebars) and eliminate the server-side XML parser for Word/HTML.
2. **For bulk, consider Queueable with callout** — If server-side PDF is truly needed, use an external PDF microservice rather than the loopback callout.
3. **Add proper OOXML parsing** — If server-side Word generation must remain, use an XML DOM parser (Apex doesn't have one natively; consider a custom parser or offload to client).

---

### B. API Integration & Self-Referential Calls

#### Inventory of API Callouts

| Class | Endpoint | Purpose | Called From |
|-------|----------|---------|-------------|
| `DocGenRenditionService.capturePdfRendition()` | `/services/data/v63.0/connect/files/{fileId}/rendition?type=PDF` | Retrieve PDF rendition of a ContentVersion | `DocGenRenditionQueueable` |

#### The Loopback Problem

The package makes an **HTTP callout from Apex back into the same Salesforce org** to use the Connect API's file rendition endpoint. This is architecturally problematic:

**Why it exists:**
- Salesforce does not expose the Content rendition API as an Apex method
- The package needs to convert DOCX/PPTX to PDF after generation or signature stamping

**Why it's problematic:**
1. **Hardcoded Org URL** — `DocGen_Loopback.namedCredential-meta.xml` contains `https://click-less-academy-dev-ed.develop.my.salesforce.com`. Every deployment to a new org requires manual metadata update.
2. **Hardcoded Consumer Key** — `DocGen_Auth_Provider.authprovider-meta.xml` contains an actual connected app consumer key (`3MVG9GCMQoQ6rpzRPQ7XyvUJAs56dc4LAMayBMsZAkQ4AA3i7HVv4dEWEx18ynPyb9QhoAOPDfsARWQS7V50d`). This is a credential leak.
3. **Auth Complexity** — The Auth Provider requires OAuth flow setup, callback URL configuration, and a Connected App in every target org.
4. **Governor Limits** — Each callout consumes callout limits. In bulk generation with 10 records per batch execute, if all request PDF, that's 10 callouts per execute.
5. **Async Only** — Callouts require async context, forcing the platform event + queueable pattern even for single-record generation.

#### Can it be eliminated?

**Yes, with tradeoffs:**

| Approach | Pros | Cons |
|----------|------|------|
| **Keep loopback, but dynamic URL** | Minimal code change | Still requires auth provider setup per org |
| **Use `PageReference.getContentAsPDF()`** | No callout needed; native Salesforce | Only works with Visualforce pages, not DOCX files |
| **Client-side PDF for everything** | No server callouts; better quality | Doesn't work in batch/flow contexts |
| **External PDF microservice** | Scalable, consistent | Adds infrastructure; network dependency |
| **Generate PDF directly in Apex** | No dependencies | Requires complex PDF library (not natively available) |

**Recommendation:** For the current architecture, the best near-term fix is to make the loopback URL dynamic using `Url.getOrgDomainUrl()` and eliminate the hardcoded consumer key from metadata. Long-term, move PDF generation entirely client-side for interactive use and accept native format output for batch/flow.

---

### C. Lightning Page Layouts & UX

#### Component Inventory

| LWC | Purpose | Key Features |
|-----|---------|--------------|
| `docGenAdmin` | Template management dashboard | CRUD templates, version control, query builder, test generation |
| `docGenRunner` | Record page action component | Select template, generate/preview document, save to record |
| `docGenQueryBuilder` | Visual SOQL builder | Object selection, field picker, parent/child relationships, live preview |
| `docGenQueryNode` | Recursive tree node for query builder | Field lists, child/parent expansion |
| `docGenFilterBuilder` | WHERE clause builder | Filter conditions for bulk generation |
| `docGenSignaturePad` | Canvas signature capture | Drawing, touch support, flow integration |
| `docGenSignatureSender` | Send signature request | Select document, enter signer details, generate URL |
| `docGenBulkRunner` | Bulk generation UI | Template selection, condition entry, job tracking |
| `docGenPreviewModal` | PDF preview modal | Uses pdf.js for rendering |
| `docGenSetupWizard` | Package setup | Configure Experience Cloud URL |

#### UX Analysis

**Strengths:**
1. **Template Admin is feature-rich** — Versioning, query builder, test generation, and sharing are all in one place.
2. **Query Builder is sophisticated** — Recursive parent/child relationship handling with real-time SOQL generation and preview is impressive.
3. **Tag generation** — Auto-generated merge field tags with copy-to-clipboard reduces user error.

**Issues:**
1. **Duplicated generation logic** — Both `docGenAdmin` and `docGenRunner` contain nearly identical document generation code (Handlebars setup, docxtemplater init, PDF engine messaging). Any bug fix or enhancement must be made in two places.
2. **Modal nesting** — The admin uses a full-screen modal for editing, which can feel overwhelming. The preview modal opens inside this modal, creating double-overlay issues on smaller screens.
3. **No loading states in query builder** — Field lists for large objects can take time to load; no skeleton or spinner is shown.
4. **Self-healing hack** — `docGenAdmin.js` line 690 contains a hardcoded hack: `if (this.editTemplateName === 'Sample Quote Template' ...)`. This is technical debt that should be removed.
5. **Clipboard fallback** — The copy-to-clipboard logic uses the deprecated `document.execCommand('copy')` approach as a fallback. Modern browsers support the Clipboard API; the fallback can be simplified.
6. **PDF Preview limited to PDF** — The preview button only works for PDF output. For native formats, it falls back to download with a warning toast. Users may find this inconsistent.
7. **Error messages are technical** — Error toasts often expose Apex exception messages directly (e.g., `"PDF Engine Error: ..."`). These should be user-friendly.

#### Accessibility Assessment
- Signature pad has `preventDefault()` on touch events but no ARIA labels for screen readers
- Query builder nodes don't announce expansion/collapse state
- No keyboard shortcuts for common actions (generate, save, copy tag)

---

### D. Code Quality Assessment

**Overall Score: 5/10**

#### Areas of Strength
1. **Consistent naming** — Classes follow `DocGen{Purpose}` convention
2. `with sharing` on most controller classes
3. `USER_MODE` used in SOQL queries where appropriate
4. Separation of concerns between Controller, Service, and Data layers

#### Areas Needing Improvement

**1. Governor Limits**
- `DocGenController.getObjectOptions()` calls `Schema.getGlobalDescribe()` on every invocation. For cached methods, this still runs once per session but could be avoided with client-side caching.
- `DocGenBatch` uses batch size 10 to avoid CPU limits during ZIP processing. This is very small for bulk operations and will take a long time for large datasets.
- `DocGenRenditionQueueable` processes one CV per callout iteration. If 10 CVs are queued, it makes 10 separate callouts in one execute. This could hit the 100 callout limit quickly.

**2. Security**
- **Dynamic SOQL in `DocGenBulkController.validateFilter()`**: `query += ' WHERE ' + condition;` — The `condition` parameter comes from user input and is only sanitized with `String.escapeSingleQuotes()`. This does not protect against all injection attacks (e.g., `OR 1=1`, subqueries, UNION attacks).
- **Dynamic SOQL in `DocGenBatch.start()`**: Same issue — the `condition` field from `DocGen_Job__c` is concatenated directly into the query string.
- **Hardcoded credentials** in metadata (Auth Provider consumer key, Named Credential URL).
- **`without sharing` classes lack documentation**: `DocGenSignatureService`, `DocGenSignatureController`, `DocGenAuthenticatorController`, `DocGenRenditionQueueable` all use `without sharing`. Some of this is necessary for guest user access, but it should be clearly documented with `@description` explaining why.

**3. Error Handling**
- Many catch blocks just do `System.debug('...')` and swallow the exception or throw a generic `AuraHandledException`.
- `DocGenBatch.execute()` catches per-record exceptions but only increments a counter. There's no way for an admin to know WHICH records failed or why.
- `DocGenRenditionQueueable.execute()` has better error logging via `logRenditionError()`, but the audit record creation is a side effect that may confuse users.

**4. Code Duplication**
- The `flattenData()` method is identical in `docGenRunner.js` and `docGenAdmin.js`.
- The Handlebars helper registration (`each`, `ifList`) is copy-pasted between the two components.
- The docxtemplater initialization config is duplicated.
- The `base64ToUtf8String()` utility is duplicated.
- **Recommendation:** Extract all shared client-side logic into `docGenPdfUtils.js` or a new `docGenGenerationUtils.js` module.

**5. Dead Code & Comments**
- `DocGenController` line 383: `// Sample data creation method removed per cleanup request.`
- `DocGenAdmin.js` lines 169-173: Commented-out `handleInstallSample()` method.
- `DocGenSign.page` line 115-118: Comments state the page is "deprecated for active signing but remains as a fallback."
- `DocGenRenditionService` line 298-303: `// EXPERIMENT: Background PDF Rendition Hack` — Comments suggest experimental code that has become production.

---

### E. Missing Components & Gaps

#### Testing
- **Only 4 test methods** in `DocGenTests.cls`
- No tests for: `DocGenBatch`, `DocGenRenditionQueueable`, `DocGenSignatureService`, `DocGenSignatureController`, `DocGenRenditionService`, `DocGenDataRetriever`, `DocGenTemplateManager`, `DocGenBulkController`, `DocGenSetupController`, any Flow Action class
- No negative test cases (invalid template, missing file, bad query)
- No test for the LWS proxy workaround

#### Error Handling
- No retry mechanism for failed batch records (only a count is kept)
- No dead-letter queue for failed PDF renditions beyond the audit log
- No notification system for job completion (email, Chatter, custom notification)

#### Documentation
- No inline ApexDocs for most public methods
- No architecture documentation in the package
- README exists but focuses on installation, not development

#### Functionality Gaps
- No scheduling capability for bulk jobs (must be triggered manually or via Flow)
- No email delivery of generated documents
- No template folder/organization beyond the `Category__c` field
- No bulk delete or archive for old generated documents
- No usage analytics (how many times a template was used)

#### DevOps/Deployment
- No CI/CD pipeline configuration
- No automated test execution scripts
- `sfdx-project.json` has no package name or version info for 2GP
- `manifest/package.xml` exists but may be outdated

---

## 4. Prioritized Recommendations

### Critical (Fix Immediately)

| # | Title | Category | Current State | Proposed State | Effort | Impact |
|---|-------|----------|---------------|----------------|--------|--------|
| 1 | **Remove Hardcoded Consumer Key** | Security | Auth Provider metadata contains real consumer key | Use placeholder + setup instructions | Small | Prevents credential leak in version control |
| 2 | **Remove Hardcoded Org URL** | Security | Named Credential has dev org URL | Use `Url.getOrgDomainUrl()` in setup or manual config | Small | Enables deployment to any org |
| 3 | **Fix Dynamic SOQL Injection Risk** | Security | `validateFilter()` and batch `start()` concatenate user input into SOQL | Validate condition against allowlist or use parameterized queries | Medium | Prevents data exfiltration |
| 4 | **Add Comprehensive Test Coverage** | Testing | 4 tests total | Minimum 75% coverage for all classes, including negative cases | Large | Required for production deployment |

### High Priority

| # | Title | Category | Current State | Proposed State | Effort | Impact |
|---|-------|----------|---------------|----------------|--------|--------|
| 5 | **Extract Shared Client Logic** | Code Quality | `flattenData`, Handlebars setup, docxtemplater init duplicated in 2+ LWCs | Single utility module (`docGenGenerationUtils.js`) | Medium | Reduces bug surface, eases maintenance |
| 6 | **Add Per-Record Error Logging to Batch** | Reliability | Batch only counts failures | Log record ID + error message to `DocGen_Job__c` or custom object | Small | Enables admin troubleshooting |
| 7 | **Document `without sharing` Classes** | Security | 5+ classes bypass sharing without explanation | Add `@description` explaining the guest user / system context requirement | Small | Security audit compliance |
| 8 | **Remove Deprecated Visualforce Page** | Maintenance | `DocGenSign.page` is deprecated but deployed | Remove page, controller methods, and Aura apps if unused | Medium | Reduces package size and confusion |

### Medium Priority

| # | Title | Category | Current State | Proposed State | Effort | Impact |
|---|-------|----------|---------------|----------------|--------|--------|
| 9 | **Unify HTML Template Generation** | Architecture | HTML templates fail server-side | Add server-side HTML rendering (even if limited) or document client-only restriction clearly | Medium | Eliminates user confusion |
| 10 | **Add Job Completion Notifications** | UX | User must manually poll for batch status | Push notification or email on completion | Medium | Better user experience |
| 11 | **Replace `setTimeout` in PDF Engine** | Reliability | PDF rendering uses fixed timeouts | Use DOM mutation observer or library callback | Medium | More reliable rendering |
| 12 | **Add Input Validation to Signature Flow** | Security | Signer email not validated | Add regex validation and basic sanitization | Small | Prevents malformed data |

### Low Priority

| # | Title | Category | Current State | Proposed State | Effort | Impact |
|---|-------|----------|---------------|----------------|--------|--------|
| 13 | **Add Template Usage Analytics** | Feature | No visibility into template usage | Custom object or field to track generation count | Medium | Helps admins manage templates |
| 14 | **Modernize Clipboard API** | UX | Uses deprecated `execCommand('copy')` | Use `navigator.clipboard` with minimal fallback | Small | Cleaner code |
| 15 | **Remove Self-Healing Hack** | Code Quality | Hardcoded sample template name check | Remove or make generic | Small | Eliminates technical debt |

---

## 5. DocuSign Integration Impact

When DocuSign Apex Toolkit is integrated, the following architectural touchpoints will be affected:

1. **Signature Flow Redirection** — The current custom signature flow (canvas drawing + DOCX stamping) could be replaced or augmented with DocuSign embedded signing. The `DocGenSignatureRequest__c` object would need new fields for DocuSign envelope ID and status.
2. **PDF Rendition Path** — DocuSign requires PDF documents. The current loopback rendition callout could potentially be replaced by DocuSign's document conversion, but this is unlikely. More realistically, the PDF generation path must remain stable.
3. **Audit Trail** — DocuSign provides its own certificate of completion. The `DocGen_Signature_Audit__c` object should store both the internal hash AND the DocuSign envelope ID for cross-reference.
4. **Authentication** — DocuSign JWT auth will need separate Named Credentials and External Credentials, adding to the auth complexity already present.
5. **Template Mapping** — DocuSign template roles would need to map to DocGen template data. Consider adding a `DocuSign_Template_Id__c` field to `DocGen_Template__c`.

---

## 6. Next Steps

### Phase 1 (Immediate — 1-2 weeks)
1. Remove hardcoded credentials from metadata
2. Fix dynamic SOQL injection vulnerability
3. Add `@description` to all `without sharing` classes
4. Extract shared client logic into utility module
5. Remove deprecated Visualforce page and related Aura apps

### Phase 2 (Short-term — 2-4 weeks)
1. Write comprehensive test suite (target 85%+ coverage)
2. Add per-record error logging to batch jobs
3. Add input validation to signature flow
4. Document the loopback callout architecture and setup requirements

### Phase 3 (Long-term — 1-2 months)
1. Evaluate replacing loopback callout with client-side PDF for all interactive use
2. Add job completion notifications
3. Add template usage analytics
4. Consider external PDF microservice for bulk operations
5. Plan DocuSign integration architecture

---

*End of Architecture Review*
