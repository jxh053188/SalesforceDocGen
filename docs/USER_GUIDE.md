# DocGen User Guide

**Date:** 2026-04-26  
**Applies to:** DocGen v0.3.0 and later  
**Audience:** End users who generate documents from Salesforce record pages

---

## Overview

This guide explains how to generate documents from a record page, preview them, and send them for DocuSign signature.

---

## Prerequisites

Before following this guide, ensure:

1. You are assigned the **DocGen User** permission set.
2. Your Salesforce admin has added the **docGenRunner** component to the record page for your object.
3. At least one DocGen template exists for the object you are working with.

---

## Generating and Previewing a Document

### Step 1: Open a Record Page

1. Navigate to any record page that has the Document Generator component (e.g., an Account, Opportunity, or Contract).
2. Look for the **Document Generator** card on the page.

### Step 2: Select a Template

1. In the Document Generator card, open the **Select Template** dropdown.
2. Choose a template. Only templates configured for the current object's type are shown.
3. If the template has a linked DocuSign envelope configuration, the runner stores this internally for the preview modal.

### Step 3: Preview the Document

1. Click **Preview Document**.
2. The component generates a PDF preview in the background. This may take a few seconds.
3. A modal opens showing the rendered PDF.

---

## Actions in the Preview Modal

The preview modal offers up to three actions, depending on the template configuration:

| Action | Visible When | Result |
|--------|-------------|--------|
| **Download** | Always | Saves the PDF to your local computer. |
| **Save to Record** | Always | Attaches the PDF to the current Salesforce record as a File. |
| **Send with DocuSign** | Template has a linked envelope configuration | Generates a DOCX with anchor tags and sends it for DocuSign signature. |

### Downloading the PDF

1. Click **Download**.
2. Your browser saves the file using the record name (e.g., `Acme Corp.pdf`).

### Saving to the Record

1. Click **Save to Record**.
2. The PDF is uploaded as a Salesforce File and linked to the current record.
3. A success toast appears. The modal closes automatically.

### Sending with DocuSign

This action is only available if the template has a linked **DocuSign Envelope Configuration**.

1. Click **Send with DocuSign**.
2. A form expands below the PDF viewer with:
   - **Email Subject** — optional. If left blank, DocuSign uses a default subject.
   - **Signer pickers** — one contact picker per signer (e.g., Signer 1, Signer 2). The number of pickers is determined by the template's **DocuSign Signer Count** field.
3. Each contact picker is pre-populated with related Contacts from the source record (Opportunity Contact Roles, Account Contact Roles, Contract Contact Roles, or Person Account).
4. Select a Contact for each signer.
5. Click **Confirm Send**.
6. The system:
   - Regenerates the document with DocuSign anchor tags.
   - Resolves the latest ContentVersion of the generated DOCX.
   - Builds a multi-recipient envelope using the selected Contacts.
   - Calls DocuSign to send the envelope.
7. A success toast appears with the DocuSign envelope ID.
8. The modal closes.

**Note:** All selected Contacts must have a valid Email address. If any signer is missing an email, the send will fail with an error message.

---

## Using the Flow Action (Advanced)

If your admin has built a Flow that uses the **Generate Document (Native)** action, you can trigger multi-recipient DocuSign sending automatically.

The Flow action accepts:
- **Template ID** (required)
- **Base Record ID** (required)
- **Send for DocuSign Signature** — set to `True` to trigger sending
- **Recipient Contact IDs (comma-separated)** — a comma-separated list of Contact IDs
- **Email Subject** — optional custom subject

**Example:**
```
Template ID: {!templateId}
Base Record ID: {!recordId}
Send for DocuSign Signature: True
Recipient Contact IDs: {!contact1.Id}, {!contact2.Id}
Email Subject: Please review and sign this agreement
```

The action returns:
- **Content Document ID** — the generated DOCX file
- **DocuSign Envelope ID** — the envelope ID from DocuSign
- **Error Message** — populated if generation or sending failed

---

## Troubleshooting

### "Preview Document" button is disabled

- Make sure you have selected a template from the dropdown.
- If the dropdown is empty, no templates are configured for this object. Contact your admin.

### "Send with DocuSign" button does not appear

- The template does not have a linked DocuSign envelope configuration. Only admins can add this.
- The template may be a PowerPoint or HTML template. DocuSign sending is designed for Word templates with anchor tags.

### "Please select a contact for Signer X" error

- You must select a Contact for every signer shown in the form.
- If no contacts appear in the picklists, the source record may not have related Contacts. Ask your admin to verify Contact relationships.

### "Send failed" error after clicking Confirm Send

- Common causes:
  - One of the selected Contacts does not have an Email address.
  - The DocuSign managed package is not installed or configured.
  - The template file is missing or the active version is not set.
  - You do not have permission to send DocuSign envelopes.
- Ask your admin to check Apex debug logs for the exact error.

### PDF preview is blank or fails to load

- Try refreshing the page and clicking **Preview Document** again.
- Check that the template file is a valid .docx, .pptx, or .html file.
- Ensure your browser allows pop-ups and iframes from Salesforce.

---

## File Locations

| Component | Path |
|-----------|------|
| Runner LWC | `force-app/main/default/lwc/docGenRunner/` |
| Preview modal LWC | `force-app/main/default/lwc/docGenPreviewModal/` |
| DocuSign controller | `force-app/main/default/classes/DocGenDocuSignController.cls` |
| Flow action | `force-app/main/default/classes/DocGenFlowAction.cls` |
