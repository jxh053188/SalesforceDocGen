# DocGen Code Inventory

**Date:** 2026-04-25

---

## Apex Classes

| # | Class | Purpose | Sharing | Lines | Test Coverage | Dependencies |
|---|-------|---------|---------|-------|---------------|--------------|
| 1 | `DocGenController` | Main controller for LWC interactions. Handles template CRUD, schema methods, sharing, and document data retrieval. | `with sharing` | 458 | Partial (via `DocGenTests`) | `DocGenDataRetriever`, `DocGenTemplateManager`, `DocGenException` |
| 2 | `DocGenService` | Core document generation engine. Server-side ZIP/XML processing for Word/PowerPoint. | `with sharing` | 322 | Partial (via `DocGenTests`) | `DocGenController`, `DocGenRenditionService`, `DocGenException` |
| 3 | `DocGenDataRetriever` | Executes dynamic SOQL and maps results to nested Maps. | `with sharing` | 86 | None | None |
| 4 | `DocGenTemplateManager` | Retrieves template file ContentVersion (active version or latest fallback). | `with sharing` | 71 | Partial (via `DocGenTests`) | None |
| 5 | `DocGenBatch` | Batchable for bulk document generation. | `global with sharing` | 74 | None | `DocGen_Job__c`, `DocGenService`, `DocGenRenditionService` |
| 6 | `DocGenRenditionQueueable` | Queueable that processes PDF rendition callouts with retry logic (max 10). | `with sharing` | 128 | None | `DocGenRenditionService`, `ContentVersion`, `DocGen_Signature_Audit__c` |
| 7 | `DocGenRenditionService` | Manages pending renditions, makes loopback HTTP callout to Connect API, logs errors to audit. | `with sharing` | 115 | None | `DocGen_Rendition_Event__e`, `DocGen_Signature_Audit__c`, Named Credential `DocGen_Loopback` |
| 8 | `DocGenSignatureService` | Stamps signatures into DOCX, handles submission, creates audit trail, enqueues rendition. | `without sharing` | 153 | None | `DocGenRenditionService`, `ContentVersion`, `DocGen_Signature_Request__c`, `DocGen_Signature_Audit__c` |
| 9 | `DocGenSignatureController` | Controller for signature experience. Validates tokens, fetches documents, stamps + returns base64, finalizes upload. | `without sharing` | 218 | None | `DocGenSignatureService`, `DocGenController`, `ContentVersion`, `ContentDistribution` |
| 10 | `DocGenSignatureFinalizer` | Invocable method wrapper for Flow. Runs `handleSignatureSubmission` in system context. | `without sharing` | 19 | None | `DocGenSignatureService` |
| 11 | `DocGenSignatureSubmitter` | Invocable method for Flow to submit signed signature data. | `without sharing` | 34 | None | `DocGenSignatureService` |
| 12 | `DocGenSignatureValidator` | Invocable method for Flow to validate a secure token. | `without sharing` | 36 | None | `DocGenSignatureController` |
| 13 | `DocGenSignatureSenderController` | Controller for signature request creation. Gets related docs, generates secure token, creates request record. | `with sharing` | 62 | None | `DocGen_Signature_Request__c`, `DocGen_Settings__c`, `ContentVersion` |
| 14 | `DocGenAuthenticatorController` | Verifies document hash against audit records for public document verification. | `without sharing` | 37 | None | `DocGen_Signature_Audit__c` |
| 15 | `DocGenBulkController` | Controller for bulk generation UI. Validates filters, submits jobs, manages saved queries. | `with sharing` | 80 | None | `DocGen_Job__c`, `DocGenBatch`, `DocGen_Saved_Query__c` |
| 16 | `DocGenSetupController` | Simple controller for setup wizard. Gets org URL and custom settings. | `with sharing` | 19 | None | `DocGen_Settings__c` |
| 17 | `DocGenFlowAction` | Invocable method for Flow to generate a single document. | `global with sharing` | 42 | None | `DocGenService`, `DocGenRenditionService` |
| 18 | `DocGenBulkFlowAction` | Invocable method for Flow to start bulk generation. | `global with sharing` | 38 | None | `DocGenBulkController` |
| 19 | `DocGenException` | Custom exception class for package. | N/A | 2 | N/A | None |
| 20 | `LoopbackTestQueueable` | Test class for loopback callout (appears to be utility). | Unknown | Unknown | None | Unknown |
| 21 | `DocGenTests` | Main test class. Covers basic generation, templates, versioning, HTML type handling. | `private` | 157 | 4 methods | `DocGenController`, `DocGenService`, `DocGenTemplateManager` |
| 22 | `DocGenBulkTests` | Test class for bulk operations. | Unknown | Unknown | Unknown | `DocGenBulkController` |
| 23 | `DocGenSharingTests` | Test class for template sharing. | Unknown | Unknown | Unknown | `DocGenController` |
| 24 | `DocGenBulkFlowActionTest` | Test class for bulk Flow action. | Unknown | Unknown | Unknown | `DocGenBulkFlowAction` |

