# DocGen API Callout Analysis

**Date:** 2026-04-25

---

## Executive Summary

The DocGen package contains **two HTTP callout implementations** within the Apex codebase. The only production callout is a **self-referential loopback** to the same Salesforce org's Connect API for PDF rendition retrieval. This pattern is architecturally questionable, introduces unnecessary complexity and failure points, and is driven by a platform limitation (no native Apex API for converting DOCX/ContentVersion to PDF). A secondary test-only callout exists in `LoopbackTestQueueable.cls` for experimentation.

**Critical Finding:** The loopback callout is the single most fragile component in the async generation pipeline. It couples the package to org-specific URL configuration, external authentication setup, and asynchronous Connect API behavior that can return 202/404/301/302 for not-ready renditions.

---

## 1. Callout Inventory

### 1.1 Production Callout: PDF Rendition Retrieval

| Attribute | Detail |
|-----------|--------|
| **Class** | `DocGenRenditionService.cls` (line 53-83) |
| **Caller** | `DocGenRenditionQueueable.cls` (line 24) |
| **Endpoint** | `callout:DocGen_Loopback/services/data/v63.0/connect/files/{ContentDocumentId}/rendition?type=PDF` |
| **Method** | `GET` |
| **Purpose** | Retrieve a PDF rendition of a DOCX ContentVersion via Salesforce Connect API |
| **Authentication** | Named Credential `DocGen_Loopback` + External Credential `DocGen_Loopback_Auth` + Auth Provider `DocGen_Auth_Provider` (OAuth) |
| **Governor Limit** | Counts against daily async callout limit (number of Queueable executions × callouts) |
| **Retry Logic** | Max 10 retries with re-enqueue in `DocGenRenditionQueueable` |

**Response Handling:**
- `200 OK` — Rendition available; body parsed as Blob, inserted as new ContentVersion
- `202 Accepted` — Rendition not ready; re-enqueued for retry
- `404 Not Found` — Rendition not ready; re-enqueued for retry
- `301/302 Redirect` — Rendition not ready; re-enqueued for retry
- Other — Logged as error via `logRenditionError()`

**Data Flow:**
```
DocGenService.generateDocument()
  → DocGenRenditionService.addPendingRendition(cvId, recordId)
  → DocGenRenditionService.enqueueRenditions()
    → EventBus.publish(DocGen_Rendition_Event__e)
      → DocGenRenditionTrigger (Platform Event trigger)
        → System.enqueueJob(DocGenRenditionQueueable)
          → DocGenRenditionService.capturePdfRendition(cvId)
            → [HTTP GET] NamedCredential → Connect API /rendition?type=PDF
              → Insert PDF ContentVersion
              → Create ContentDocumentLink to record
              → Update Signature Audit hash
              → Delete source DOCX ContentDocument
```

### 1.2 Test/Experimental Callout: Loopback Test

| Attribute | Detail |
|-----------|--------|
| **Class** | `LoopbackTestQueueable.cls` (line 6-16) |
| **Endpoint** | `Url.getOrgDomainUrl() + '/services/data/v65.0/query/?q=SELECT+Id+FROM+Account+LIMIT+1'` |
| **Method** | `GET` |
| **Purpose** | Experimental/proof-of-concept for loopback callouts using session ID |
| **Authentication** | Manual `Authorization: Bearer {sessionId}` header |
| **Status** | **Unused in production** — appears to be a development utility |

---

## 2. Why This Callout Exists

### The Underlying Problem

Salesforce provides **no native Apex API** to convert a DOCX file (stored as ContentVersion) into a PDF. The `ContentVersion` object supports multiple file formats, but automatic PDF rendition generation for DOCX uploads is only available via:

1. **Connect API** (`/connect/files/{id}/rendition?type=PDF`) — Requires HTTP callout
2. **Browser-side rendering** (`docx-preview.js` + `html2pdf.js`) — Used in the LWC client path
3. **External service** (AWS Lambda, etc.) — Not currently implemented

