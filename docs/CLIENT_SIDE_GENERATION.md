# DocGen Client-Side Generation Architecture

**Date:** 2026-04-25
**Applies to:** `feature/remove-loopback-bulk` and later

---

## Overview

With the removal of the Loopback Callout and Bulk Generation infrastructure, all document generation in DocGen now follows a **client-side-first** architecture. The server (Apex) is responsible for data retrieval and DOCX/PPTX assembly. The client (LWC / browser) is responsible for format conversion, PDF rendering, and user download.

This document explains the data flow for each generation path.

---

## Server-Side Responsibility: DOCX / PPTX Assembly

The Apex layer performs the following steps:

1. **Retrieve Template Metadata** — `DocGenController.generateDocumentData()` queries `DocGen_Template__c` for the base object, query config, template type, output format, and title format.
2. **Fetch Record Data** — `DocGenDataRetriever.getRecordData()` executes the configured SOQL and returns a nested `Map<String, Object>` representing parent fields and child lists.
3. **Load Template File** — `DocGenTemplateManager.getTemplateFileContent()` returns the base64-encoded ContentVersion of the uploaded template file.
4. **Merge Tags** — `DocGenService.processXml()` walks the ZIP archive (DOCX or PPTX), finds the target XML files (`word/document.xml`, `ppt/slides/slide*.xml`), and replaces merge tags with record data. Supports:
   - Simple field replacement (`{Name}`)
   - Conditional sections (`{#Section}...{/Section}`)
   - List iteration with smart table row expansion
5. **Save Result** — `DocGenService.saveFile()` inserts a new `ContentVersion` linked to the source record and returns the `ContentDocumentId`.

**Important:** `DocGenService.saveFile()` no longer accepts an `outputFormat` parameter. It always produces the native template type (DOCX for Word, PPTX for PowerPoint). If the template is configured for PDF output, the PDF conversion happens later on the client.

### Security Model on the Server

- All queries use `WITH USER_MODE` where possible.
- `DocGenController.generateDocumentData()` validates that the user has access to the template before proceeding.
- `ContentVersion` insertion uses standard sharing; the resulting document is linked to the source record via `ContentDocumentLink`.

---

## Client-Side Responsibility: PDF Conversion & Download

The LWC components (`docGenRunner`, `docGenAdmin`, `docGenSignaturePad`) handle PDF conversion in the browser using JavaScript libraries loaded as static resources:

| Library | Purpose |
|---------|---------|
| `docxtemplater` + `pizzip` | Client-side DOCX tag replacement (fallback/parallel path) |
| `mammoth` | Converts DOCX to HTML for preview |
| `html2pdf` | Converts HTML to PDF in the browser |
| `jszip` | ZIP manipulation for DOCX internals |
| `filesaver` | Triggers browser download |

### Standard Record Page Flow

```
User clicks "Generate" in docGenRunner
  → LWC calls Apex: DocGenController.generateDocumentData(templateId, recordId)
  ← Apex returns: { data, templateFile, templateType, outputFormat, titleFormat }

  → LWC (if Word/PPT) merges tags client-side OR uses Apex-generated DOCX
  → If outputFormat == 'PDF':
      → Convert DOCX → HTML (mammoth)
      → Convert HTML → PDF (html2pdf.js)
      → Trigger browser download
  → If outputFormat == 'DOCX':
      → Trigger browser download directly
```

### Flow Action Path

```
Flow calls DocGenFlowAction.generateDocument(requests)
  → Each request invokes DocGenService.generateDocument()
  → Apex returns ContentDocumentId (always DOCX/PPTX)

Flow receives the ContentDocumentId.
No PDF conversion occurs automatically.
If PDF is required, the Flow must pass the ContentDocumentId to a client component
or the user must download the DOCX and convert it locally.
```

### E-Signature Flow

```
User requests signature (docGenSignatureSender)
  → Apex creates DocGen_Signature_Request__c with secure token
  → Signer receives email with link to Experience Site

Signer opens site (DocGenVerify page)
  → LWC loads document via DocGenSignatureController.fetchDocumentData()
  → Signer draws signature in docGenSignaturePad
  → LWC calls DocGenSignatureController.stampAndReturnSource(token, base64Image)
    → Apex: DocGenSignatureService.stampSignature() injects PNG into DOCX
    → Returns base64 of signed DOCX to LWC
  → LWC renders signed DOCX in preview modal
  → If user wants PDF, LWC converts DOCX → HTML → PDF client-side
  → LWC calls DocGenSignatureController.finishSignatureUpload() to save final file
```

