# P1 High Severity Security Fixes — Design Plan

**Branch**: `feature/security-p1-high`  
**Date**: 2026-04-26  
**Classification**: Dev + Admin work (code changes + custom permission metadata)  

---

## 1. EXISTING METADATA REVIEW

- **Token generation** (`DocGenSignatureSenderController.cls`, line 28): Uses `Math.random()` + `System.now().getTime()` + `signerEmail` as SHA-256 input. Class is already `public with sharing`.
- **ContentDocumentLink Visibility**: Two locations set `Visibility = 'AllUsers'`:
  - `DocGenController.cls`, line 57 (`saveGeneratedDocument`)
  - `DocGenSignatureService.cls`, line 103 (`stampSignature`)
- **`without sharing` classes** (6 total):
  - `DocGenSignatureController.cls` — LWC controller, `@AuraEnabled` methods, all SOQL already uses `WITH SYSTEM_MODE`, but DML (`update req`, `insert audit`, `insert ContentDistribution`) is plain DML.
  - `DocGenSignatureValidator.cls` — Flow invocable wrapper around `DocGenSignatureController.validateToken`.
  - `DocGenSignatureSubmitter.cls` — Flow invocable wrapper around `DocGenSignatureService.handleSignatureSubmission`.
  - `DocGenSignatureFinalizer.cls` — Flow invocable wrapper around `DocGenSignatureService.handleSignatureSubmission`.
  - `DocGenSignatureService.cls` — Helper class, public methods called by Flow and LWC. Contains DML.
  - `DocGenAuthenticatorController.cls` — Public site controller, one query missing `WITH SYSTEM_MODE`.
- **Permission sets**: `DocGen_Admin`, `DocGen_User`, `DocGen_Guest_Signature` exist. No custom permissions exist in the project.
- **Tests**: `DocGenTests.cls` tests `previewRecordData`. `DocGenSignatureControllerTest.cls` tests all 6 `without sharing` classes. `DocGenSignatureServiceTest.cls` tests service methods. All tests currently run as the default system user.

---

## 2. ISSUES & FIXES

### Issue 1 — Predictable Token Generation (HIGH)

**File**: `force-app/main/default/classes/DocGenSignatureSenderController.cls` (line 28)  
**Current code**:
```apex
Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(System.now().getTime()) + Math.random() + signerEmail));
String token = EncodingUtil.convertToHex(hash);
```

**Problem**: `Math.random()` is not cryptographically secure. `System.now().getTime()` has low entropy. A determined attacker could narrow the token space and potentially guess valid tokens.

**Fix**: Replace the predictable input with a high-entropy source.
```apex
Blob aesKey = Crypto.generateAesKey(256);
Blob hash = Crypto.generateDigest('SHA-256', aesKey);
String token = EncodingUtil.convertToHex(hash);
```
This uses Salesforce's cryptographically secure random number generator via `Crypto.generateAesKey(256)`.

**Risks**: Token length and format remain the same (hex-encoded SHA-256 = 64 chars). No downstream changes required. Existing tokens in the database remain valid.

---

### Issue 2 — ContentDocumentLink Visibility = 'AllUsers' (HIGH)

**Files**:
- `force-app/main/default/classes/DocGenController.cls` (line 57)
- `force-app/main/default/classes/DocGenSignatureService.cls` (line 103)

**Current code** (both locations):
```apex
cdl.Visibility = 'AllUsers';
```

**Problem**: `AllUsers` exposes linked documents to ALL users in the org, including Experience Cloud external users and community users, bypassing record-level security.

**Fix**: Change both to `Visibility = 'InternalUsers'`.

```apex
cdl.Visibility = 'InternalUsers'; // Restrict to internal users only
```

Add a comment explaining the security rationale at each location.

**Risks**: If any business process relies on external/community users accessing these documents via the ContentDocumentLink, those users will lose access. In the DocGen signature flow, signed documents are returned to the signer via the LWC/controller — they do not need direct ContentDocumentLink access. In the normal document generation flow, generated documents are linked to internal records for internal users. **Acceptable risk**.

