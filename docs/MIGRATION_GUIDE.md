# Migration Guide: Removing Loopback & Bulk Generation

**Date:** 2026-04-25
**From:** Any version prior to `feature/remove-loopback-bulk`
**To:** `feature/remove-loopback-bulk` and later

---

## Who Should Read This

You should read this guide if:
- You have an existing DocGen installation that includes **Bulk Generation** or **server-side PDF rendition**.
- You are upgrading from a version that used the **Loopback Callout** (`DocGen_Loopback` Named Credential).
- You have users or automations that depend on the removed features.

---

## What You Will Lose

### 1. Server-Side PDF Generation

**Previous behavior:** When a template's `Output_Format__c` was set to PDF, the server generated a DOCX and then used an async loopback callout to the Salesforce Connect API to retrieve a PDF rendition.

**New behavior:** The server always generates DOCX (or PPTX). PDF output is only produced when the user generates a document through the LWC UI (`docGenRunner`, `docGenAdmin`), where the browser converts the DOCX to PDF client-side.

**Impact:**
- Flow actions that previously returned a PDF `ContentDocumentId` now return a DOCX `ContentDocumentId`.
- Any downstream automation that expected a PDF file extension or MIME type will receive DOCX instead.
- E-signature finalization produces a signed DOCX, not a signed PDF.

### 2. Bulk Generation

**Previous behavior:** Users could navigate to the **Bulk Gen** tab, select a template and a query condition, and run a batch job (`DocGenBatch`) that generated documents for thousands of records. The job tracked progress in `DocGen_Job__c`.

**New behavior:** The Bulk Gen tab, `docGenBulkRunner` LWC, `DocGenBatch` Apex class, and `DocGen_Job__c` object are all deleted.

**Impact:**
- There is no UI for bulk document generation.
- There is no batch Apex class for bulk generation.
- Historical `DocGen_Job__c` records in your org will become inaccessible metadata orphans unless you delete the object and records before upgrading.

### 3. Loopback Authentication Setup

**Previous behavior:** Administrators had to set up an Auth Provider, Connected App, External Credential, and Named Credential. The Setup Wizard guided users through four steps including copying a callback URL.

**New behavior:** All of that metadata is deleted. The Setup Wizard now has a single step: enter the Experience Site URL.

**Impact:**
- The `DocGen_Auth_Provider`, `DocGen_Loopback_Auth`, and `DocGen_Loopback` metadata will be deleted on upgrade.
- Any Connected App created manually for DocGen can be safely deleted (unless used by other integrations).
- No Named Principal OAuth authorization is needed.

---

## Pre-Upgrade Checklist

Before deploying this upgrade to production, complete the following:

### 1. Audit Existing Data

- **Run a report on `DocGen_Job__c`:** If you have active or historical bulk jobs, export the data for reference. The object will be deleted during upgrade.
- **Check `DocGen_Signature_Audit__c` records:** Look for any records where `Document_Hash_SHA256__c` starts with `PENDING_RENDITION:`. These indicate incomplete or failed renditions from the old loopback system. The new code no longer creates these placeholders.

### 2. Identify Automations Using Removed Features

Search your org for references to the following:

| Component | Search In |
|-----------|-----------|
| `DocGenBulkFlowAction` | Flows, Process Builder |
| `DocGenBulkController` | Aura components, Visualforce pages |
| `DocGen_Job__c` | Reports, dashboards, list views, validation rules |
| `DocGen_Rendition_Event__e` | Platform Event subscriptions, triggers, Flows |
| `DocGen_Loopback` | Named Credential references in code |

**If found:** Update or delete these automations before upgrading.

### 3. Notify Users

Communicate the following changes to your DocGen users:

- The **Bulk Gen** tab is gone. Users who need bulk generation should contact their admin to discuss alternatives (e.g., a custom Flow using `DocGenFlowAction` in a loop, or generating documents one at a time from record pages).
- **PDF from Flow** is no longer automatic. Flow-generated documents will be DOCX.
- **Setup Wizard** is simpler. No more OAuth/loopback setup steps.

### 4. Back Up Metadata (Optional)

If you wish to preserve the old behavior for reference or rollback:

```bash
# Retrieve the old metadata before deploying
sfdx force:mdapi:retrieve -k manifest/package.xml -r ./backup
```

---

## Upgrade Steps

### Step 1: Deploy the New Metadata

Use your standard deployment pipeline. The package manifest (`manifest/package.xml`) no longer includes the deleted components.

```bash
sfdx force:source:deploy -p force-app/main/default
```

### Step 2: Clean Up Deleted Metadata from the Org

Because the deleted components are no longer in the package, the deployment will **not** automatically remove them from an existing org. You must delete them manually or via a destructive changes package.

