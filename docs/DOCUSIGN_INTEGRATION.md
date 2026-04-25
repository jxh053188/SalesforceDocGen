# DocuSign eSignature Integration

**Date:** 2026-04-25
**Branch:** `feature/2026-04-25-docusign-esignature-integration`
**Applies to:** DocGen v0.2.0 and later

---

## Overview

This integration connects the DocGen document generation engine to **DocuSign eSignature for Salesforce**, allowing users to generate Word documents with embedded DocuSign anchor tags and send them for signature directly from a Salesforce record page or Flow.

**What it does:**
- Injects DocuSign anchor tags into generated `.docx` files at merge-field positions
- Sends generated documents as DocuSign envelopes via the `dfsle` managed package
- Resolves default recipients from the source record (Opportunity Contact, Contract Signer, Account Primary Contact, or Person Account)
- Surfaces DocuSign envelope IDs back to the calling Flow or LWC

**What it does NOT do (MVP limitations):**
- No custom DocuSign tracking objects — envelope status is tracked by the managed package's `dsfs__DocuSign_Status__c`
- No server-side PDF conversion before sending — envelopes are sent as DOCX
- No DocuSign template selection in the UI — the `withDocuSignTemplate()` override is stubbed for a future iteration
- No anchor tag injection for PowerPoint or HTML templates — Word only
- No bulk DocuSign sending — single-record only

---

## Prerequisites

1. **DocuSign eSignature for Salesforce** managed package must be installed in your org.
2. **DocuSign Connect** should be configured if you need automatic status writeback to Salesforce.
3. **Permission sets** must be assigned after deployment (see Security Model below).
4. **My Domain** must be enabled and deployed.

---

## Setup Guide

### Step 1: Install the DocuSign Managed Package

If not already installed, install **DocuSign eSignature for Salesforce** from the AppExchange and complete the managed-package setup wizard.

### Step 2: Assign Permission Sets

Users who generate or send documents need the updated DocGen permission sets.

```bash
sfdx force:user:permset:assign -n DocGen_Admin -u <admin-user>
sfdx force:user:permset:assign -n DocGen_User -u <standard-user>
```

**What changed in the permission sets:**
- `DocGenDocuSignController` and `DocGenDocuSignService` class access added
- Read access to `dsfs__DocuSign_Status__c` added (envelope status visibility)

### Step 3: Configure Anchor Tag Mappings

Anchor tags tell DocuSign where to place signature, date, text, or checkbox fields inside the document.

1. Go to **Setup > Custom Metadata Types**.
2. Click **Manage Records** next to **DocGen DocuSign Mapping**.
3. Click **New** and create mappings for each template that will be sent via DocuSign.

| Field | Description | Example |
|-------|-------------|---------|
| **Template Id** | The Salesforce `DocGen_Template__c` record ID | `a01xx0000000001` |
| **Merge Field** | The merge token used in the Word template (without braces) | `Name`, `Amount`, `SignatureDate` |
| **Anchor Tag** | The DocuSign anchor string that will be placed after the merge value | `/sn1/`, `/t1/`, `/d1/` |
| **Anchor Type** | Picklist: `SignHere`, `Text`, `Date`, `Checkbox` | `SignHere` |
| **Unique Suffix Field** | Optional. A field API name whose value is appended to the anchor for repeating sections | `LastName`, `LineNumber` |
| **Active** | Whether this mapping is active | Checked |

#### Example Mappings

**Simple signature block:**
- Template Id: `a01xx0000000001`
- Merge Field: `SignerName`
- Anchor Tag: `/sn1/`
- Anchor Type: `SignHere`
- Active: true

**Date field:**
- Template Id: `a01xx0000000001`
- Merge Field: `SignatureDate`
- Anchor Tag: `/d1/`
- Anchor Type: `Date`
- Active: true

**Text field in a repeating table row:**
- Template Id: `a01xx0000000001`
- Merge Field: `ItemName`
- Anchor Tag: `/t1/`
- Anchor Type: `Text`
- Unique Suffix Field: `LineNumber`
- Active: true

The anchor in the final document becomes `/t1/-1`, `/t1/-2`, etc., depending on the record value of `LineNumber`.

### Step 4: Add the LWC to a Record Page

1. Open **Lightning App Builder** for any object that has DocGen templates (Account, Opportunity, Contract, etc.).
2. Drag the **docGenDocuSignSender** component onto the page.
3. Save and activate the page.

When a user visits the record:
- The component loads templates available for that object.
- It loads related Contacts (Opportunity Contact Roles, Account Contact Roles, Contract Contact Roles, or Person Account).
- The user selects a template, optionally overrides the recipient, enters an optional custom email subject, and clicks **Generate & Send via DocuSign**.

### Step 5: Use the Flow Action

