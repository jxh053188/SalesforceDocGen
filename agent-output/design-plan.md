# Design Plan: Remove Loopback & Bulk Generation

## Branch
feature/remove-loopback-bulk

## Goal
Remove the Loopback callout and bulk generation completely. Force all PDF generation to happen client-side (Option 7.1 from API_CALLOUT_ANALYSIS.md). Delete dead code and clean up random files in project root.

## WHAT TO DELETE

### Apex Classes (16 files)
- `force-app/main/default/classes/DocGenRenditionService.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenRenditionQueueable.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenBatch.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkController.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkFlowAction.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkFlowActionTest.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/DocGenBulkTests.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/LoopbackTestQueueable.cls` + `.cls-meta.xml`

### Apex Trigger (2 files)
- `force-app/main/default/triggers/DocGenRenditionTrigger.trigger` + `.trigger-meta.xml`

### Custom Objects (entire directories)
- `force-app/main/default/objects/DocGen_Job__c/` (object-meta + 6 fields)
- `force-app/main/default/objects/DocGen_Rendition_Event__e/` (object-meta + 2 fields)

### Tabs (2 files)
- `force-app/main/default/tabs/DocGen_Bulk_Gen.tab-meta.xml`
- `force-app/main/default/tabs/DocGen_Job__c.tab-meta.xml`

### Static Resources (2 files)
- `force-app/main/default/staticresources/DocGen_Bulk_Screen.png` + `.resource-meta.xml`

### LWC Bundle
- `force-app/main/default/lwc/docGenBulkRunner/` (html, js, js-meta.xml)

### Auth/Callout Metadata (3 files)
- `force-app/main/default/namedCredentials/DocGen_Loopback.namedCredential-meta.xml`
- `force-app/main/default/externalCredentials/DocGen_Loopback_Auth.externalCredential-meta.xml`
- `force-app/main/default/authproviders/DocGen_Auth_Provider.authprovider-meta.xml`

### Ad-Hoc Scripts (9 files in project root)
- `test_soql2.apex`
- `update_permissions.py`
- `fix_perms_final.js`
- `test_fix.apex`
- `create_metadata.py`
- `fix_perms.js`
- `test_soql.apex`
- `test_callout.apex`
- `scripts/test_971_loopback.apex`

**Keep:** `sample-html-template.html`

### App, Permission Sets, Manifest
- Remove `DocGen_Bulk_Gen` and `DocGen_Job__c` tabs from `force-app/main/default/applications/DocGen.app-meta.xml`
- Remove deleted class/object/field/tab/external-credential references from:
  - `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml`
  - `force-app/main/default/permissionsets/DocGen_User.permissionset-meta.xml`
  - `force-app/main/default/permissionsets/DocGen_Guest_Signature.permissionset-meta.xml`
- Remove all deleted component entries from `manifest/package.xml`

## WHAT TO MODIFY

### `DocGenService.cls`
- Remove the `format` parameter from `saveFile()`
- Remove the `if (format == 'PDF')` block that calls `DocGenRenditionService.addPendingRendition()`
- Update the `saveFile()` call site in `generateDocument()` to pass 4 args instead of 5

### `DocGenFlowAction.cls`
- Remove the `DocGenRenditionService.enqueueRenditions(true)` call at the end of `generateDocument()`

### `DocGenSignatureService.cls`
- Remove the rendition calls from `handleSignatureSubmission()`
- Replace the audit hash `'PENDING_RENDITION:' + signedCvId` with the `ContentDocumentId` of the signed DOCX

### `docGenWelcome.js` (+ `.html` if button exists)
- Remove `navigateToBulk()` method and any corresponding bulk navigation button

### `docGenSetupWizard.js`
- Remove `getOrgUrl` import, wire, and `callbackUrl` getter
- Keep `getSettings` and `saveSettings`

### `docGenSetupWizard.html`
- Replace the 4-step loopback setup wizard with a single-step card showing only the Experience Site URL input and Save button
- Remove all OAuth/Connected App/Named Credential instructional text

## WHAT TO KEEP (Unchanged)
- `DocGenController.cls`
- `DocGenSetupController.cls`
- `DocGenDataRetriever.cls`
- `DocGenTemplateManager.cls`
- `DocGenException.cls`
- `DocGenTests.cls`
- `DocGenSharingTests.cls`
- All E-Signature classes (except the minimal signature service fix above)
- All E-Signature LWCs, pages, flows, sites, and objects
- `DocGen_Saved_Query__c` (used by template manager)
- `docGenRunner`, `docGenAdmin`, `docGenQueryBuilder`, `docGenFilterBuilder`, `docGenSharing`, `docGenTitleEditor`, `docGenPreviewModal`, `docGenPdfUtils`, `pdfjsViewer`, and all other LWCs

## ORDER OF OPERATIONS
1. **salesforce-admin** deletes all metadata files, updates permission sets, app tabs, and manifest.
2. **salesforce-developer** modifies surviving Apex and LWC files to remove references to deleted components.