**Recommended destructive changes:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>DocGenRenditionService</members>
        <members>DocGenRenditionQueueable</members>
        <members>DocGenBatch</members>
        <members>DocGenBulkController</members>
        <members>DocGenBulkFlowAction</members>
        <members>DocGenBulkFlowActionTest</members>
        <members>DocGenBulkTests</members>
        <members>LoopbackTestQueueable</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>DocGenRenditionTrigger</members>
        <name>ApexTrigger</name>
    </types>
    <types>
        <members>DocGen_Job__c</members>
        <members>DocGen_Rendition_Event__e</members>
        <name>CustomObject</name>
    </types>
    <types>
        <members>DocGen_Bulk_Gen</members>
        <members>DocGen_Job__c</members>
        <name>CustomTab</name>
    </types>
    <types>
        <members>DocGen_Auth_Provider</members>
        <name>AuthProvider</name>
    </types>
    <types>
        <members>DocGen_Loopback_Auth</members>
        <name>ExternalCredential</name>
    </types>
    <types>
        <members>DocGen_Loopback</members>
        <name>NamedCredential</name>
    </types>
    <types>
        <members>DocGen_Bulk_Screen</members>
        <name>StaticResource</name>
    </types>
    <types>
        <members>docGenBulkRunner</members>
        <name>LightningComponentBundle</name>
    </types>
    <version>66.0</version>
</Package>
```

Deploy the destructive changes:

```bash
sfdx force:mdapi:deploy -d destructiveChanges -w 30
```

### Step 3: Reassign Permission Sets

Users who previously had `DocGen_Admin` or `DocGen_User` will need the updated permission sets redeployed. The updated sets no longer grant access to deleted objects/classes.

```bash
sfdx force:user:permset:assign -n DocGen_Admin -u <admin-user>
sfdx force:user:permset:assign -n DocGen_User -u <standard-user>
```

### Step 4: Verify Setup Wizard

1. Open the **DocGen Setup** tab.
2. Confirm that only the **Experience Site URL** field is shown.
3. Re-enter or confirm the URL and save.

### Step 5: Test Core Flows

1. **Single Record Generation:** Go to a record page, generate a document, and verify download.
2. **Template Manager:** Create a new template, upload a file, and test preview.
3. **Flow Action:** If you use Flow, test `DocGenFlowAction` and confirm it returns a DOCX `ContentDocumentId`.
4. **E-Signature:** Send a test signature request and complete it end-to-end.

---

## Post-Upgrade Data Cleanup

After the upgrade is stable, clean up the following from your org:

1. **Connected App:** If you created a Connected App solely for DocGen loopback, delete it.
2. **Auth Provider entries:** Remove any Named Principal authorizations related to `DocGen_Loopback_Auth`.
3. **`DocGen_Job__c` records:** If you exported historical data and no longer need it, delete the records. The object itself should be deleted via destructive changes.

---

## Alternative Patterns for Removed Features

### "I need bulk generation"

**Option A: Screen Flow + Loop**
Create a Screen Flow that queries the records you need, loops through them, and calls `DocGenFlowAction` for each. Note that this will produce DOCX files. If PDF is required, you will need to download each DOCX and convert it manually, or build a custom LWC that iterates over a list and triggers client-side PDF generation.

**Option B: Custom Batch LWC**
Build a Lightning Web Component that loads a list of records and calls `DocGenController.generateDocumentData()` for each one sequentially, converting to PDF in the browser. This preserves the client-side path but adds UI complexity.

### "I need PDF from Flow"

**Current limitation:** There is no server-side PDF conversion after this upgrade.

**Workarounds:**
- Accept DOCX as the Flow output and let users convert locally.
- Build an external microservice (AWS Lambda, Heroku, Azure Function) that accepts a DOCX Blob via callout and returns a PDF. This would require a new Named Credential and Apex service, but it would be a clean external integration rather than a fragile loopback.

### "I need signed PDFs from e-signature"

**Current behavior:** The signed document is a DOCX with the signature image injected.

**Workaround:** In the LWC signing experience, the signer can preview the signed document. If the Experience Site page includes the client-side PDF conversion libraries, the signer can download a PDF before the final upload is saved. Alternatively, the finalizer Flow can send the DOCX to an external conversion service.

---

## Rollback Considerations

If you need to rollback after upgrade:

1. Restore the deleted metadata from your backup.
2. Redeploy the old permission sets.
3. Recreate the Auth Provider / Named Credential and re-authorize.
4. Re-enable the Bulk Gen tab in the Custom Application.

**Note:** Any documents generated as DOCX during the new version's tenure will remain DOCX. Reinstalling the old version does not retroactively convert them.

---

## Support

For questions about this migration, refer to:
- `docs/REMOVAL_SUMMARY.md` — Detailed list of what was removed.
- `docs/CLIENT_SIDE_GENERATION.md` — How the new client-side architecture works.
- `docs/SETUP_GUIDE.md` — Simplified setup instructions.
- `outputs/API_CALLOUT_ANALYSIS.md` — Original architecture analysis that motivated this change.