1. In **Flow Builder**, add an Action element.
2. Search for **Generate Document (Native)**.
3. Set the input variables:
   - `Template ID` (required)
   - `Base Record ID` (required)
   - `Send for DocuSign Signature` (optional) — set to `{!$GlobalConstant.True}` to trigger sending
   - `Recipient Contact ID` (optional) — leave blank to use the record's default recipient resolution
   - `Email Subject` (optional) — overrides the default subject

4. The action returns:
   - `Content Document ID` — the generated DOCX file
   - `DocuSign Envelope ID` — the envelope ID from DocuSign
   - `Error Message` — populated if generation or sending failed

---

## Architecture

### Data Flow

```
User (Record Page or Flow)
    |
    v
DocGenDocuSignController.generateAndSend()
    |
    +---> DocGenService.generateDocument(templateId, recordId, injectAnchors=true)
    |         |
    |         +---> Queries DocGen_DocuSign_Mapping__mdt for active anchors
    |         +---> Unzips Word template
    |         +---> Merges data + injects anchor tags into word/document.xml
    |         +---> Re-zips and saves as ContentVersion
    |         |
    |         v
    +---> DocGenDocuSignService.sendDocumentForSignature()
              |
              +---> Resolves recipient (Contact lookup + Email validation)
              +---> Builds dfsle.Document and dfsle.Recipient
              +---> Calls dfsle.EnvelopeService.sendEnvelope()
              |
              v
          DocuSign Envelope ID returned
```

### How Anchor Tags Are Injected

When `injectDocuSignAnchors` is `true` and the template type is `Word`, the generation engine:

1. Queries `DocGen_DocuSign_Mapping__mdt` for active mappings where `Template_Id__c` matches.
2. Builds a map keyed by `Merge_Field__c`.
3. During XML processing (`processXml` in `DocGenService`), after resolving a merge field value, checks whether that field has a mapping.
4. If a mapping exists:
   - Appends a space + the `Anchor_Tag__c` to the resolved value.
   - If `Unique_Suffix_Field__c` is populated, resolves that field's value and appends `-<suffix>` to the anchor.
   - XML-escapes the combined string before writing it into the Word XML.

**Anchor placement example:**

Template XML:
```xml
<w:t>{SignerName}</w:t>
```

With mapping `Merge_Field__c = 'SignerName'`, `Anchor_Tag__c = '/sn1/'`:

Result XML:
```xml
<w:t>Acme Corp /sn1/</w:t>
```

DocuSign recognizes `/sn1/` as an anchor and places a `SignHere` tab at that location.

### How the Managed Package Handles Tracking

The integration does **not** create custom tracking records. Instead, it relies on the DocuSign managed package's native objects:

- `dsfs__DocuSign_Status__c` — envelope-level status (Sent, Delivered, Completed, etc.)
- `dsfs__DocuSign_Recipient_Status__c` — per-recipient status

The permission sets grant read-only access to `dsfs__DocuSign_Status__c` so DocGen users can view envelope progress via standard DocuSign reports or related lists.

---

## Configuration Reference

### Custom Metadata Type: `DocGen_DocuSign_Mapping__mdt`

| Field API Name | Type | Required | Description |
|----------------|------|----------|-------------|
| `Template_Id__c` | Text(18) | Yes | Salesforce ID of the `DocGen_Template__c` record |
| `Merge_Field__c` | Text(255) | Yes | Merge token name (without `{` `}`) |
| `Anchor_Tag__c` | Text(255) | Yes | DocuSign anchor string |
| `Anchor_Type__c` | Picklist | Yes | `SignHere`, `Text`, `Date`, `Checkbox` |
| `Unique_Suffix_Field__c` | Text(255) | No | Field API name whose value is appended as `-<value>` |
| `Active__c` | Checkbox | Yes | Default `true`; inactive mappings are skipped |

### Anchor Tag Format Reference

DocuSign anchor tags are arbitrary strings that DocuSign searches for in the document text. Common conventions:

| Convention | Anchor Example | Anchor Type | Purpose |
|------------|--------------|-------------|---------|
| Signature | `/sn1/` | `SignHere` | Signature placement |
| Text | `/t1/` | `Text` | Free-form text field |
| Date | `/d1/` | `Date` | Date signed field |
| Checkbox | `/c1/` | `Checkbox` | Checkbox field |

You can use any string, but DocuSign recommends keeping them short and unlikely to appear in normal document text.

### Unique Suffix Field Usage

When a mapping is used inside a repeating section (e.g., a table row loop), the same anchor tag would appear multiple times, causing DocuSign to place tabs on top of each other. The **Unique Suffix Field** solves this by appending a record-specific value:

```
Base anchor: /t1/
Suffix field value: 42
Final anchor in document: /t1/-42
```

This produces unique anchors per row, allowing DocuSign to place distinct tabs for each line item.

---

## Security Model

- **`with sharing`** enforced on `DocGenDocuSignService` and `DocGenDocuSignController`.
- **`WITH USER_MODE`** on all SOQL queries in DocuSign classes.
- **Recipient resolution** validates that the resolved Contact has a non-null Email before sending.
- **No guest user access** to DocuSign sending — only authenticated users with `DocGen_Admin` or `DocGen_User` permission sets can send.
- **Template access** is filtered by object type; users cannot send templates meant for a different object.

