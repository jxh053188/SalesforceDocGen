# Design Requirements: Remove Loopback Callout & Bulk Generation

**Date:** 2026-04-25
**Branch:** (to be created after approval)
**Option:** 7.1 from API Callout Analysis — Force all PDF generation client-side

---

## WHAT USER REQUESTED

1. Remove all Loopback Callout Infrastructure (dead code)
2. Remove Bulk Generation completely
3. Clean up ad-hoc scripts from project root
4. Implement cleanup recommendations from API_CALLOUT_ANALYSIS.md
5. Leave E-Signature Code untouched (except references to deleted components)
6. Update remaining code to only support client-side generation paths (DOCX output, not PDF via server)

---

## EXISTING METADATA REVIEW

- **Loopback chain**: `DocGenRenditionService` → `DocGenRenditionQueueable` → `DocGenRenditionTrigger` on `DocGen_Rendition_Event__e`. Uses Named Credential `DocGen_Loopback` → External Credential `DocGen_Loopback_Auth` → Auth Provider `DocGen_Auth_Provider`.
- **Bulk chain**: `DocGenBulkController` (Aura/LWC) → `DocGenBatch` → `DocGen_Job__c`. Also exposed via `DocGenBulkFlowAction` invocable.
- **References found in surviving code**:
  - `DocGenService.cls` calls `DocGenRenditionService.addPendingRendition()` in `saveFile()`.
  - `DocGenFlowAction.cls` calls `DocGenRenditionService.enqueueRenditions(true)`.
  - `DocGenSignatureService.cls` calls both `addPendingRendition()` and `enqueueRenditions()` in `handleSignatureSubmission()`.
  - `docGenWelcome.js` has `navigateToBulk()` pointing to `DocGen_Bulk_Gen` tab.
  - `docGenSetupWizard.html/js` contains 3 setup steps for Connected App / Auth Provider / Named Credential loopback configuration.
  - `DocGen.app-meta.xml` lists `DocGen_Bulk_Gen` and `DocGen_Job__c` tabs.
  - Permission sets (`DocGen_Admin`, `DocGen_User`, `DocGen_Guest_Signature`) grant access to deleted classes/objects/external credentials.
  - `manifest/package.xml` lists all deleted components.
- **No other triggers** exist on `DocGen_Job__c` or `DocGen_Rendition_Event__e`.
- **No layouts directory** exists for the custom objects.

---

## DEPENDENCIES / CONSTRAINTS FOUND

1. `DocGenSignatureService.cls` is e-signature code that **must** be modified because it directly references `DocGenRenditionService`, which is being deleted. This is a compilation dependency, not a feature change.
2. `DocGenService.saveFile()` receives an `outputFormat` parameter that becomes dead code after removing rendition.
3. `DocGenFlowAction` currently enqueues renditions after generating DOCX. After removal, Flow actions will return a DOCX ContentDocumentId even if template Output_Format__c is PDF. This is expected behavior per Option 7.1.
4. `DocGenSignatureService.handleSignatureSubmission()` creates audit records with `Document_Hash_SHA256__c = 'PENDING_RENDITION:' + signedCvId`. Since rendition is gone, this must be replaced with an actual SHA-256 hash of the signed DOCX.
5. `DocGenSetupWizard` references `getOrgUrl` Apex method solely for the loopback callback URL display. After removal, this wire/import is unnecessary.

---

## CLASSIFICATION

**Admin Work (salesforce-admin)**
- Delete custom objects, fields, tabs, static resources, triggers, auth metadata, LWC bundles
- Update Custom Application tab list
- Update Permission Sets (remove deleted refs)
- Update manifest/package.xml

**Developer Work (salesforce-developer)**
- Modify surviving Apex classes to remove dead references
- Modify surviving LWC components to remove dead references
- Update e-signature audit hash logic

---

## ADMIN WORK (salesforce-admin)

### 1. Delete Apex Classes (16 files)
Delete the following files entirely (`.cls` + `.cls-meta.xml` pairs):
- `force-app/main/default/classes/DocGenRenditionService.cls`
- `force-app/main/default/classes/DocGenRenditionService.cls-meta.xml`
- `force-app/main/default/classes/DocGenRenditionQueueable.cls`
- `force-app/main/default/classes/DocGenRenditionQueueable.cls-meta.xml`
- `force-app/main/default/classes/DocGenBatch.cls`
- `force-app/main/default/classes/DocGenBatch.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkController.cls`
- `force-app/main/default/classes/DocGenBulkController.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkFlowAction.cls`
- `force-app/main/default/classes/DocGenBulkFlowAction.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkFlowActionTest.cls`
- `force-app/main/default/classes/DocGenBulkFlowActionTest.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkTests.cls`
- `force-app/main/default/classes/DocGenBulkTests.cls-meta.xml`
- `force-app/main/default/classes/LoopbackTestQueueable.cls`
- `force-app/main/default/classes/LoopbackTestQueueable.cls-meta.xml`

