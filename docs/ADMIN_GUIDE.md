# DocGen Admin Guide

**Date:** 2026-04-26  
**Applies to:** DocGen v0.3.0 and later  
**Audience:** Salesforce administrators and power users who manage document templates

---

## Overview

This guide covers day-to-day administration of DocGen templates, with a focus on the DocuSign envelope configuration integration introduced in v0.3.0.

---

## Prerequisites

Before following this guide, ensure:

1. You are assigned the **DocGen Admin** permission set.
2. The DocuSign eSignature for Salesforce managed package is installed in your org.
3. At least one `dfsle__EnvelopeConfiguration__c` record exists for the object you want to generate documents from.

---

## Creating or Editing a Template

### Step 1: Open the Template Manager

1. From the App Launcher, open the **DocGen** app.
2. Click the **Template Manager** tab.
3. You will see a list of existing templates.

### Step 2: Create a New Template

1. Click the **New Template Wizard** tab.
2. Fill in the required fields on **Step 1 (Details)**:
   - **Template Name** (required)
   - **Type** — Word, PowerPoint, or HTML
   - **Output Format** — Native or PDF
   - **DocuSign Envelope Configuration** (optional) — see below
   - **DocuSign Signer Count** (optional) — see below
   - **Description** (optional)

3. Proceed to **Step 2 (Query Config)** and build your data query.
4. Review on **Step 3 (Finish)** and click **Create Template**.
5. Upload your template file on the **Document & History** tab.
6. Click **Save as New Version** to activate the template.

### Step 3: Link a DocuSign Envelope Configuration

The **DocuSign Envelope Configuration** picklist appears in two places:

- **Create Wizard Step 1**
- **Edit Modal > Settings tab**

To link a configuration:

1. Select the template's **Base Object** first (e.g., `Account`, `Opportunity`).
2. The **DocuSign Envelope Configuration** picklist will automatically refresh.
3. Only envelope configurations whose **source object** matches the template's base object are displayed.
4. Select the desired configuration.
5. The **DocuSign Signer Count** field auto-populates from the envelope configuration metadata.
6. You may override the signer count (minimum 1, maximum 10).
7. Save the template.

**Important:** If no envelope configurations appear, verify that:
- The DocuSign managed package is installed.
- At least one `dfsle__EnvelopeConfiguration__c` record exists for the selected object.
- The running user has read access to `dfsle__EnvelopeConfiguration__c`.

### Step 4: Edit an Existing Template

1. From the template list, click the row-actions menu (three dots) on the template you want to edit.
2. Select **Edit**.
3. Switch to the **Settings** tab.
4. Modify the **DocuSign Envelope Configuration** or **DocuSign Signer Count** as needed.
5. Click **Save Details** (quick save) or **Save as New Version** (snapshot the current state).

---

## Managing Versions

Every time you click **Save as New Version**, DocGen snapshots the template configuration into a `DocGen_Template_Version__c` record. This includes:

- Query configuration and metadata
- Category, description, type, and base object
- DocuSign envelope configuration and signer count

To restore a version:

1. Open the template edit modal.
2. Go to the **Document & History** tab.
3. Find the version you want to restore in the version history table.
4. Click **Activate**. The template headline fields are updated immediately.

---

## Template Sharing

To share a template with another user or group:

1. From the template list, click the row-actions menu.
2. Select **Share**.
3. In the sharing modal, search for a user or group.
4. Select the access level (Read or Edit).
5. Click **Share**.

To remove sharing:

1. Open the sharing modal again.
2. Find the share record and click **Remove**.

---

## DocuSign Anchor Tag Mappings

For documents sent via DocuSign, you must configure anchor tag mappings so DocuSign knows where to place signature tabs.

1. Go to **Setup > Custom Metadata Types > DocGen DocuSign Mapping**.
2. Click **Manage Records**.
3. Create one mapping per merge field that needs a DocuSign tab:
   - **Template Id** — the Salesforce ID of the `DocGen_Template__c` record
   - **Merge Field** — the token name without braces (e.g., `SignerName`)
   - **Anchor Tag** — the DocuSign anchor string (e.g., `/sn1/`)
   - **Anchor Type** — `SignHere`, `Text`, `Date`, or `Checkbox`
   - **Unique Suffix Field** — optional field for repeating anchors in loops
   - **Active** — checked

See [DOCUSIGN_INTEGRATION.md](DOCUSIGN_INTEGRATION.md) for the full anchor tag reference.

---

## Troubleshooting

### No envelope configurations appear in the picklist

- Confirm the DocuSign managed package is installed (`dfsle` namespace is visible).
- Check that at least one `dfsle__EnvelopeConfiguration__c` record exists and its source-object field matches the template's base object.
- Verify the running user has read access to `dfsle__EnvelopeConfiguration__c`.
- The integration discovers the source-object field dynamically via Schema describe. If the managed package version uses a different field name, the query may return all configurations instead of filtering.

### Signer count is wrong after selecting an envelope configuration

- The signer count is read from a dynamic field on `dfsle__EnvelopeConfiguration__c` (searched by field names containing "signer" or "recipient").
- If the managed package version does not expose this field, the default of 1 is used.
- You can manually override the signer count before saving.

### Template saves but DocuSign sending fails for users

- Ensure the template has an **active version** with a linked ContentDocument.
- Verify the user has the **DocGen User** permission set.
- Check that the selected Contacts have valid Email addresses.
- Review Apex debug logs for errors from `DocGenDocuSignService`.

---

## File Locations

| Component | Path |
|-----------|------|
| Template Manager LWC | `force-app/main/default/lwc/docGenAdmin/` |
| Template object | `force-app/main/default/objects/DocGen_Template__c/` |
| Envelope config lookup field | `force-app/main/default/objects/DocGen_Template__c/fields/DocuSign_Envelope_Configuration__c.field-meta.xml` |
| Signer count field | `force-app/main/default/objects/DocGen_Template__c/fields/DocuSign_Signer_Count__c.field-meta.xml` |
| Admin permission set | `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml` |