**Note:** The async signature finalizer (`DocGenSignatureFinalizer`) is an alternative path for headless processing. It stamps the signature server-side and stores a signed DOCX. It no longer triggers any PDF rendition.

---

## Data Flow Diagram

### Single Record Generation (LWC)

```
+-----------+     generateDocumentData()     +-------------+
|  LWC UI   |  ----------------------------> |  Apex Ctrl  |
| (Runner)  |                                |  (DocGen)   |
+-----------+                                +-------------+
     ^                                              |
     |         {data, templateFile, ...}            |
     |  <-------------------------------------------+
     |
     |  Client-side merge + PDF conversion
     v
+-----------+
|  Browser  |
|  Download |
+-----------+
```

### Flow Action Generation

```
+-----------+     generateDocument()        +-------------+
|   Flow    |  ----------------------------> | DocGenFlow  |
|           |                               |   Action    |
+-----------+                               +-------------+
     ^                                              |
     |         ContentDocumentId (DOCX)             |
     +----------------------------------------------+
```

### E-Signature (Hybrid Client-Server)

```
+-----------+     stampAndReturnSource()     +-----------------+
|  LWC Pad  |  ----------------------------> | DocGenSignature |
|           |                               |    Controller   |
+-----------+                               +-----------------+
     ^                                              |
     |         base64 signed DOCX                   |
     |  <-------------------------------------------+
     |
     |  Optional: client-side PDF conversion
     v
+-----------+     finishSignatureUpload()   +-----------------+
|  LWC UI   |  ----------------------------> | DocGenSignature |
|           |                               |    Controller   |
+-----------+                               +-----------------+
```

---

## File Locations

- **Apex Service:** `force-app/main/default/classes/DocGenService.cls`
- **Apex Controller:** `force-app/main/default/classes/DocGenController.cls`
- **Flow Action:** `force-app/main/default/classes/DocGenFlowAction.cls`
- **Signature Service:** `force-app/main/default/classes/DocGenSignatureService.cls`
- **Runner LWC:** `force-app/main/default/lwc/docGenRunner/`
- **Admin LWC:** `force-app/main/default/lwc/docGenAdmin/`
- **Signature Pad LWC:** `force-app/main/default/lwc/docGenSignaturePad/`
- **Static Resources:** `force-app/main/default/staticresources/docxtemplater`, `html2pdf`, `mammoth`, `jszip`, `pizzip`, `filesaver`

---

## When PDF Is and Is Not Available

| Path | PDF Available? | How |
|------|---------------|-----|
| Record page LWC (`docGenRunner`) | Yes | Client-side conversion via html2pdf.js |
| Template Manager preview | Yes | Client-side conversion |
| Flow Action | No | Returns DOCX ContentDocumentId only |
| E-signature (default) | No | Signed DOCX is the default output |
| E-signature (with client preview) | Yes | User can trigger client-side PDF before finalizing upload |
| Bulk / Batch | N/A | Feature removed |

---

## Performance Considerations

- **Client-side PDF conversion is CPU-bound in the browser.** Large documents with many images may take several seconds. The UI should show a spinner during conversion.
- **Server-side DOCX generation is synchronous and fast.** It does not consume Queueable or Callout limits.
- **No governor limit pressure** from rendition retries or bulk batches.

---

## Browser Compatibility

Client-side PDF conversion relies on modern browser APIs:
- `Blob`, `FileReader`, `URL.createObjectURL`
- Canvas API (for signature drawing)
- ES6+ JavaScript features

Supported browsers: Chrome, Firefox, Safari, Edge (latest 2 versions).

---

## Future Enhancement Suggestions

1. **Add an optional server-side PDF microservice** (external Lambda/Heroku) for Flow users who absolutely need automated PDF output without browser interaction.
2. **Add a client-side batch runner LWC** that iterates over a list view and generates documents one by one, preserving the client-side PDF path for "bulk-like" use cases.
3. **Improve signature PDF conversion** by providing a one-click "Download as PDF" button in the post-signing confirmation screen.