The server-side path (Flow, Bulk generation) needs PDF output, so the Connect API callout was introduced as a workaround.

### Why a Self-Callout Instead of Direct Apex?

The Connect API is a **REST API**, not an Apex callable class. There is no `ContentVersion.convertToPdf()` method. The self-callout is a forced pattern, not an architectural choice.

**However**, the specific implementation using a Named Credential pointing back to the same org is a design decision that carries significant baggage:

| Concern | Impact |
|---------|--------|
| **Named Credential URL is hardcoded** | Cannot deploy to a different org without metadata modification |
| **Requires Auth Provider + OAuth setup** | Adds setup complexity; hardcoded consumer key is a security risk |
| **Asynchronous by nature** | Platform Event → Queueable adds latency (seconds to minutes) |
| **Connect API rendition is not immediate** | DOCX upload does not instantly create a PDF rendition; the callout may fail multiple times before the rendition is ready |
| **Consumes daily callout limits** | Each retry counts against org limits |
| **Failure surface area is large** | Auth, networking, Connect API availability, rendition generation delays |

---

## 3. Authentication Architecture

### 3.1 Component Chain

```
Apex Code
  → Named Credential: DocGen_Loopback
    → External Credential: DocGen_Loopback_Auth
      → Auth Provider: DocGen_Auth_Provider
        → Salesforce OAuth (same org)
```

### 3.2 Named Credential: `DocGen_Loopback`

**File:** `force-app/main/default/namedCredentials/DocGen_Loopback.namedCredential-meta.xml`

| Property | Value | Issue |
|----------|-------|-------|
| `parameterValue` (URL) | `https://click-less-academy-dev-ed.develop.my.salesforce.com` | **Hardcoded to a specific dev org** |
| `calloutStatus` | `Enabled` | — |
| `generateAuthorizationHeader` | `true` | — |
| `allowMergeFieldsInBody` | `false` | Good (prevents injection) |
| `allowMergeFieldsInHeader` | `false` | Good (prevents injection) |
| `namedCredentialType` | `SecuredEndpoint` | — |

**Critical Issue:** The URL is hardcoded to `click-less-academy-dev-ed.develop.my.salesforce.com`. This makes the metadata non-portable. Every new org requires manual metadata update or post-deploy configuration.

**Recommendation:** Replace with `Url.getOrgDomainUrl().toExternalForm()` at runtime, or use a Custom Setting/Metadata to store the org URL, or require manual Named Credential setup post-deployment.

### 3.3 External Credential: `DocGen_Loopback_Auth`

**File:** `force-app/main/default/externalCredentials/DocGen_Loopback_Auth.externalCredential-meta.xml`

| Property | Value |
|----------|-------|
| `authenticationProtocol` | `Oauth` |
| `authProvider` | `DocGen_Auth_Provider` |
| `parameterType` (principal) | `NamedPrincipal` (Admin group) |

The Named Principal means a single admin user authorizes the connection on behalf of the org. This is acceptable for server-to-server, but the user must complete an OAuth flow in Setup after deployment.

### 3.4 Auth Provider: `DocGen_Auth_Provider`

**File:** `force-app/main/default/authproviders/DocGen_Auth_Provider.authprovider-meta.xml`

| Property | Value | Issue |
|----------|-------|-------|
| `consumerKey` | `3MVG9GCMQoQ6rpzRPQ7XyvUJAs56dc4LAMayBMsZAkQ4AA3i7HVv4dEWEx18ynPyb9QhoAOPDfsARWQS7V50d` | **Hardcoded real consumer key in version control** |
| `consumerSecret` | `Placeholder_Value` | Correctly placeholdered |
| `providerType` | `Salesforce` | — |
| `isPkceEnabled` | `true` | Good |
| `defaultScopes` | `api refresh_token` | — |