**Total Apex Classes:** 24
**Total Lines (approximate):** ~1,900
**Test Coverage:** Very low (~15-20% estimated; only 4 tests in main test class)

---

## Lightning Web Components

| # | Component | Purpose | API | Key Features | Bundle Size (est.) |
|---|-----------|---------|-----|------------|-------------------|
| 1 | `docGenAdmin` | Template management dashboard | `NavigationMixin` | CRUD, versioning, query builder, test generation, sharing | ~1,050 lines |
| 2 | `docGenRunner` | Record page action for document generation | `@api recordId, objectApiName` | Template selection, generate/preview, save to record | ~540 lines |
| 3 | `docGenQueryBuilder` | Visual SOQL builder | `@api selectedObject, queryMetadata, templateType` | Object search, field picker, parent/child recursion, tag generator, preview | ~640 lines |
| 4 | `docGenQueryNode` | Recursive tree node for query builder | `@api nodeConfig, globalState` | Field lists, child/parent expansion, filter builder | ~200 lines |
| 5 | `docGenFilterBuilder` | WHERE clause builder | `@api objectApiName` | Filter conditions with operators | ~150 lines |
| 6 | `docGenSignaturePad` | Canvas signature capture | `@api token, recordId, documentUrl` | Drawing, touch support, Flow integration, auto-advance | ~160 lines |
| 7 | `docGenSignatureSender` | Send signature request | `@api recordId` | Document selection, signer details, URL generation | ~105 lines |
| 8 | `docGenAuthenticator` | Public document verifier | N/A | Hash input, verification result display | ~80 lines |
| 9 | `docGenSetupWizard` | Package setup wizard | N/A | Configure Experience Cloud URL | ~80 lines |
| 10 | `docGenWelcome` | Welcome/landing screen | N/A | Onboarding UI | ~60 lines |
| 11 | `docGenTitleEditor` | Document title format editor | `@api titleFormat` | Merge field picker for filenames | ~80 lines |
| 12 | `docGenSharing` | Template sharing modal | `@api templateId` | User/group search, share management | ~150 lines |
| 13 | `docGenBulkRunner` | Bulk generation UI | N/A | Template selection, condition entry, job polling | ~200 lines |
| 14 | `docGenPreviewModal` | PDF preview modal | `LightningModal` | Blob URL display, download button | ~50 lines |
| 15 | `pdfjsViewer` | PDF.js wrapper | N/A | PDF rendering viewer | ~100 lines |
| 16 | `docGenPdfUtils` | Shared PDF generation utility | ES module exports | `generatePdfFromIframe()` promise wrapper | ~75 lines |

**Total LWC Components:** 16
**Total Lines (approximate):** ~3,220

---

## Aura Components

| # | Component | Purpose | Status |
|---|-----------|---------|--------|
| 1 | `DocGenSignOut` | Lightning Out application for signature page | Deprecated |
| 2 | `DocGenVerifyApp` | Lightning Out application for verifier page | Active |

---

## Visualforce Pages

| # | Page | Controller | Purpose | Status |
|---|------|-----------|---------|--------|
| 1 | `DocGenPDFEngine` | None (static) | PDF rendering engine iframe target | Active |
| 2 | `DocGenSign` | `DocGenSignatureController` | Legacy signature page | Deprecated |
| 3 | `DocGenVerify` | None | Public document verifier | Active |

---

## Custom Objects

