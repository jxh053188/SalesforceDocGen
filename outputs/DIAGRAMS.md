# DocGen Architecture Diagrams

**Date:** 2026-04-25

---

## 1. Current System Architecture

```mermaid
graph TB
    subgraph "Salesforce Org"
        subgraph "Lightning Experience"
            RUNNER["docGenRunner LWC<br/>(Record Page Action)"]
            ADMIN["docGenAdmin LWC<br/>(Template Manager)"]
            QB["docGenQueryBuilder LWC<br/>(Visual SOQL Builder)"]
            SIG_SEND["docGenSignatureSender LWC<br/>(Send for Signature)"]
            BULK["docGenBulkRunner LWC<br/>(Bulk Generation)"]
        end

        subgraph "Experience Cloud"
            FLOW["DocGen Signature Submission Flow"]
            SIG_PAD["docGenSignaturePad LWC<br/>(Canvas Signing)"]
        end

        subgraph "Apex Layer"
            CTRL["DocGenController<br/>with sharing"]
            SVC["DocGenService<br/>with sharing"]
            BATCH["DocGenBatch<br/>global with sharing"]
            REND_SVC["DocGenRenditionService<br/>with sharing"]
            SIG_SVC["DocGenSignatureService<br/>without sharing"]
            SIG_CTRL["DocGenSignatureController<br/>without sharing"]
            BULK_CTRL["DocGenBulkController<br/>with sharing"]
            DATA["DocGenDataRetriever<br/>with sharing"]
            TM["DocGenTemplateManager<br/>with sharing"]
        end

        subgraph "Async Processing"
            Q["DocGenRenditionQueueable<br/>implements Queueable"]
            EVT["DocGen_Rendition_Event__e<br/>Platform Event"]
            TRG["DocGenRenditionTrigger<br/>After Insert"]
        end

        subgraph "Custom Objects"
            TPL["DocGen_Template__c"]
            VER["DocGen_Template_Version__c"]
            JOB["DocGen_Job__c"]
            SIG_REQ["DocGen_Signature_Request__c"]
            AUDIT["DocGen_Signature_Audit__c"]
            SETTINGS["DocGen_Settings__c"]
        end

        subgraph "Salesforce Standard"
            CV["ContentVersion"]
            CDL["ContentDocumentLink"]
            SOBJ["SObject Records"]
        end

        subgraph "External / Callout"
            NC["Named Credential<br/>DocGen_Loopback"]
            AP["Auth Provider<br/>(hardcoded consumer key)"]
        end
    end

    RUNNER -->|generateDocumentData| CTRL
    ADMIN -->|getAllTemplates/saveTemplate| CTRL
    BULK -->|submitJob| BULK_CTRL
    SIG_SEND -->|createSignatureRequest| SIG_CTRL

    CTRL --> SVC
    CTRL --> DATA
    CTRL --> TM
    BULK_CTRL --> BATCH
    BATCH --> SVC
    SVC --> DATA
    SVC --> TM
    SVC --> REND_SVC

    REND_SVC -->|addPendingRendition| EVT
    EVT --> TRG
    TRG --> Q
    Q -->|HTTP GET /connect/files/{id}/rendition| NC
    NC -->|OAuth| AP

    SIG_CTRL --> SIG_SVC
    FLOW --> SIG_PAD
    SIG_PAD -->|Flow Action| SIG_SVC

    DATA -->|Dynamic SOQL| SOBJ
    TM -->|Query| CV
    SVC -->|Insert| CV
    SVC -->|Insert| CDL
    SIG_SVC -->|Insert| CV
    SIG_SVC -->|Insert| AUDIT
    SIG_SVC -->|Update| SIG_REQ

    CTRL -->|CRUD| TPL
    CTRL -->|CRUD| VER
    BULK_CTRL -->|CRUD| JOB
    SIG_CTRL -->|CRUD| SIG_REQ

    RUNNER -.->|postMessage| VF["DocGenPDFEngine<br/>Visualforce Page"]
    ADMIN -.->|postMessage| VF
```

---

## 2. Data Flow: Single Record Document Generation