### 2. Delete Apex Trigger (2 files)
- `force-app/main/default/triggers/DocGenRenditionTrigger.trigger`
- `force-app/main/default/triggers/DocGenRenditionTrigger.trigger-meta.xml`

### 3. Delete Custom Objects (entire directories)
- `force-app/main/default/objects/DocGen_Job__c/` (object-meta + 6 field-meta files)
- `force-app/main/default/objects/DocGen_Rendition_Event__e/` (object-meta + 2 field-meta files)

### 4. Delete Custom Tabs (2 files)
- `force-app/main/default/tabs/DocGen_Bulk_Gen.tab-meta.xml`
- `force-app/main/default/tabs/DocGen_Job__c.tab-meta.xml`

### 5. Delete Static Resources (2 files)
- `force-app/main/default/staticresources/DocGen_Bulk_Screen.png`
- `force-app/main/default/staticresources/DocGen_Bulk_Screen.resource-meta.xml`

### 6. Delete LWC Bundle (4 files)
- `force-app/main/default/lwc/docGenBulkRunner/docGenBulkRunner.html`
- `force-app/main/default/lwc/docGenBulkRunner/docGenBulkRunner.js`
- `force-app/main/default/lwc/docGenBulkRunner/docGenBulkRunner.js-meta.xml`
- If a `__tests__` directory exists under `docGenBulkRunner/`, delete it as well.

### 7. Delete Auth/Callout Metadata (3 files)
- `force-app/main/default/namedCredentials/DocGen_Loopback.namedCredential-meta.xml`
- `force-app/main/default/externalCredentials/DocGen_Loopback_Auth.externalCredential-meta.xml`
- `force-app/main/default/authproviders/DocGen_Auth_Provider.authprovider-meta.xml`

### 8. Update Custom Application
File: `force-app/main/default/applications/DocGen.app-meta.xml`
- Remove `<tabs>DocGen_Bulk_Gen</tabs>`
- Remove `<tabs>DocGen_Job__c</tabs>`

### 9. Update Permission Sets

**File: `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml`**
Remove the following nodes entirely:
- `<classAccesses>` for: `DocGenBatch`, `DocGenBulkController`, `DocGenBulkFlowAction`, `DocGenRenditionQueueable`, `DocGenRenditionService`
- `<externalCredentialPrincipalAccesses>` block for `DocGen_Loopback_Auth-Admin`
- `<fieldPermissions>` for all `DocGen_Job__c` fields (5 fields: `Error_Count__c`, `Query_Condition__c`, `Status__c`, `Success_Count__c`, `Total_Records__c`)
- `<objectPermissions>` for `DocGen_Job__c`
- `<tabSettings>` for `DocGen_Bulk_Gen` and `DocGen_Job__c`

**File: `force-app/main/default/permissionsets/DocGen_User.permissionset-meta.xml`**
Remove the same nodes as Admin (where they exist):
- `<classAccesses>` for: `DocGenBatch`, `DocGenBulkController`, `DocGenBulkFlowAction`, `DocGenRenditionQueueable`, `DocGenRenditionService`
- `<externalCredentialPrincipalAccesses>` block for `DocGen_Loopback_Auth-Admin`
- `<fieldPermissions>` for all `DocGen_Job__c` fields
- `<objectPermissions>` for `DocGen_Job__c`
- `<tabSettings>` for `DocGen_Bulk_Gen` and `DocGen_Job__c`

**File: `force-app/main/default/permissionsets/DocGen_Guest_Signature.permissionset-meta.xml`**
- Remove `<objectPermissions>` for `DocGen_Rendition_Event__e`
- (Optional) Update `<description>` to remove "trigger renditions" text, but this is not critical.

### 10. Update Manifest
File: `manifest/package.xml`
Remove `<members>` entries for all deleted components:
- ApexClass members: `DocGenBatch`, `DocGenBulkController`, `DocGenBulkFlowAction`, `DocGenBulkFlowActionTest`, `DocGenBulkTests`, `DocGenRenditionQueueable`, `DocGenRenditionService`, `LoopbackTestQueueable`
- ApexTrigger member: `DocGenRenditionTrigger`
- AuthProvider member: `DocGen_Auth_Provider`
- ExternalCredential member: `DocGen_Loopback_Auth`
- CustomObject members: `DocGen_Job__c`, `DocGen_Rendition_Event__e`
- CustomTab members: `DocGen_Bulk_Gen`, `DocGen_Job__c`
- LightningComponentBundle member: `docGenBulkRunner`
- NamedCredential member: `DocGen_Loopback`
- StaticResource member: `DocGen_Bulk_Screen`