**Critical Security Issue:** The `consumerKey` is a real connected app client ID. Even though the `consumerSecret` is placeholdered, the client ID should also be treated as sensitive. It should be replaced with `Placeholder_Value` and setup instructions added to documentation.

---

## 4. Security Analysis

### 4.1 Threat Model

| Threat | Likelihood | Impact | Mitigation Status |
|--------|-----------|--------|-------------------|
| Consumer key leaked via git history | High (already in repo) | Medium (key alone is not sufficient for auth) | **Not mitigated** |
| Named Credential URL points to wrong org | High (every deployment) | High (callouts fail, auth breaks) | **Not mitigated** |
| OAuth token compromised | Low | High (full API access as named principal) | Mitigated by Salesforce token storage |
| Callout intercepted (MITM) | Very Low | High | Mitigated by HTTPS |
| Replay attack with captured token | Low | Medium | Mitigated by OAuth token expiry |

### 4.2 Access Level in Callout Context

The callout itself runs in the context of the **Named Principal** (admin user who authorized the External Credential). This means:

- The Connect API call executes with that user's permissions, not the running Queueable's user
- If the admin has broad access, the callout can retrieve any file rendition
- This is acceptable for an internal org callout but should be documented

### 4.3 Input Validation

The `capturePdfRendition()` method takes an `Id cvId` parameter and queries:

```apex
ContentVersion cv = [
    SELECT ContentDocumentId, Title, PathOnClient 
    FROM ContentVersion 
    WHERE Id = :cvId 
    WITH SYSTEM_MODE 
    LIMIT 1
];
```

The `Id` type binding prevents SOQL injection. The `ContentDocumentId` is then concatenated into the REST endpoint URL. Because `ContentDocumentId` comes from a trusted database query (not user input), this is safe.

**However**, there is **no validation** that the source ContentVersion is actually a DOCX or that the calling user has access to it before making the callout. `WITH SYSTEM_MODE` bypasses sharing.

---

## 5. Performance & Governor Limits

### 5.1 Limits Consumed

| Limit | Consumption | Notes |
|-------|-------------|-------|
| Async Callouts per 24h | 1 per rendition attempt | Retries multiply this |
| Queueable jobs per 24h | 1 per rendition batch + retries | Max 10 retries per failed CV |
| DML Statements | 3+ per rendition (insert CV, insert CDL, update Audit) | Plus cleanup delete |
| SOQL Queries | 3+ per rendition | CV lookup, CDL lookup, Audit lookup |
| Heap Size | PDF Blob stored in memory | Could approach limits for large PDFs |

### 5.2 Batch Scaling Concern

In `DocGenBatch.cls` (batch size 10), if all 10 records generate DOCX files and request PDF renditions:

- 10 Platform Events published
- 10 Queueable jobs enqueued (or 1 per trigger batch)
- Each Queueable makes 1+ HTTP callouts
- With retries, this could consume dozens of callouts per batch

**For bulk jobs with thousands of records, this is not sustainable.** The daily async callout limit (varies by edition) will eventually be reached.

### 5.3 Rendition Latency

The Connect API does not guarantee immediate PDF rendition availability after DOCX insert. The code handles `202/404/301/302` with retries, but:

- Each retry re-enqueues a Queueable job
- Between retries, the document may take **seconds to minutes** to render
- There is **no exponential backoff** — retries happen as fast as Queueable processing allows
- The `retryCount < 10` limit is arbitrary; 10 retries may not be sufficient for slow renditions

---

## 6. Error Handling & Observability

### 6.1 Retry Logic

```apex
if (!failedCvs.isEmpty() && retryCount < 10) {
    System.enqueueJob(new DocGenRenditionQueueable(failedCvs, retryCount + 1));
}
```

**Strengths:**
- Distinguishes "not ready yet" (`202/404/301/302`) from hard failures
- Hard failures are logged to `DocGen_Signature_Audit__c`
- Retry preserves the Map of CV-to-Record IDs