```mermaid
sequenceDiagram
    participant User
    participant Runner as docGenRunner LWC
    participant VF as DocGenPDFEngine VF
    participant Ctrl as DocGenController
    participant Svc as DocGenService
    participant Data as DocGenDataRetriever
    participant TM as DocGenTemplateManager
    participant CV as ContentVersion
    participant Rendition as DocGenRenditionService

    User->>Runner: Select template + click Generate
    Runner->>Ctrl: generateDocumentData(templateId, recordId)
    Ctrl->>TM: getTemplateFileContent(templateId)
    TM->>CV: Query latest/active ContentVersion
    TM-->>Ctrl: Return base64 template file
    Ctrl->>Data: getRecordData(recordId, baseObject, queryConfig)
    Data->>Data: Build dynamic SOQL
    Data->>Data: Database.query(query, USER_MODE)
    Data-->>Ctrl: Return Map<String, Object>
    Ctrl-->>Runner: Return {data, templateFile, templateType, outputFormat}

    alt Word/PowerPoint (Client-side)
        Runner->>Runner: PizZip + docxtemplater render
        alt Output = Native
            Runner-->>User: Download .docx/.pptx
        else Output = PDF
            Runner->>VF: postMessage(blob + filename)
            VF->>VF: docx-preview.js render
            VF->>VF: html2pdf.js convert
            VF-->>Runner: postMessage(ArrayBuffer)
            Runner-->>User: Download/save PDF
        end
    else HTML (Client-side)
        Runner->>Runner: Handlebars compile + render
        alt Output = PDF
            Runner->>VF: postMessage(html + filename)
            VF->>VF: html2pdf.js convert
            VF-->>Runner: postMessage(ArrayBuffer)
            Runner-->>User: Download/save PDF
        else Output = Native
            Runner-->>User: Download .html
        end
    end

    alt Server-side bulk / Flow
        Runner->>Svc: generateDocument(templateId, recordId)
        Svc->>Data: getRecordData(recordId, ...)
        Svc->>Svc: processXml (string replacement)
        Svc->>CV: Insert ContentVersion
        Svc->>Rendition: addPendingRendition(cvId, recordId)
        Rendition->>Rendition: enqueueRenditions()
        Rendition->>CV: [Async] HTTP GET rendition PDF
        Rendition->>CV: Insert PDF ContentVersion
        Rendition->>CDL: Link PDF to record
    end
```

---

## 3. Data Flow: E-Signature Experience Cloud

```mermaid
sequenceDiagram
    participant Sender as Salesforce User
    participant SenderLWC as docGenSignatureSender
    participant SenderCtrl as DocGenSignatureSenderController
    participant SIG_REQ as DocGen_Signature_Request__c
    participant Settings as DocGen_Settings__c

    participant Signer as External Signer
    participant EC as Experience Cloud
    participant Flow as DocGen Signature Submission Flow
    participant Pad as docGenSignaturePad LWC
    participant Val as DocGenSignatureValidator
    participant Finalizer as DocGenSignatureFinalizer
    participant SigSvc as DocGenSignatureService
    participant Audit as DocGen_Signature_Audit__c
    participant Rendition as DocGenRenditionService

    Sender->>SenderLWC: Select document + enter signer details
    SenderLWC->>SenderCtrl: createSignatureRequest(docId, recordId, name, email)
    SenderCtrl->>SenderCtrl: Generate SHA-256 secure token
    SenderCtrl->>SIG_REQ: Insert request (Status = Sent)
    SenderCtrl->>Settings: Get Experience_Site_Url__c
    SenderCtrl-->>SenderLWC: Return public URL with token
    SenderLWC-->>Sender: Display URL (copy to clipboard)

    Signer->>EC: Navigate to URL with token
    EC->>Flow: Start Flow with token input
    Flow->>Val: validateToken(token)
    Val->>SIG_REQ: Query by token (SYSTEM_MODE)
    alt Invalid / Already Signed
        Val-->>Flow: Return isValid=false + errorMessage
        Flow-->>Signer: Show error screen
    else Valid
        Val->>SIG_REQ: Update Status = Viewed
        Val-->>Flow: Return isValid=true + documentUrl
        Flow->>Pad: Render signature pad with documentUrl
        Signer->>Pad: Draw signature + click Submit
        Pad->>Pad: Capture canvas to base64 PNG
        Pad->>Flow: Emit signatureData
        Flow->>Finalizer: finalizeSignature(token, base64Image)
        Finalizer->>SigSvc: handleSignatureSubmission(token, base64Image)
        SigSvc->>SigSvc: stampSignature (inject PNG into DOCX)
        SigSvc->>Audit: Insert audit record (hash = PENDING_RENDITION:{cvId})
        SigSvc->>SIG_REQ: Update Status = Signed
        SigSvc->>Rendition: addPendingRendition(signedCvId, recordId)
        SigSvc->>Rendition: enqueueRenditions()
        Rendition->>Rendition: [Async] HTTP callout for PDF rendition
        Rendition->>Audit: Update hash with actual SHA-256 of PDF
        Rendition->>CV: Link PDF to record
        Finalizer-->>Flow: Complete
        Flow-->>Signer: Show success screen
    end
```

---

## 4. Component Dependency Diagram