### 11. Delete Ad-Hoc Scripts from Project Root
Delete these files (they are not part of the SFDX package):
- `/Users/jarredharkness/SalesforceDocGen/test_soql2.apex`
- `/Users/jarredharkness/SalesforceDocGen/update_permissions.py`
- `/Users/jarredharkness/SalesforceDocGen/fix_perms_final.js`
- `/Users/jarredharkness/SalesforceDocGen/test_fix.apex`
- `/Users/jarredharkness/SalesforceDocGen/create_metadata.py`
- `/Users/jarredharkness/SalesforceDocGen/fix_perms.js`
- `/Users/jarredharkness/SalesforceDocGen/test_soql.apex`
- `/Users/jarredharkness/SalesforceDocGen/test_callout.apex`
- `/Users/jarredharkness/SalesforceDocGen/scripts/test_971_loopback.apex`

**Keep:** `/Users/jarredharkness/SalesforceDocGen/sample-html-template.html`

---

## DEV WORK (salesforce-developer)

### 1. Modify `DocGenService.cls`
**File:** `force-app/main/default/classes/DocGenService.cls`

In the `saveFile` method (currently lines ~278-305):
- Remove the `format` parameter from the `saveFile` method signature. The method should read:
  `private static Id saveFile(Blob fileBlob, String title, Id recordId, String type)`
- Remove the entire `if (format == 'PDF')` block that calls `DocGenRenditionService.addPendingRendition(cv.Id, recordId);`
- Update the call site inside `generateDocument` (line ~65) from:
  `return saveFile(resultBlob, docTitle, recordId, outputFormat, templateType);`
  to:
  `return saveFile(resultBlob, docTitle, recordId, templateType);`

**Result:** Server-side generation always produces DOCX/PPTX/HTML. PDF templates will still generate DOCX on the server; PDF conversion happens only in the LWC client path (docGenRunner / docGenAdmin).

### 2. Modify `DocGenFlowAction.cls`
**File:** `force-app/main/default/classes/DocGenFlowAction.cls`

In `generateDocument` method (currently lines 36-38):
- Remove these lines entirely:
  ```apex
  // EXPERIMENT: Flush collected PDF rendition jobs
  // Direct enqueuing is used to preserve the user's auth context for loopback callouts
  DocGenRenditionService.enqueueRenditions(true);
  ```

**Result:** Flow action returns a DOCX ContentDocumentId. No async rendition is triggered.

### 3. Modify `DocGenSignatureService.cls`
**File:** `force-app/main/default/classes/DocGenSignatureService.cls`

In `handleSignatureSubmission` method (currently lines 145-147):
- Remove these lines entirely:
  ```apex
  // 4. Trigger PDF Rendition (requires external credential access)
  DocGenRenditionService.addPendingRendition(signedCvId, req.Related_Record_Id__c);
  DocGenRenditionService.enqueueRenditions();
  ```

Also in the same method (currently line 136):
- Replace:
  `audit.Document_Hash_SHA256__c = 'PENDING_RENDITION:' + signedCvId;`
- With a real hash computation. After `Id signedCvId = stampSignature(...)`, query back the inserted ContentVersion and compute the hash:
  ```apex
  ContentVersion signedCv = [SELECT VersionData FROM ContentVersion WHERE Id = :signedCvId WITH SYSTEM_MODE LIMIT 1];
  String docHash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', signedCv.VersionData));
  audit.Document_Hash_SHA256__c = docHash;
  ```
  (Move this query to after the `stampSignature` call and before `insert audit;`, or adjust ordering so `audit.Document_Hash_SHA256__c` is populated before `insert audit;`.)

**Result:** E-signature async path no longer depends on deleted rendition service. Audit records contain the actual SHA-256 of the signed DOCX.

### 4. Modify `docGenWelcome.js`
**File:** `force-app/main/default/lwc/docGenWelcome/docGenWelcome.js`

- Remove the `navigateToBulk()` method entirely.
- If the HTML template has a button calling `navigateToBulk`, remove that button as well. (Check `docGenWelcome.html` for a bulk navigation button and remove it.)

### 5. Modify `docGenSetupWizard.js`
**File:** `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.js`