---

## Test Coverage Summary

| Test Class | Lines | Key Scenarios |
|------------|-------|---------------|
| `DocGenDocuSignServiceTest` | 274 | Success path, missing CV, missing recipient, resolved contact with no email, template override stub, default recipient resolution for Opportunity/Contract/Account/PersonAccount, no-default fallback |
| `DocGenDocuSignControllerTest` | 224 | Template loading, related contact loading for Opportunity/Account/Contract, generate-and-send success, null record handling, HTML template rejection, AuraHandledException wrapping |
| `DocGenTests` (anchor scenarios) | ~150 | Anchor injection with mappings, anchor suffix in loops, PowerPoint anchor skip (no injection), Word generation with no mappings |

Overall DocGen test coverage remains above 90%.

---

## Troubleshooting

### Anchor tags not recognized by DocuSign

**Symptoms:** Envelope sends successfully, but tabs do not appear in the expected locations.

**Causes & fixes:**
- **Font size too small:** DocuSign requires anchor text to be at least 8 pt. Ensure the merge field in the Word template uses a readable font size.
- **Anchor text wrapped in XML nodes:** If the anchor tag is split across multiple `<w:r>` runs, DocuSign may not detect it. Keep the merge field and anchor on the same line in the template.
- **XML escaping:** The integration XML-escapes the anchor string. If your anchor contains characters like `&`, `<`, or `>`, use simple alphanumeric anchors.
- **Inactive mapping:** Verify the CMT record is `Active__c = true` and `Template_Id__c` matches exactly.

### Envelope not appearing in Salesforce tracking

**Symptoms:** The envelope sends, but no `dsfs__DocuSign_Status__c` record appears.

**Causes & fixes:**
- **DocuSign Connect not configured:** Ensure DocuSign Connect is enabled in your DocuSign admin console and pointed at your Salesforce org.
- **Permission sets missing:** The running user must have read access to `dsfs__DocuSign_Status__c`. Re-assign `DocGen_Admin` or `DocGen_User`.
- **SourceId not set:** The integration sets `SourceId = sourceRecordId` on the envelope. If the managed package does not write back, check the Connect configuration for the SourceId mapping.

### Recipient resolution failures

**Symptoms:** Error: "Recipient is required for DocuSign sending."

**Causes & fixes:**
- **No Contact on Opportunity:** The Opportunity record must have a `ContactId` populated, or you must pass a specific `recipientContactId`.
- **No signer on Contract:** The Contract must have `CustomerSignedId` populated, or you must pass a specific Contact.
- **No primary AccountContactRole:** For standard Accounts, create an `AccountContactRole` with `IsPrimary = true`.
- **Person Account without PersonContactId:** Ensure the Person Account record is fully configured.
- **Resolved Contact has no Email:** Even if a Contact is found, DocuSign requires an Email. Populate the Contact's Email field.

### Flow action returns error but no envelopeId

**Symptoms:** `errorMessage` is populated; `envelopeId` is null.

**Check:**
- The template type is not HTML (HTML templates are rejected for server-side generation).
- The template has an active version with a linked ContentDocument.
- The recipient Contact has a valid Email.
- The DocuSign managed package is installed and the `dfsle` namespace is available.

---

## File Locations

| Component | Path |
|-----------|------|
| Service class | `force-app/main/default/classes/DocGenDocuSignService.cls` |
| Controller class | `force-app/main/default/classes/DocGenDocuSignController.cls` |
| Service tests | `force-app/main/default/classes/DocGenDocuSignServiceTest.cls` |
| Controller tests | `force-app/main/default/classes/DocGenDocuSignControllerTest.cls` |
| LWC bundle | `force-app/main/default/lwc/docGenDocuSignSender/` |
| CMT object | `force-app/main/default/objects/DocGen_DocuSign_Mapping__mdt/` |
| Modified service | `force-app/main/default/classes/DocGenService.cls` |
| Modified Flow action | `force-app/main/default/classes/DocGenFlowAction.cls` |
| Permission sets | `force-app/main/default/permissionsets/` |

---

## Known Limitations & Future Enhancements

1. **DocuSign template override is stubbed.** The `withDocuSignTemplate()` method exists but only logs an INFO message. Future iterations will support sending with a managed DocuSign template.
2. **Anchor injection is Word-only.** PowerPoint and HTML templates do not receive anchor tags even when `injectDocuSignAnchors = true`.
3. **Package manifest not updated.** `manifest/package.xml` does not yet list the new DocuSign classes, LWC, or CMT. Add them before creating a package version.
4. **No bulk sending.** Each Flow action or LWC invocation sends one envelope. For bulk scenarios, iterate in a Flow loop.
5. **Signed document is DOCX.** DocuSign returns the signed document in its original format. If a PDF is required, convert client-side after envelope completion.

---

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial DocuSign eSignature integration |