**Weaknesses:**
- No exponential backoff
- No delay between retries
- After 10 failures, the job silently drops the failed items (no final error notification)
- `DocGen_Job__c` (bulk job tracker) is not updated with rendition failures

### 6.2 Error Logging

Errors are logged to `DocGen_Signature_Audit__c` via `logRenditionError()`. This creates audit records with:
- `Document_Hash_SHA256__c` = `'PENDING_RENDITION:' + sourceCvId`
- `Error_Message__c` = timestamp + error message

**Issue:** This conflates signature audit records with rendition failure records. For bulk generation (non-signature), the audit record is created solely for error logging, which pollutes the audit trail.

### 6.3 Missing Monitoring

There is **no centralized logging** for:
- Total callout volume
- Retry rates
- Average time-to-rendition
- Jobs that exhaust all 10 retries
- Daily callout limit proximity

---

## 7. Alternatives to the Loopback Callout

### 7.1 Option A: Eliminate Server-Side PDF Generation

**Approach:** Remove the server-side PDF path entirely. Force all PDF generation to happen client-side.

**Pros:**
- Zero callouts
- Zero async complexity
- Instant feedback to user

**Cons:**
- Flow/bulk actions cannot produce PDFs
- Bulk generation would need a different model (e.g., client-side batch runner)
- E-signatures would need to return DOCX instead of PDF

**Feasibility:** Partial — would require significant UX changes for bulk/Flow.

### 7.2 Option B: External PDF Conversion Service

**Approach:** Replace loopback with an external microservice (e.g., AWS Lambda, Heroku, Azure Function) that accepts a DOCX Blob and returns a PDF.

**Pros:**
- No self-referential callout
- No org-specific auth setup
- Faster rendition (no Connect API delay)
- Scales independently

**Cons:**
- Additional infrastructure to maintain
- Data leaves Salesforce (security review needed)
- Network latency
- Cost

**Feasibility:** High — architecturally clean but requires external dependency.

### 7.3 Option C: Keep DOCX as Final Format for Server Paths

**Approach:** Accept that server-side generation produces DOCX. Only convert to PDF client-side.

**Pros:**
- Eliminates callout entirely
- Simplest server architecture

**Cons:**
- Users expecting PDF from Flow/bulk will be disappointed
- E-signature final documents would be DOCX

**Feasibility:** Low — PDF is likely a hard requirement.

### 7.4 Option D: Improve Loopback Setup Experience

**Approach:** Keep the loopback but make setup automatic.

**Implementation:**
1. Replace hardcoded URL in Named Credential with a post-deploy script using Metadata API
2. Replace hardcoded consumer key with `Placeholder_Value`
3. Add a Setup Wizard step that:
   - Detects org URL (`Url.getOrgDomainUrl()`)
   - Guides admin through Auth Provider Connected App creation
   - Updates Named Credential URL via Metadata API or instructs manual update

**Pros:**
- Minimal code change
- Retains current functionality
- Makes deployment repeatable

**Cons:**
- Still has all loopback architectural weaknesses
- Metadata API updates from Apex require care

**Feasibility:** High — recommended as immediate fix.

---

## 8. Recommendations

### Critical

| # | Recommendation | Effort | Impact |
|---|---------------|--------|--------|
| 1 | **Replace hardcoded consumer key** in `DocGen_Auth_Provider.authprovider-meta.xml` with `Placeholder_Value` and document Connected App setup steps. | Small | Prevents credential leak |
| 2 | **Replace hardcoded org URL** in `DocGen_Loopback.namedCredential-meta.xml`. Either use `Url.getOrgDomainUrl()` at runtime (requires code change to bypass Named Credential) or implement post-deploy setup wizard update. | Small-Medium | Enables deployment to any org |
| 3 | **Add per-record error tracking** in `DocGenRenditionQueueable` after max retries exhausted. Update `DocGen_Job__c` with failure details. | Small | Prevents silent data loss |
| 4 | **Separate rendition error logging** from signature audit records. Create a dedicated `DocGen_Rendition_Log__c` object or use `DocGen_Job__c.Error_Details__c`. | Small | Cleaner data model |