```mermaid
graph LR
    subgraph "Client-Side Generation"
        RUNNER["docGenRunner"]
        ADMIN["docGenAdmin"]
        UTILS["docGenPdfUtils"]
        PREVIEW["docGenPreviewModal"]
    end

    subgraph "Shared Libraries (Static Resources)"
        PIZZIP["pizzip.js"]
        DOCX["docxtemplater.js"]
        HB["handlebars.js"]
        H2P["html2pdf.js"]
        FILESAVE["filesaver.js"]
        PDFJS["pdfjs"]
    end

    subgraph "Server-Side Generation"
        SVC["DocGenService"]
        REND["DocGenRenditionService"]
        BATCH["DocGenBatch"]
        Q["DocGenRenditionQueueable"]
    end

    subgraph "Data Layer"
        CTRL["DocGenController"]
        DATA["DocGenDataRetriever"]
        TM["DocGenTemplateManager"]
    end

    RUNNER -->|imports| UTILS
    ADMIN -->|imports| UTILS
    RUNNER -->|loads| PIZZIP
    RUNNER -->|loads| DOCX
    RUNNER -->|loads| HB
    RUNNER -->|loads| H2P
    RUNNER -->|loads| FILESAVE
    ADMIN -->|loads| PIZZIP
    ADMIN -->|loads| DOCX
    ADMIN -->|loads| HB
    ADMIN -->|loads| H2P
    ADMIN -->|loads| FILESAVE
    RUNNER -->|uses| PREVIEW
    ADMIN -->|uses| PREVIEW

    CTRL -->|calls| DATA
    CTRL -->|calls| TM
    SVC -->|calls| DATA
    SVC -->|calls| TM
    BATCH -->|calls| SVC
    SVC -->|uses| REND
    REND -->|enqueues| Q

    style RUNNER fill:#ffcccc
    style ADMIN fill:#ffcccc
    style SVC fill:#ccffcc
    style BATCH fill:#ccffcc
    style REND fill:#ccffcc
    style Q fill:#ccffcc
```

**Red nodes** indicate components with duplicated code.
**Green nodes** indicate server-side components.

---

## 5. Refactored Architecture (Post-Recommendations)

```mermaid
graph TB
    subgraph "Salesforce Org (Refactored)"
        subgraph "Lightning Experience"
            RUNNER2["docGenRunner LWC"]
            ADMIN2["docGenAdmin LWC"]
            GEN_UTILS["docGenGenerationUtils.js<br/>(shared module)"]
        end

        subgraph "Apex Layer"
            CTRL2["DocGenController<br/>with sharing"]
            SVC2["DocGenService<br/>with sharing"]
            BATCH2["DocGenBatch<br/>global with sharing"]
            BULK_CTRL2["DocGenBulkController<br/>with sharing"]
            DATA2["DocGenDataRetriever<br/>with sharing"]
            TM2["DocGenTemplateManager<br/>with sharing"]
        end

        subgraph "External Service (Optional)"
            PDF_SVC["External PDF Microservice<br/>(e.g., AWS Lambda)"]
        end

        subgraph "Custom Objects"
            TPL2["DocGen_Template__c"]
            VER2["DocGen_Template_Version__c"]
            JOB2["DocGen_Job__c<br/>+ Error_Details__c"]
        end

        subgraph "Salesforce Standard"
            CV2["ContentVersion"]
            CDL2["ContentDocumentLink"]
            SOBJ2["SObject Records"]
        end
    end

    RUNNER2 -->|imports| GEN_UTILS
    ADMIN2 -->|imports| GEN_UTILS
    GEN_UTILS -->|loads| PIZZIP2["pizzip.js"]
    GEN_UTILS -->|loads| DOCX2["docxtemplater.js"]
    GEN_UTILS -->|loads| HB2["handlebars.js"]

    RUNNER2 -->|postMessage| VF2["DocGenPDFEngine VF<br/>(iframe)"]
    ADMIN2 -->|postMessage| VF2

    CTRL2 --> SVC2
    CTRL2 --> DATA2
    CTRL2 --> TM2
    BULK_CTRL2 --> BATCH2
    BATCH2 --> SVC2
    SVC2 --> DATA2
    SVC2 --> TM2
    SVC2 --> CV2
    SVC2 --> CDL2

    BATCH2 -.->|Optional: future| PDF_SVC
    SVC2 -.->|Optional: future| PDF_SVC

    DATA2 -->|Dynamic SOQL<br/>USER_MODE| SOBJ2
    TM2 --> CV2

    style GEN_UTILS fill:#ccffcc
    style PDF_SVC fill:#ffffcc
    style VF2 fill:#ccccff
```

**Key Changes:**
1. Shared `docGenGenerationUtils.js` eliminates duplication
2. Loopback callout removed from standard path
3. External PDF microservice shown as optional future path for bulk
4. `Error_Details__c` field added to `DocGen_Job__c`