**Test impact**: Tests verify link existence via SOQL (`SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :X`). Visibility does not affect these queries. No test changes required.

---

### Issue 3 — `without sharing` Exposure (HIGH)

**Files** (6 classes):
1. `DocGenSignatureController.cls`
2. `DocGenSignatureValidator.cls`
3. `DocGenSignatureSubmitter.cls`
4. `DocGenAuthenticatorController.cls`
5. `DocGenSignatureFinalizer.cls`
6. `DocGenSignatureService.cls`

**Problem**: Entire classes bypass sharing rules. A minimally-permissioned user who can call `@AuraEnabled` methods or Flow invocables could access or modify data they do not own or have sharing access to.

**Fix Strategy**:
- Change class-level declaration from `public without sharing` to `public with sharing` on all 6 classes.
- For SOQL queries that already use `WITH SYSTEM_MODE`, no query changes needed.
- For DML that must run in elevated context (guest user signature flow), create **inner `private without sharing` helper classes** ONLY in the classes where specific methods need elevation.

**Detailed per-class plan:**

#### A. `DocGenSignatureController.cls`
Change to `public with sharing`. Create an inner helper for elevated DML:

```apex
private without sharing class SystemModeHelper {
    static void updateSignatureRequest(DocGen_Signature_Request__c req) {
        update req;
    }
    static void insertSignatureAudit(DocGen_Signature_Audit__c audit) {
        insert audit;
    }
    static void insertContentDistribution(ContentDistribution cd) {
        insert cd;
    }
    static Id saveGeneratedDocument(Id recordId, String fileName, String base64Data, String extension) {
        // Same logic as DocGenController.saveGeneratedDocument but in without-sharing context
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName + (extension.startsWith('.') ? extension : '.' + extension);
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.IsMajorVersion = true;
        insert cv;
        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE].ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocId;
        cdl.LinkedEntityId = recordId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'InternalUsers';
        insert cdl;
        return contentDocId;
    }
}
```

Refactor these methods to use the helper:
- `validateToken` (line 84-85): `update req;` → `SystemModeHelper.updateSignatureRequest(req);`
- `validateToken` (line 114): `insert cd;` → `SystemModeHelper.insertContentDistribution(cd);`
- `stampAndReturnSource` (line 154-155): `update req;` → `SystemModeHelper.updateSignatureRequest(req);`
- `stampAndReturnSource` (line 163-164): `insert audit;` → `SystemModeHelper.insertSignatureAudit(audit);`
- `finishSignatureUpload` (line 193-198): `DocGenController.saveGeneratedDocument(...)` → `SystemModeHelper.saveGeneratedDocument(...)`

#### B. `DocGenSignatureValidator.cls`
Change to `public with sharing`. No helper needed — this class only delegates to `DocGenSignatureController.validateToken`, which will handle its own elevation.

#### C. `DocGenSignatureSubmitter.cls`
Change to `public with sharing`. No helper needed — delegates to `DocGenSignatureService.handleSignatureSubmission`, which is only called from Flow running in system context.

#### D. `DocGenSignatureFinalizer.cls`
Change to `public with sharing`. No helper needed — delegates to `DocGenSignatureService.handleSignatureSubmission`, called from Flow in system context.

#### E. `DocGenSignatureService.cls`
Change to `public with sharing`. No helper needed because:
- `stampSignatureToBlob` is read-only (SOQL with `WITH SYSTEM_MODE`).
- `stampSignature` and `handleSignatureSubmission` are only invoked from Flow invocables (`DocGenSignatureSubmitter`, `DocGenSignatureFinalizer`). Flow runs in system context, so DML succeeds even in a `with sharing` class.
- If `stampSignature` is ever called from a non-system context in the future, the caller will need to ensure appropriate permissions or use an inner helper. Document this assumption in a class-level comment.

Remove the inline comment at line 5 (`// We use without sharing to query the Audit table securely for public users`) since it will no longer be accurate.

#### F. `DocGenAuthenticatorController.cls`
Change to `public with sharing`. Add `WITH SYSTEM_MODE` to the SOQL query:

```apex
List<DocGen_Signature_Audit__c> audits = [
    SELECT Id, Signed_Date__c, IP_Address__c, Signature_Request__r.Signer_Name__c, Signature_Request__r.Signer_Email__c
    FROM DocGen_Signature_Audit__c
    WHERE Document_Hash_SHA256__c = :fileHash
    WITH SYSTEM_MODE
    LIMIT 1
];
```

No helper needed — this method is read-only.

**Risks**:
- Guest users (Experience Site) who call `DocGenSignatureController` methods rely on elevated DML. The inner helper ensures this continues to work.
- Flow invocables that previously relied on `without sharing` will continue to work because Flow system context carries through.
- If any other code directly calls `DocGenSignatureService.stampSignature` from a user context, the insert may fail. Add a class-level doc comment warning about this.

---

### Issue 4 — Client-Side SOQL Trust Boundary (HIGH)

**File**: `force-app/main/default/classes/DocGenController.cls` (lines 66-77)  
**Method**: `previewRecordData`

**Current code**:
```apex
@AuraEnabled(cacheable=true)
public static Map<String, Object> previewRecordData(Id recordId, String baseObject, String queryConfig) {
    if (recordId == null || String.isBlank(baseObject) || String.isBlank(queryConfig)) {
        return null;
    }
    try {
        return DocGenDataRetriever.getRecordData(recordId, baseObject, queryConfig);
    } catch (Exception e) {
        throw new DocGenException('Error fetching preview data: ' + e.getMessage());
    }
}
```

**Problem**: `baseObject` and `queryConfig` come directly from the client LWC. A malicious authenticated user could call this method directly via API with any queryable object they have access to (e.g., `User`, `Contact`, `Opportunity`), bypassing the intended query-builder UI flow.

**Fix**: Enforce an authorization gate. Create a Custom Permission `DocGen_Administrator` and require it before executing the query.

#### New Metadata

**a. Custom Permission**  
File: `force-app/main/default/customPermissions/DocGen_Administrator.customPermission-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomPermission xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Grants access to the DocGen query builder preview function and template administration.</description>
    <label>DocGen Administrator</label>
    <isLicensed>false</isLicensed>
</CustomPermission>
```

**b. Permission Set Update**  
File: `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml`  
Add:
```xml
<customPermissions>
    <enabled>true</enabled>
    <name>DocGen_Administrator</name>
</customPermissions>
```

Do **not** add the custom permission to `DocGen_User` or `DocGen_Guest_Signature`.

#### Code Change

In `DocGenController.previewRecordData`, add an early-exit authorization check:

```apex
@AuraEnabled(cacheable=true)
public static Map<String, Object> previewRecordData(Id recordId, String baseObject, String queryConfig) {
    if (recordId == null || String.isBlank(baseObject) || String.isBlank(queryConfig)) {
        return null;
    }
    
    // Security gate: previewRecordData is an admin-only query-builder feature
    if (!FeatureManagement.checkPermission('DocGen_Administrator')) {
        throw new DocGenException('Insufficient privileges: DocGen Administrator permission required.');
    }
    
    try {
        return DocGenDataRetriever.getRecordData(recordId, baseObject, queryConfig);
    } catch (Exception e) {
        throw new DocGenException('Error fetching preview data: ' + e.getMessage());
    }
}
```

**Risks**:
- Users with `DocGen_User` permission set who previously could preview data (if they had access to the query builder page) will now be blocked. However, `DocGen_User` does not grant Edit on `DocGen_Template__c`, so they could not have saved templates anyway. This is a tightening of the security boundary, not a functional regression for legitimate use cases.
- If `DocGen_Admin` permission set is not assigned to an admin user, they will be blocked. This is expected and correct.

---

## 3. EXECUTION ORDER