### High

| # | Recommendation | Effort | Impact |
|---|---------------|--------|--------|
| 5 | **Add exponential backoff** to retry logic. Instead of immediate re-enqueue, delay retries using `System.scheduleJob()` or a delay field. | Medium | Reduces callout volume and governor limit pressure |
| 6 | **Implement a maximum daily callout safety valve**. Before enqueueing, check how many callouts have been made today (via custom counter or Limits.getCallouts()) and fail gracefully if approaching limit. | Medium | Prevents org-wide callout exhaustion |
| 7 | **Document the `without sharing` + Named Principal interaction**. The Queueable runs `with sharing`, but the callout executes as the Named Principal. Explain this in ApexDoc. | Small | Security audit compliance |
| 8 | **Evaluate external PDF service** as a long-term replacement for the loopback. Document the decision and create a spike story. | Medium | Removes architectural debt |

### Medium

| # | Recommendation | Effort | Impact |
|---|---------------|--------|--------|
| 9 | **Delete `LoopbackTestQueueable.cls`** if it is not referenced by any test or production code. It uses manual session ID passing, which is an anti-pattern. | Small | Reduces package size and confusion |
| 10 | **Add timeout to HttpRequest** in `capturePdfRendition()`. The default is 10s; for large renditions, 30s may be more appropriate. | Small | Prevents premature timeout failures |
| 11 | **Monitor and alert** on `DocGen_Signature_Audit__c` records where `Document_Hash_SHA256__c` starts with `PENDING_RENDITION:`. These indicate incomplete or failed renditions. | Small | Operational visibility |
| 12 | **Cache ContentVersion metadata** in `capturePdfRendition()` if multiple renditions are requested in the same transaction. | Small | Reduces redundant SOQL |

---

## 9. Decision Matrix: Loopback vs. External Service

| Criteria | Current Loopback | External Service | No Server PDF |
|----------|-----------------|------------------|-------------|
| Setup Complexity | High (Auth Provider + OAuth + Named Credential) | Medium (Named Credential to external) | Low |
| Org Portability | Poor (hardcoded metadata) | Good | Excellent |
| Scalability | Poor (governor limits, retries) | Excellent | Excellent |
| Cost | Free (within org limits) | Infrastructure cost | Free |
| Security Surface | Medium (OAuth, self-callout) | Medium (data leaves org) | Low |
| Reliability | Low (rendition delays, auth fragility) | High | High |
| Implementation Effort | Done | Medium | Medium |
| User Experience | Async delay | Fast async | Instant (client only) |

**Recommended Path (Short Term):** Implement Recommendations 1-4 (Critical) and 5-8 (High) to stabilize the existing loopback.

**Recommended Path (Long Term):** Spike an external PDF conversion service (Option B) as the permanent replacement for the loopback callout. This removes the most fragile component in the architecture.

---

## 10. Files Referenced

| File | Purpose |
|------|---------|
| `DocGenRenditionService.cls` | Makes the loopback HTTP callout to Connect API |
| `DocGenRenditionQueueable.cls` | Async processor with retry logic |
| `DocGenRenditionTrigger.trigger` | Platform Event trigger that enqueues Queueable |
| `LoopbackTestQueueable.cls` | Experimental/test callout utility |
| `DocGen_Loopback.namedCredential-meta.xml` | Hardcoded loopback URL |
| `DocGen_Loopback_Auth.externalCredential-meta.xml` | OAuth external credential |
| `DocGen_Auth_Provider.authprovider-meta.xml` | Auth provider with hardcoded consumer key |

---

*End of API Callout Analysis*
