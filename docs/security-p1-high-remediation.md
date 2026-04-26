# P1 High Severity Security Fixes — Remediation Documentation

**Date:** 2026-04-26
**Status:** Completed
**Branch:** `feature/security-p1-high`

---

## Overview

**Original request:** Remediate four P1 High Severity security findings in the DocGen package: predictable token generation, overly permissive ContentDocumentLink visibility, broad `without sharing` exposure across six classes, and an unguarded client-side SOQL trust boundary.

**Summary:** All four findings were addressed through a combination of cryptographic hardening, visibility tightening, sharing-model refactoring with inner `without sharing` helpers for elevated DML, and a custom-permission authorization gate. Comprehensive test coverage was added to validate each fix and ensure no regression in the guest-user signature flow.

---

## Issues Fixed

### Issue 1 — Predictable Token Generation (HIGH)

**Finding:** `DocGenSignatureSenderController.createSignatureRequest` generated SHA-256 tokens using `Math.random()` and `System.now().getTime()` concatenated with the signer email. `Math.random()` is not cryptographically secure and the overall input had low entropy, narrowing the token space available to a determined attacker.

**Fix:** Replaced the token input with a high-entropy source:

```apex
Blob aesKey = Crypto.generateAesKey(256);
Blob hash = Crypto.generateDigest('SHA-256', aesKey);
String token = EncodingUtil.convertToHex(hash);
```

The token format remains unchanged (64-character hex-encoded SHA-256), so existing tokens in the database and URL patterns continue to work without migration.

---

### Issue 2 — ContentDocumentLink Visibility = 'AllUsers' (HIGH)

**Finding:** Two locations set `ContentDocumentLink.Visibility = 'AllUsers'`, which exposes linked documents to all users in the org, including Experience Cloud external and community users:

- `DocGenController.saveGeneratedDocument` (generated document linking)
- `DocGenSignatureService.stampSignature` (signed document linking)

**Fix:** Changed both assignments to `Visibility = 'InternalUsers'`. A comment explaining the security rationale was added at each location. External signers do not need direct ContentDocumentLink access — they receive the signed document via the LWC/controller response (base64 PDF or download link).

---

### Issue 3 — `without sharing` Exposure (HIGH)

**Finding:** Six classes were declared `public without sharing`, bypassing sharing rules entirely. Minimally-permissioned users who could invoke `@AuraEnabled` methods or Flow invocables could access or modify data they did not own or have sharing access to.

**Classes affected:**
1. `DocGenSignatureController`
2. `DocGenSignatureValidator`
3. `DocGenSignatureSubmitter`
4. `DocGenSignatureFinalizer`
5. `DocGenSignatureService`
6. `DocGenAuthenticatorController`

**Fix strategy:**
- Changed all six classes to `public with sharing`.
- SOQL queries that already used `WITH SYSTEM_MODE` required no query changes.
- For DML that must run in an elevated context (guest user signature flow), a **private inner `without sharing` helper** was created inside `DocGenSignatureController` only.

**Inner helper:** `DocGenSignatureController.SystemModeHelper`

```apex
private without sharing class SystemModeHelper {
    static void updateSignatureRequest(DocGen_Signature_Request__c req) { update req; }
    static void insertSignatureAudit(DocGen_Signature_Audit__c audit) { insert audit; }
    static void updateSignatureAudit(List<DocGen_Signature_Audit__c> audits) { update audits; }
    static void insertContentDistribution(ContentDistribution cd) { insert cd; }
    static Id saveGeneratedDocument(Id recordId, String fileName, String base64Data, String extension) { ... }
}
```

Methods refactored to use the helper:
- `validateToken` — `update req` and `insert cd`
- `stampAndReturnSource` — `update req` and `insert audit`
- `finishSignatureUpload` — `saveGeneratedDocument`

The other five classes delegate to these methods or run inside Flow system context, so no additional helpers were needed. `DocGenSignatureService` carries a class-level JavaDoc warning that DML methods are intended to be called from Flow system context or elevated inner helpers, and direct user-context invocation may fail if the user lacks object/field permissions.

`DocGenAuthenticatorController.verifyDocument` was also updated to add `WITH SYSTEM_MODE` to its SOQL query so the read-only verification path continues to work for all callers.

---

### Issue 4 — Client-Side SOQL Trust Boundary (HIGH)

**Finding:** `DocGenController.previewRecordData` accepted `baseObject` and `queryConfig` directly from the client LWC. A malicious authenticated user could call this `@AuraEnabled(cacheable=true)` method via API with any queryable object they had access to, bypassing the intended query-builder UI flow.