| Step | File(s) | Owner | Dependencies |
|------|---------|-------|------------|
| 1 | Create `DocGen_Administrator.customPermission-meta.xml` | Admin | None |
| 2 | Update `DocGen_Admin.permissionset-meta.xml` | Admin | Step 1 |
| 3 | Modify `DocGenSignatureSenderController.cls` (token) | Developer | None |
| 4 | Modify `DocGenController.cls` (Visibility + permission gate) | Developer | Steps 1-2 |
| 5 | Modify `DocGenSignatureService.cls` (Visibility + sharing) | Developer | None |
| 6 | Modify `DocGenSignatureController.cls` (sharing + helper) | Developer | Steps 4-5 |
| 7 | Modify `DocGenSignatureValidator.cls` (sharing) | Developer | Step 6 |
| 8 | Modify `DocGenSignatureSubmitter.cls` (sharing) | Developer | Step 5 |
| 9 | Modify `DocGenSignatureFinalizer.cls` (sharing) | Developer | Step 5 |
| 10 | Modify `DocGenAuthenticatorController.cls` (sharing + SYSTEM_MODE) | Developer | None |
| 11 | Update tests | Developer | Steps 1-10 |

---

## 4. TEST PLAN

### Existing tests that must still pass
All existing tests in these classes must pass after the changes:
- `DocGenTests.cls`
- `DocGenSignatureControllerTest.cls`
- `DocGenSignatureServiceTest.cls`
- `DocGenSharingTests.cls`
- `DocGenDocuSignControllerTest.cls`
- `DocGenDocuSignServiceTest.cls`

### New / Updated test requirements

1. **Token generation uniqueness** (`DocGenSignatureControllerTest.cls` or `DocGenSignatureServiceTest.cls`):
   - Generate 100 tokens in a loop and assert all are unique.
   - Assert token length is 64 characters (SHA-256 hex).

2. **`previewRecordData` permission gate** (`DocGenTests.cls`):
   - Update `testPreviewRecordData` to assign the `DocGen_Admin` permission set to the running user before calling `previewRecordData`.
   - Add a negative test `testPreviewRecordDataInsufficientPrivileges` that runs as a user WITHOUT the `DocGen_Administrator` custom permission and asserts an exception is thrown.

3. **Sharing context verification** (new test in `DocGenSignatureControllerTest.cls`):
   - Create a `DocGen_Signature_Request__c` owned by User A.
   - Run as User B (who has no sharing access to the request).
   - Call `DocGenSignatureController.validateToken` with the token.
   - Assert the method returns `isValid = false` (because the `with sharing` class respects sharing rules for the SOQL, but wait — the SOQL uses `WITH SYSTEM_MODE`...).
   
   **Correction**: Because the SOQL in `validateToken` uses `WITH SYSTEM_MODE`, sharing rules are bypassed for the query. The purpose of changing to `with sharing` is to prevent OTHER methods or future methods from accidentally exposing data. The actual `validateToken` behavior for a token-based lookup will still work for any caller who knows the token. This is the intended design (token is the security boundary, not sharing).
   
   Therefore, the sharing test should verify that `DocGenSignatureController` is `with sharing` by checking `Schema.SObjectType.DocGen_Signature_Request__c` via a reflection-style test, OR simply verify that the class still functions correctly for the guest user flow (which is the critical path).

4. **Guest user flow end-to-end** (new or updated test in `DocGenSignatureControllerTest.cls`):
   - Simulate the guest user signature flow: create a request, call `validateToken`, `stampAndReturnSource`, and `finishSignatureUpload`.
   - Assert that status updates, audit records, and ContentDocumentLinks are created successfully.
   - This validates that the inner `SystemModeHelper` correctly elevates DML.

5. **`DocGenAuthenticatorController` with restricted user** (`DocGenSignatureControllerTest.cls`):
   - Create a user with minimal permissions.
   - Run as that user.
   - Call `verifyDocument` with a valid hash.
   - Assert it returns the correct result (because the query uses `WITH SYSTEM_MODE`).

### Test data setup changes
- In `DocGenTests.cls` `@testSetup`, assign the `DocGen_Admin` permission set to the running user so `testPreviewRecordData` passes. Or do it inside `testPreviewRecordData` itself.
- For the negative privilege test, create a test user with `Standard User` profile and `DocGen_User` permission set (which does NOT contain the custom permission).

---