| # | Object | Key Fields | Purpose |
|---|--------|-----------|---------|
| 1 | `DocGen_Template__c` | Name, Base_Object_API__c, Type__c, Output_Format__c, Query_Config__c, Query_Metadata__c, Category__c, Description__c, Test_Record_Id__c, Document_Title_Format__c | Master template record |
| 2 | `DocGen_Template_Version__c` | Template__c, Content_Version_Id__c, Is_Active__c, Query_Config__c, Query_Metadata__c, Type__c, Base_Object_API__c, Category__c, Description__c | Version snapshot of template |
| 3 | `DocGen_Job__c` | Template__c, Query_Condition__c, Status__c, Total_Records__c, Success_Count__c, Error_Count__c | Bulk generation job tracking |
| 4 | `DocGen_Saved_Query__c` | DocGen_Template__c, Name, Description__c, Query_Condition__c | Reusable filter conditions |
| 5 | `DocGen_Signature_Request__c` | Signer_Name__c, Signer_Email__c, Source_Document_Id__c, Related_Record_Id__c, Secure_Token__c, Status__c | Signature request record |
| 6 | `DocGen_Signature_Audit__c` | Signature_Request__c, Signed_Date__c, Document_Hash_SHA256__c, IP_Address__c, User_Agent__c, Error_Message__c | Tamper-evident audit trail |
| 7 | `DocGen_Settings__c` | Experience_Site_Url__c | Org-wide configuration |
| 8 | `DocGen_Rendition_Event__e` | Source_CV_Id__c, Related_Record_Id__c | Platform event for async PDF rendition |

---

## Static Resources

| # | Resource | Purpose | Size |
|---|----------|---------|------|
| 1 | `DocGenEngine` | Bundle: html2pdf.js, docx-preview.js, jszip.min.js, index.html | ~2MB |
| 2 | `docxtemplater` | Word document templating engine | ~500KB |
| 3 | `handlebars` | HTML templating engine | ~100KB |
| 4 | `html2pdf` | HTML to PDF conversion library | ~500KB |
| 5 | `jszip` | ZIP file manipulation | ~100KB |
| 6 | `pizzip` | ZIP library for docxtemplater | ~100KB |
| 7 | `filesaver` | Browser file download utility | ~20KB |
| 8 | `mammoth` | DOCX to HTML converter | ~200KB |
| 9 | `pdfjs` | PDF.js viewer library | ~3MB |
| 10 | `DocGenSampleDoc` | Sample .docx template | ~20KB |
| 11 | `DocGenSampleOpp` | Sample Opportunity template | ~20KB |
| 12 | `DocGenSamplePPT` | Sample PowerPoint template | ~50KB |

**Total Static Resource Size:** ~6.6MB

---

## Configuration Artifacts

| # | Artifact | Purpose | Key Details |
|---|----------|---------|-------------|
| 1 | `DocGen.app-meta.xml` | Custom App | Document Generation app |
| 2 | `DocGen_Loopback.namedCredential-meta.xml` | Named Credential | Loopback callout to same org |
| 3 | `DocGen_Loopback_Auth.externalCredential-meta.xml` | External Credential | OAuth for loopback |
| 4 | `DocGen_Auth_Provider.authprovider-meta.xml` | Auth Provider | **Hardcoded consumer key** |
| 5 | `DocGen_Signatures.site-meta.xml` | Site | Experience Cloud site for signatures |
| 6 | `DocGen_Admin.permissionset-meta.xml` | Permission Set | Full admin access |
| 7 | `DocGen_User.permissionset-meta.xml` | Permission Set | Standard user access |
| 8 | `DocGen_Guest_Signature.permissionset-meta.xml` | Permission Set | Guest user access for signing |
| 9 | `DocGen_Signature_Submission.flow-meta.xml` | Flow | Experience Cloud signature flow |
| 10 | `DocGenRenditionTrigger.trigger` | Trigger | After insert on Platform Event |

---

## Code Metrics Summary

| Metric | Value |
|--------|-------|
| Total Apex Classes | 24 |
| Apex Lines of Code (approx.) | ~1,900 |
| Total LWC Components | 16 |
| LWC Lines of Code (approx.) | ~3,220 |
| Total Visualforce Pages | 3 |
| Total Aura Components | 2 |
| Total Custom Objects | 7 (+ 1 Platform Event) |
| Total Static Resources | 12 |
| Total Permission Sets | 3 |
| Total Flows | 1 |
| Total Triggers | 1 |
| Test Methods | 4 (in main test class) |
| Estimated Test Coverage | ~15-20% |