**Fix:** Enforced an authorization gate using a new Custom Permission.

**New metadata:**
- **Custom Permission:** `DocGen_Administrator`
  - Label: DocGen Administrator
  - Description: Grants access to the DocGen query builder preview function and template administration.
- **Permission Set update:** `DocGen_Admin.permissionset-meta.xml` now enables `DocGen_Administrator`.

The custom permission was **not** added to `DocGen_User` or `DocGen_Guest_Signature`.

**Code change:**

```apex
if (!FeatureManagement.checkPermission('DocGen_Administrator')) {
    throw new DocGenException('Insufficient privileges: DocGen Administrator permission required.');
}
```

This is inserted as an early-exit check inside `previewRecordData` after null validation and before any query execution.

---

## Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `force-app/main/default/classes/DocGenSignatureSenderController.cls` | Modified | Token generation hardened using `Crypto.generateAesKey(256)`. |
| `force-app/main/default/classes/DocGenController.cls` | Modified | `saveGeneratedDocument` visibility changed to `InternalUsers`; `previewRecordData` gated with `FeatureManagement.checkPermission('DocGen_Administrator')`. |
| `force-app/main/default/classes/DocGenSignatureService.cls` | Modified | `stampSignature` visibility changed to `InternalUsers`; class changed to `public with sharing`; added class-level JavaDoc warning. |
| `force-app/main/default/classes/DocGenSignatureController.cls` | Modified | Class changed to `public with sharing`; added inner `SystemModeHelper` to elevate DML; refactored `validateToken`, `stampAndReturnSource`, and `finishSignatureUpload` to use helper. |
| `force-app/main/default/classes/DocGenSignatureValidator.cls` | Modified | Class changed to `public with sharing`. |
| `force-app/main/default/classes/DocGenSignatureSubmitter.cls` | Modified | Class changed to `public with sharing`. |
| `force-app/main/default/classes/DocGenSignatureFinalizer.cls` | Modified | Class changed to `public with sharing`. |
| `force-app/main/default/classes/DocGenAuthenticatorController.cls` | Modified | Class changed to `public with sharing`; SOQL query added `WITH SYSTEM_MODE`. |
| `force-app/main/default/classes/DocGenTests.cls` | Modified | Updated `testPreviewRecordData` to assign `DocGen_Admin` PS; added `testPreviewRecordData_InsufficientPrivileges`; existing tests verify `InternalUsers` visibility. |
| `force-app/main/default/classes/DocGenSignatureControllerTest.cls` | Modified | Added `testTokenCryptographicStrength` (50 unique 64-char tokens); existing tests continue to validate end-to-end guest flow and helper DML. |
| `force-app/main/default/classes/DocGenSignatureServiceTest.cls` | Modified | Existing tests verify `InternalUsers` visibility on generated links. |
| `force-app/main/default/customPermissions/DocGen_Administrator.customPermission-meta.xml` | **Created** | New custom permission for query-builder preview access. |
| `force-app/main/default/permissionsets/DocGen_Admin.permissionset-meta.xml` | Modified | Added `<customPermissions>` block enabling `DocGen_Administrator`. |

---

## Test Coverage Added / Updated

| Test Class | Test Method | Purpose |
|------------|-------------|---------|
| `DocGenSignatureControllerTest` | `testTokenCryptographicStrength` | Generates 50 tokens via `createSignatureRequest`, asserts all are unique and each is exactly 64 hex characters. |
| `DocGenTests` | `testPreviewRecordData` (updated) | Assigns `DocGen_Admin` permission set to running user before calling `previewRecordData` to satisfy the new authorization gate. |
| `DocGenTests` | `testPreviewRecordData_InsufficientPrivileges` | Creates a `Standard User` with only `DocGen_User` permission set, runs via `System.runAs`, and asserts a `DocGenException` containing "Insufficient privileges" is thrown. |
| `DocGenTests` | `testSaveGeneratedDocument` (existing) | Asserts that saved document links have `Visibility = 'InternalUsers'`. |
| `DocGenSignatureControllerTest` | `testFinishSignatureUpload` (existing) | Asserts uploaded PDF links have `Visibility = 'InternalUsers'`. |
| `DocGenSignatureServiceTest` | `testStampSignature` (existing) | Asserts signed document links have `Visibility = 'InternalUsers'`. |
| `DocGenSignatureServiceTest` | `testHandleSignatureSubmission` (existing) | Asserts generated signed document links have `Visibility = 'InternalUsers'`. |
| `DocGenSignatureControllerTest` | `testValidateTokenValidSent`, `testStampAndReturnSource`, `testFinishSignatureUpload`, `testFinalizeSignature` (existing) | Validate that the guest-user signature flow continues to work after the `with sharing` + inner-helper refactor. |
| `DocGenSignatureControllerTest` | `testVerifyDocumentValidHash` / `testVerifyDocumentInvalidHash` (existing) | Validate that document verification works after the `with sharing` + `WITH SYSTEM_MODE` changes. |