- Remove the `get callbackUrl()` getter.
- Remove the `@wire(getOrgUrl)` block and its import.
- Remove the `getOrgUrl` import line: `import getOrgUrl from '@salesforce/apex/DocGenSetupController.getOrgUrl';`
- Remove `this.orgUrl` tracking if it is only used for `callbackUrl`.
- Keep `getSettings`, `saveSettings`, and the `experienceSiteUrl` logic.

### 6. Modify `docGenSetupWizard.html`
**File:** `force-app/main/default/lwc/docGenSetupWizard/docGenSetupWizard.html`

- Remove the `<lightning-progress-indicator>` and all step navigation (Step 1, 2, 3, 4 templates).
- Replace with a single-step card that only shows the Experience Site URL input and Save button.
- Remove the introduction banner text that mentions "API Loopback" and "OAuth integration".
- Keep the `lightning-input` for Experience Site URL, the example text, and the Save button.
- Remove `handleStepClick`, `nextStep`, `prevStep`, and all step-related getters (`isStep1`, `isStep2`, `isStep3`, `isStep4`) from the JS if they remain. (The JS modifications above should handle this.)

---

## EXECUTION ORDER

1. **Admin Agent** commits all file deletions and metadata updates (permission sets, app, manifest, tabs, objects, auth metadata, static resources, LWC bundle).
2. **Developer Agent** commits Apex/LWC modifications.
3. **No dependency** between admin and developer commits for source control — SFDX will validate on deploy. However, conceptually admin work should be committed first so the branch reflects a coherent state.

---

## IMPLEMENTATION NOTES FOR ALL AGENTS

- **Do NOT deploy** to any org. Only commit to the feature branch.
- `DocGenSignatureService` is e-signature code. Do not delete it. Only remove the rendition references and fix the audit hash as specified.
- `DocGenSetupController.cls` does **not** need to be modified. The `getOrgUrl` method is harmless; only the wizard's consumption of it is removed.
- `DocGenController.cls` does **not** need modification (it has no direct references to deleted components).
- `DocGenDataRetriever.cls`, `DocGenTemplateManager.cls`, `DocGenException.cls`, `DocGenSharingTests.cls`, `DocGenTests.cls` do **not** need modification.
- After removal, `DocGenService.generateDocument()` will return a DOCX ContentDocumentId regardless of template `Output_Format__c`. The client-side LWC (`docGenRunner`, `docGenAdmin`) is responsible for PDF conversion when the user selects PDF output from the UI.
- The `DocGen_Job__c` object has a lookup field `Template__c`. Deleting the object does not affect `DocGen_Template__c`.
- `DocGen_Saved_Query__c` object is **kept** (it is used by the template manager for storing query configurations, not bulk).
- Ensure `git rm` is used for deleted files so they are properly tracked as removals.

---

## PROMPT FOR salesforce-admin

"Commit to branch `feature/2026-04-25-remove-loopback-bulk`. Do not deploy.

1. Delete all files listed in the Admin Work section of `agent-output/design-requirements.md`.
2. Update `DocGen.app-meta.xml` to remove `DocGen_Bulk_Gen` and `DocGen_Job__c` tabs.
3. Update all three permission sets (`DocGen_Admin`, `DocGen_User`, `DocGen_Guest_Signature`) to remove references to deleted classes, objects, fields, tabs, and external credentials.
4. Update `manifest/package.xml` to remove all deleted component entries.
5. Delete the ad-hoc script files from the project root (listed in section 11).
6. Use `git rm` for deletions and commit all changes."

---

## PROMPT FOR salesforce-developer

"Commit to branch `feature/2026-04-25-remove-loopback-bulk`. Do not deploy.

1. Modify `DocGenService.cls`: remove the `format` parameter from `saveFile()`, remove the `DocGenRenditionService.addPendingRendition()` call, and update the call site in `generateDocument()`.
2. Modify `DocGenFlowAction.cls`: remove the `DocGenRenditionService.enqueueRenditions(true)` call at the end of `generateDocument()`.
3. Modify `DocGenSignatureService.cls`: remove the rendition calls from `handleSignatureSubmission()`, and replace the `'PENDING_RENDITION:' + signedCvId` audit hash with a real SHA-256 hash of the signed ContentVersion's VersionData.
4. Modify `docGenWelcome.js` (and `.html` if needed): remove the `navigateToBulk()` method and any corresponding UI button.
5. Modify `docGenSetupWizard.js`: remove `getOrgUrl` wire/import and `callbackUrl` getter.
6. Modify `docGenSetupWizard.html`: replace the multi-step loopback setup wizard with a single-step card containing only the Experience Site URL input and Save button. Remove OAuth/loopback text.
7. Commit all changes."