## 5. RISKS & MITIGATIONS

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Guest user signature flow breaks after `with sharing` change | Medium | High | Inner `SystemModeHelper` in `DocGenSignatureController` isolates elevated DML. End-to-end guest flow test validates this. |
| Flow invocables fail after `with sharing` change | Low | High | Flow runs in system context; `with sharing` does not block system-context DML. `DocGenSignatureService` is only called from Flow invocables for DML paths. |
| `previewRecordData` blocks legitimate admin users | Low | Medium | Custom permission is added to `DocGen_Admin` permission set. Any admin using the query builder already has (or should have) this permission set. Document the requirement. |
| `InternalUsers` visibility blocks external signers from viewing signed docs | Low | Medium | External signers receive the signed document via the LWC/controller response (base64 PDF or download link). They do not need direct ContentDocumentLink access. |
| Existing test failures due to custom permission not being assigned in test context | Medium | High | Update `testPreviewRecordData` to assign `DocGen_Admin` PS before calling the method. Add negative test for unprivileged user. |

---

## 6. AGENT PROMPTS

### Prompt for salesforce-admin

```
Create the following metadata on branch feature/security-p1-high. Do not deploy.

1. New Custom Permission:
   File: force-app/main/default/customPermissions/DocGen_Administrator.customPermission-meta.xml
   - Label: DocGen Administrator
   - Description: Grants access to the DocGen query builder preview function and template administration.
   - isLicensed: false

2. Update Permission Set:
   File: force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml
   - Add a <customPermissions> block enabling DocGen_Administrator.
   - Do NOT add the custom permission to DocGen_User or DocGen_Guest_Signature permission sets.

Commit both files to branch feature/security-p1-high.
```

### Prompt for salesforce-developer