All existing tests in the following classes continue to pass:
- `DocGenTests.cls`
- `DocGenSignatureControllerTest.cls`
- `DocGenSignatureServiceTest.cls`
- `DocGenSharingTests.cls`
- `DocGenDocuSignControllerTest.cls`
- `DocGenDocuSignServiceTest.cls`

---

## Breaking Changes & Migration Notes

### 1. ContentDocumentLink Visibility Tightening
Documents generated by `DocGenController.saveGeneratedDocument` and signed documents created by `DocGenSignatureService.stampSignature` are now linked with `Visibility = 'InternalUsers'` instead of `'AllUsers'`.

**Impact:** External/community users who previously accessed these documents directly via the ContentDocumentLink (outside the DocGen LWC/controller flow) will lose access.

**Mitigation:** No migration needed for the intended flow. External signers receive documents through the LWC response or generated download links. Internal users retain full access.

### 2. `previewRecordData` Authorization Gate
Users calling `DocGenController.previewRecordData` must now hold the `DocGen_Administrator` custom permission.

**Impact:** Any user with `DocGen_User` (but not `DocGen_Admin`) who previously accessed the query-builder preview will now receive an `Insufficient privileges` error.

**Mitigation:** Assign the `DocGen_Admin` permission set (which now includes the custom permission) to users who need query-builder preview access. The `DocGen_Admin` permission set is the intended vehicle for administrative access.

### 3. `with sharing` Refactor
No breaking changes for the supported use cases:
- **Guest user signature flow:** Continues to work because DML inside `DocGenSignatureController` is elevated through the inner `SystemModeHelper`.
- **Flow invocables (`DocGenSignatureSubmitter`, `DocGenSignatureFinalizer`, `DocGenSignatureValidator`):** Continue to work because Flow runs in system context, which carries through `with sharing` classes.
- **Direct `DocGenSignatureService` DML from user context:** If any custom code directly calls `DocGenSignatureService.stampSignature` or `handleSignatureSubmission` from a non-system user context, the DML may now fail due to object/field permissions. This is the intended security boundary. If elevation is required, wrap the call in a `without sharing` helper or invoke it from Flow.

### 4. Token Format Unchanged
Existing `Secure_Token__c` values in the database remain valid. No data migration is required.

---

## Security Model Summary

- **Sharing:** All signature classes now enforce `with sharing`. Only the private inner `SystemModeHelper` inside `DocGenSignatureController` bypasses sharing, and it is used exclusively for DML required by the guest signature flow.
- **SOQL mode:** Queries that must return data regardless of the caller's sharing (token-based lookups, audit verification) use `WITH SYSTEM_MODE`. General user-facing queries use `WITH USER_MODE`.
- **Authorization:** The query-builder preview is gated by the `DocGen_Administrator` custom permission, enforced at the Apex method entry point via `FeatureManagement.checkPermission`.
- **Document visibility:** Generated and signed documents are restricted to internal users only via `ContentDocumentLink.Visibility = 'InternalUsers'`.

---

## Known Limitations & Future Enhancements

- `DocGenSignatureService` DML paths rely on being called from Flow system context. If future requirements introduce direct user-context invocation of these methods, an inner helper (similar to `DocGenSignatureController.SystemModeHelper`) will need to be added.
- The token generation fix addresses predictability but does not implement token expiration. If token expiration is required as a future enhancement, a `Token_Expires_At__c` field and scheduled job would be needed.
- `DocGenAuthenticatorController.verifyDocument` remains read-only and uses `WITH SYSTEM_MODE`. Any future write operations in this class should be reviewed for sharing implications.

---

## Change History

| Date | Commit | Change |
|------|--------|--------|
| 2026-04-26 | `34b79f7` | Created `DocGen_Administrator` custom permission; added to `DocGen_Admin` permission set. |
| 2026-04-26 | `7b61ec0` | Applied all four P1 security fixes (token generation, visibility, sharing, permission gate). |
| 2026-04-26 | `5c63665` | Added and updated test coverage for all P1 fixes. |
| 2026-04-26 | `6ac3c92` | Code review follow-up: consolidated DML helpers, fixed annotation casing, removed stale comments. |
