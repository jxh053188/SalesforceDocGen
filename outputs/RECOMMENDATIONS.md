# DocGen Prioritized Recommendations

**Date:** 2026-04-25

---

## Critical

| # | Title | Category | Current State | Proposed State | Effort | Impact | Implementation Notes | Dependencies |
|---|-------|----------|---------------|----------------|--------|--------|----------------------|--------------|
| 1 | Remove Hardcoded Consumer Key | Security | Auth Provider metadata contains real consumer key (`3MVG9GCMQoQ6rpzRPQ7XyvUJAs56dc4LAMayBMsZAkQ4AA3i7HVv4dEWEx18ynPyb9QhoAOPDfsARWQS7V50d`) | Replace with `Placeholder_Value` and document setup steps | Small | Prevents credential leak in version control; security compliance | Edit `DocGen_Auth_Provider.authprovider-meta.xml`; add setup instructions to README | None |
| 2 | Remove Hardcoded Org URL | Security | Named Credential `DocGen_Loopback` has `https://click-less-academy-dev-ed.develop.my.salesforce.com` | Use `Url.getOrgDomainUrl()` in setup wizard or require manual post-deploy config | Small | Enables deployment to any org without metadata modification | Update `DocGenSetupController` to prompt for loopback URL; update Named Credential via Metadata API or document manual step | None |
| 3 | Fix Dynamic SOQL Injection Risk | Security | `DocGenBulkController.validateFilter()` and `DocGenBatch.start()` concatenate user-supplied `condition` directly into SOQL | Validate `condition` against allowlist pattern or parse into structured filters | Medium | Prevents data exfiltration and SOQL injection attacks | Consider using the query builder's structured filter format instead of raw SOQL strings | None |
| 4 | Add Comprehensive Test Coverage | Testing | Only 4 test methods exist | Minimum 75% coverage for all classes; include negative tests | Large | Required for production deployment; catches regressions | Prioritize: DocGenService, DocGenBatch, DocGenRenditionQueueable, DocGenSignatureService | None |

## High

| # | Title | Category | Current State | Proposed State | Effort | Impact | Implementation Notes | Dependencies |
|---|-------|----------|---------------|----------------|--------|--------|----------------------|--------------|
| 5 | Extract Shared Client Logic | Code Quality | `flattenData`, Handlebars setup, docxtemplater init, `base64ToUtf8String` duplicated in `docGenRunner.js` and `docGenAdmin.js` | Single utility module (`docGenGenerationUtils.js`) | Medium | Reduces bug surface; single point of fix for generation issues | Create new module; export functions; update imports in both components | None |
| 6 | Add Per-Record Error Logging to Batch | Reliability | Batch only increments `failCount`; no record-level detail | Log record ID + error to `DocGen_Job__c.Error_Details__c` (new long text field) or child object | Small | Enables admin to identify and fix failing records | Add `Error_Details__c` field to `DocGen_Job__c`; append JSON array of failures in `execute()` | None |
| 7 | Document `without sharing` Classes | Security | `DocGenSignatureService`, `DocGenSignatureController`, `DocGenAuthenticatorController`, `DocGenRenditionQueueable` lack explanation for `without sharing` | Add ApexDoc `@description` explaining guest user / system context need | Small | Security audit compliance; future maintainers understand intent | Add comments like "Uses without sharing because Experience Cloud guest users cannot access ContentVersion with default sharing" | None |
| 8 | Remove Deprecated Visualforce Page | Maintenance | `DocGenSign.page` is deprecated per inline comments but still deployed | Remove page, controller methods, and Aura apps `DocGenSignOut`/`DocGenVerifyApp` if unused | Medium | Reduces package size; eliminates dead code | Verify no active references; delete files; update permission sets | None |

## Medium

| # | Title | Category | Current State | Proposed State | Effort | Impact | Implementation Notes | Dependencies |
|---|-------|----------|---------------|----------------|--------|--------|----------------------|--------------|
| 9 | Unify HTML Template Generation | Architecture | HTML templates throw exception in `DocGenService.generateDocument()` | Either add server-side HTML rendering or clearly document client-only restriction in UI | Medium | Eliminates user confusion when HTML templates fail in Flow/bulk | Add validation in Flow action classes with clear error message; or implement server-side HTML rendering using Blob | None |
| 10 | Add Job Completion Notifications | UX | User must manually click Refresh to check batch status | Send email or custom notification when job completes | Medium | Better user experience; reduces polling load | Add `Notification__c` field to `DocGen_Job__c`; send in `finish()` method | None |
| 11 | Replace `setTimeout` in PDF Engine | Reliability | `DocGenPDFEngine.page` uses `setTimeout(500)` and `setTimeout(1000)` to wait for rendering | Use DOM mutation observer or library completion callback | Medium | More reliable rendering; prevents premature PDF capture | Research `docx-preview.js` and `html2pdf.js` callback APIs | None |
| 12 | Add Input Validation to Signature Flow | Security | Signer email not validated; token format not checked | Add regex validation for email; validate token format (hex string) | Small | Prevents malformed data; basic injection protection | Add validation in `DocGenSignatureSenderController.createSignatureRequest()` and `DocGenSignatureController.validateToken()` | None |

## Low

| # | Title | Category | Current State | Proposed State | Effort | Impact | Implementation Notes | Dependencies |
|---|-------|----------|---------------|----------------|--------|--------|----------------------|--------------|
| 13 | Add Template Usage Analytics | Feature | No visibility into which templates are used most | Add `Usage_Count__c` field to `DocGen_Template__c`; increment on generation | Medium | Helps admins manage template inventory | Update `DocGenService.generateDocument()` to increment counter | None |
| 14 | Modernize Clipboard API | UX | Uses deprecated `document.execCommand('copy')` with textarea fallback | Use `navigator.clipboard.writeText()` with minimal fallback | Small | Cleaner code; follows modern web standards | Update `docGenQueryBuilder.js` and `docGenSignatureSender.js` | None |
| 15 | Remove Self-Healing Hack | Code Quality | `docGenAdmin.js` line 690 hardcodes `Sample Quote Template` name check | Remove the hack; fix the underlying template query issue | Small | Eliminates technical debt | Remove the conditional; ensure sample template query is correct in metadata | None |
