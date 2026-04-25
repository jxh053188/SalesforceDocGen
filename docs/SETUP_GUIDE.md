# DocGen Setup Guide (Simplified)

**Date:** 2026-04-25
**Applies to:** `feature/remove-loopback-bulk` and later

---

## Overview

The DocGen setup process has been significantly simplified. Previously, administrators had to configure a Connected App, Auth Provider, External Credential, and Named Credential to enable server-side PDF rendition via a loopback callout. **This is no longer required.**

The only remaining setup step is configuring the **Experience Site URL** for e-signature functionality.

---

## Prerequisites

Before installing or upgrading DocGen, ensure the following:

1. **Salesforce Edition:** Enterprise, Unlimited, or Developer Edition (Lightning Experience required).
2. **API Version:** 66.0 or later.
3. **My Domain:** Enabled and deployed in your org.
4. **Content Deliveries:** Enabled (for document storage and sharing).
5. **Experience Cloud:** Optional but recommended if using the e-signature feature.

---

## Installation

Deploy the package metadata to your org using your preferred deployment tool (e.g., Salesforce DX, Metadata API, or a change set).

```bash
# Example: SFDX source deploy
sfdx force:source:deploy -p force-app/main/default
```

After deployment, assign permission sets to users.

---

## Permission Sets

DocGen ships with three permission sets. Assign them according to user roles:

### DocGen Admin

**Assign to:** System administrators and power users who manage templates.

**Grants access to:**
- All DocGen custom objects: `DocGen_Template__c`, `DocGen_Template_Version__c`, `DocGen_Saved_Query__c`, `DocGen_Signature_Request__c`, `DocGen_Signature_Audit__c`
- All surviving Apex classes
- All DocGen application tabs
- Template sharing management

### DocGen User

**Assign to:** Standard users who generate documents from record pages.

**Grants access to:**
- `DocGen_Template__c` (read)
- `DocGen_Signature_Request__c` and `DocGen_Signature_Audit__c` (read)
- Document generation classes and LWC components

### DocGen Guest Signature

**Assign to:** Guest user profile for the Experience Site (if using e-signature).

**Grants access to:**
- `DocGen_Signature_Request__c` (read/update limited fields)
- `DocGen_Signature_Audit__c` (create)
- Signature validation and stamping controllers

**To assign:**
```bash
sfdx force:user:permset:assign -n DocGen_Admin -u <username>
sfdx force:user:permset:assign -n DocGen_User -u <username>
```

---

## Setup Wizard

Navigate to the **DocGen Setup** tab in the DocGen application.

### Step 1: Configure Experience Site URL

If you plan to use the e-signature feature, enter the full URL of the Experience Cloud page where signers will access documents.

**Example:**
```
https://docgen-portal.my.site.com/s/sign-document
```

**Field:** Experience Site URL (with page path)

**Why this matters:** The e-signature sender (`docGenSignatureSender`) embeds this URL in the email sent to signers. The URL must be publicly accessible and point to a page that hosts the `docGenAuthenticator` or `docGenSignaturePad` component.

Click **Save Settings**.

### What Was Removed from the Wizard

The following setup steps are no longer necessary and have been removed from the UI:

- ~~Connected App creation~~
- ~~Auth Provider configuration~~
- ~~External Credential / Named Credential setup~~
- ~~OAuth callback URL copy/paste~~

These were all related to the deleted loopback callout infrastructure.

---

## Post-Setup Verification

### 1. Verify Application Tabs

Open the DocGen app from the App Launcher. You should see the following tabs:

- **Template Manager** — Create and manage templates
- **DocGen Template** — Template record list
- **Setup** — Configuration page
- **Template Version** — Version history
- **Signature Request** — Track e-signature requests
- **Signature Audit** — View audit trail

You should **NOT** see:
- ~~Bulk Gen~~ (removed)
- ~~DocGen Job~~ (removed)

### 2. Verify Template Creation

1. Go to **Template Manager**.
2. Click **New Template**.
3. Select an object (e.g., Account).
4. Upload a Word (.docx) or PowerPoint (.pptx) template with merge tags like `{Name}`.
5. Save and activate the template.

### 3. Verify Document Generation

1. Navigate to a record page (e.g., an Account).
2. If configured, the `docGenRunner` component should appear (or use the Template Manager to test).
3. Select a template and click **Generate**.
4. Confirm the document downloads in the expected format.

### 4. Verify E-Signature (Optional)

1. Ensure an Experience Site exists with a page hosting the signature components.
2. In a record with a generated DOCX, click **Request Signature**.
3. Enter a signer name and email.
4. Check that the signer receives an email with a link to the Experience Site URL configured in Setup.

---

## Troubleshooting

### "Settings saved successfully" but URL not persisted

- Ensure the `DocGen_Settings__c` custom setting object is deployed.
- Check that the running user has **Customize Application** permission or is assigned the `DocGen_Admin` permission set.

### E-signature link is broken

- Verify the Experience Site URL in Setup includes the protocol (`https://`) and the full page path.
- Ensure the Experience Site is published and the guest user has the `DocGen_Guest_Signature` permission set.
- Confirm the page hosts the `c-doc-gen-authenticator` or `c-doc-gen-signature-pad` component.

### Document generation fails

- Check that the template has an active version.
- Verify the user has read access to the template and the base object.
- Review browser console logs for client-side errors (LWC path).
- Check Apex debug logs for server-side errors (Flow path).

### "PDF not available from Flow"

This is expected behavior. Flow actions return a DOCX `ContentDocumentId`. PDF conversion is only available in the LWC client path. See `CLIENT_SIDE_GENERATION.md` for details.

---

## File Locations

- **Setup Wizard LWC:** `force-app/main/default/lwc/docGenSetupWizard/`
- **Setup Controller:** `force-app/main/default/classes/DocGenSetupController.cls`
- **Custom Setting:** `DocGen_Settings__c` (Experience_Site_Url__c field)
- **Permission Sets:** `force-app/main/default/permissionsets/`
- **App Definition:** `force-app/main/default/applications/DocGen.app-meta.xml`
