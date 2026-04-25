---
name: Docx mock creation pattern for Apex tests
description: How to create minimal valid DOCX blobs using Compression.ZipWriter in Apex tests for DocGen and signature stamping
type: reference
---

**Pattern:** Use `Compression.ZipWriter` to build a minimal ZIP archive with the entries that `Compression.ZipReader` expects:

```apex
private static Blob createTestDocx(String documentXml) {
    Compression.ZipWriter writer = new Compression.ZipWriter();
    writer.addEntry('word/document.xml', Blob.valueOf(documentXml));
    writer.addEntry('[Content_Types].xml', Blob.valueOf(
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '</Types>'
    ));
    return writer.getArchive();
}
```

**Why it works:**
- `Compression.ZipWriter` and `Compression.ZipReader` are native Salesforce classes available in API 60.0+.
- A DOCX is just a ZIP with specific entries. `DocGenService.processXml` looks for `word/document.xml`, `word/header*.xml`, and `word/footer*.xml`.
- `DocGenSignatureService.stampSignatureToBlob` looks for `[Content_Types].xml`, `word/_rels/document.xml.rels`, and `word/document.xml`. Missing optional entries are handled gracefully (fall through to `else` copy branch).

**When to apply:**
- Any test that calls `DocGenService.generateDocument()` with a Word template.
- Any test that calls `DocGenSignatureService.stampSignatureToBlob()` or `stampSignature()`.
- Any test that validates `DocGenTemplateManager.getTemplateFileContent()` with a DOCX fallback.

**Project-specific notes:**
- API version: 65.0
- Field-level: `ContentVersion.VersionData` accepts the Blob directly.
- Avoid creating real binary DOCX files; the native ZipWriter is sufficient and keeps tests fast.