```
Implement the P1 High Severity security fixes on branch feature/security-p1-high. Do not deploy.
Run all tests after changes and ensure they pass.

### Fix 1 — Predictable Token Generation
File: force-app/main/default/classes/DocGenSignatureSenderController.cls (line 28)
Replace the token generation logic:
FROM:
    Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(System.now().getTime()) + Math.random() + signerEmail));
TO:
    Blob aesKey = Crypto.generateAesKey(256);
    Blob hash = Crypto.generateDigest('SHA-256', aesKey);
Leave the rest of the method unchanged.

### Fix 2 — ContentDocumentLink Visibility = 'AllUsers'
Files:
- force-app/main/default/classes/DocGenController.cls (line 57)
- force-app/main/default/classes/DocGenSignatureService.cls (line 103)
In BOTH locations, change:
    cdl.Visibility = 'AllUsers';
TO:
    cdl.Visibility = 'InternalUsers'; // Restrict to internal users only; prevents exposure to Experience Cloud external users

### Fix 3 — 'without sharing' Exposure (6 classes)
Change ALL of the following classes from 'public without sharing' to 'public with sharing'.

A. DocGenSignatureController.cls
- Change class declaration to 'public with sharing'.
- Create a PRIVATE INNER class at the bottom of the file:
    private without sharing class SystemModeHelper {
        static void updateSignatureRequest(DocGen_Signature_Request__c req) { update req; }
        static void insertSignatureAudit(DocGen_Signature_Audit__c audit) { insert audit; }
        static void insertContentDistribution(ContentDistribution cd) { insert cd; }
        static Id saveGeneratedDocument(Id recordId, String fileName, String base64Data, String extension) {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName + (extension.startsWith('.') ? extension : '.' + extension);
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.IsMajorVersion = true;
            insert cv;
            Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE].ContentDocumentId;
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = contentDocId;
            cdl.LinkedEntityId = recordId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'InternalUsers';
            insert cdl;
            return contentDocId;
        }
    }
- In validateToken: replace 'update req;' (line ~85) with 'SystemModeHelper.updateSignatureRequest(req);'
- In validateToken: replace 'insert cd;' (line ~114) with 'SystemModeHelper.insertContentDistribution(cd);'
- In stampAndReturnSource: replace 'update req;' (line ~155) with 'SystemModeHelper.updateSignatureRequest(req);'
- In stampAndReturnSource: replace 'insert audit;' (line ~164) with 'SystemModeHelper.insertSignatureAudit(audit);'
- In finishSignatureUpload: replace the call to 'DocGenController.saveGeneratedDocument(...)' (line ~193-198) with 'SystemModeHelper.saveGeneratedDocument(...)'

B. DocGenSignatureValidator.cls
- Change class declaration to 'public with sharing'.
- No other changes needed.

C. DocGenSignatureSubmitter.cls
- Change class declaration to 'public with sharing'.
- No other changes needed.

D. DocGenSignatureFinalizer.cls
- Change class declaration to 'public with sharing'.
- No other changes needed.

E. DocGenSignatureService.cls
- Change class declaration to 'public with sharing'.
- Remove the old comment '// We use without sharing to query the Audit table securely for public users' if still present.
- Add a class-level JavaDoc comment noting: 'This class is declared with sharing. DML methods are intended to be called from Flow system context or from elevated inner helpers. Direct invocation from user context may fail if the user lacks object/field permissions.'
- No inner helper needed; all DML paths are called from Flow invocables running in system context.

F. DocGenAuthenticatorController.cls
- Change class declaration to 'public with sharing'.
- Add 'WITH SYSTEM_MODE' to the SOQL query that selects from DocGen_Signature_Audit__c.
- Remove or update the inline comment that says 'We use without sharing to query the Audit table securely for public users'.

### Fix 4 — Client-Side SOQL Trust Boundary
File: force-app/main/default/classes/DocGenController.cls (method previewRecordData, lines 66-77)
Add an authorization gate at the top of the method (after the null-check, before the try block):

    if (!FeatureManagement.checkPermission('DocGen_Administrator')) {
        throw new DocGenException('Insufficient privileges: DocGen Administrator permission required.');
    }

### Test Updates
1. In DocGenTests.cls, update testPreviewRecordData:
   - Before calling DocGenController.previewRecordData, assign the 'DocGen_Admin' PermissionSet to the running user.
   - Use a pattern like:
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'DocGen_Admin'];
        List<PermissionSetAssignment> existing = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :ps.Id];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
        }
   - Then proceed with the existing test logic.

2. In DocGenTests.cls, add a new negative test testPreviewRecordData_InsufficientPrivileges:
   - Create a test user with Standard User profile.
   - Assign ONLY the 'DocGen_User' PermissionSet (which does NOT have the custom permission).
   - Run as that user via System.runAs.
   - Call DocGenController.previewRecordData with valid params.
   - Assert that a DocGenException is thrown with message containing 'Insufficient privileges'.

3. In DocGenSignatureControllerTest.cls, add testTokenCryptographicStrength:
   - Call DocGenSignatureSenderController.createSignatureRequest 50 times in a loop.
   - Collect all generated tokens.
   - Assert all 50 tokens are unique.
   - Assert each token length is 64.

4. Ensure all existing tests still pass after the sharing changes. If any test fails due to DML or sharing, investigate whether the test is running as a user with insufficient permissions and adjust the test user setup accordingly.

Commit all changes to branch feature/security-p1-high.
```

---

## 7. IMPLEMENTATION NOTES FOR ALL AGENTS

- **Do not create or modify any other metadata** beyond what is listed in this plan.
- **Do not change `DocGenController.saveGeneratedDocument`** directly (leave it as `with sharing`). The signature flow uses the inner helper in `DocGenSignatureController` for elevated access.
- **Do not change the return type or signature** of any `@AuraEnabled` method — these are bound to LWC components.
- **Custom Permission name must be exactly** `DocGen_Administrator` (case-sensitive for `FeatureManagement.checkPermission`).
- **Token format must remain unchanged** (64-character hex string) so existing database tokens and URL patterns continue to work.
- **Visibility change**: `InternalUsers` is the correct value per Salesforce security best practices for org-internal documents. `AllUsers` should never be used for documents that contain PII or signatures.
- **API version**: All changes must remain compatible with API version 66.0.
- **Branch**: All commits must go to `feature/security-p1-high`.
