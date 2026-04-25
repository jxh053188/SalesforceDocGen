@isTest
private class DocGenSignatureControllerTest {

    @TestSetup
    static void setup() {
        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>Test {#Signature}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'SignSource',
            PathOnClient = 'SignSource.docx',
            VersionData = docxBlob,
            IsMajorVersion = true
        );
        insert cv;
    }

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

    @isTest
    static void testValidateTokenBlank() {
        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.validateToken('');
        Test.stopTest();
        System.assertEquals(false, res.isValid, 'Should be invalid for blank token');
        System.assert(res.errorMessage.contains('Invalid or missing'), 'Error should mention invalid token');
    }

    @isTest
    static void testValidateTokenInvalid() {
        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.validateToken('nonexistent');
        Test.stopTest();
        System.assertEquals(false, res.isValid, 'Should be invalid for nonexistent token');
        System.assert(res.errorMessage.contains('not found'), 'Error should mention not found');
    }

    @isTest
    static void testValidateTokenAlreadySigned() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-signed',
            Status__c = 'Signed'
        );
        insert req;

        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.validateToken('tok-signed');
        Test.stopTest();
        System.assertEquals(false, res.isValid, 'Should be invalid for already signed');
        System.assert(res.errorMessage.contains('already been signed'), 'Error should mention already signed');
    }

    @isTest
    static void testValidateTokenCancelled() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-cancelled',
            Status__c = 'Cancelled'
        );
        insert req;

        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.validateToken('tok-cancelled');
        Test.stopTest();
        System.assertEquals(false, res.isValid, 'Should be invalid for cancelled');
        System.assert(res.errorMessage.contains('cancelled'), 'Error should mention cancelled');
    }

    @isTest
    static void testValidateTokenValidSent() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John Doe',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-sent',
            Status__c = 'Sent'
        );
        insert req;

        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.validateToken('tok-sent');
        Test.stopTest();
        System.assertEquals(true, res.isValid, 'Should be valid');
        System.assertEquals('John Doe', res.signerName, 'Signer name should match');

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Viewed', updatedReq.Status__c, 'Status should be updated to Viewed');
    }

    @isTest
    static void testFetchDocumentData() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-fetch',
            Status__c = 'Sent'
        );
        insert req;

        Test.startTest();
        DocGenSignatureController.SignatureInitResponse res = DocGenSignatureController.fetchDocumentData('tok-fetch');
        Test.stopTest();
        System.assertEquals(true, res.isValid, 'Should be valid');
        System.assertNotEquals(null, res.templateBase64, 'Should return base64 content');
    }

    @isTest
    static void testStampAndReturnSource() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-stamp',
            Status__c = 'Sent'
        );
        insert req;

        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        Test.startTest();
        Map<String, String> result = DocGenSignatureController.stampAndReturnSource('tok-stamp', fakeBase64);
        Test.stopTest();

        System.assertNotEquals(null, result.get('base64'), 'Should return base64');
        System.assert(result.get('title').contains('Signed'), 'Title should contain Signed');

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Signed', updatedReq.Status__c, 'Should be Signed');

        List<DocGen_Signature_Audit__c> audits = [SELECT Id FROM DocGen_Signature_Audit__c WHERE Signature_Request__c = :req.Id];
        System.assertEquals(1, audits.size(), 'Audit should be created');
    }

    @isTest
    static void testFinishSignatureUpload() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Related_Record_Id__c = acc.Id,
            Secure_Token__c = 'tok-finish',
            Status__c = 'Signed'
        );
        insert req;

        DocGen_Signature_Audit__c audit = new DocGen_Signature_Audit__c(
            Signature_Request__c = req.Id,
            Signed_Date__c = System.now(),
            Document_Hash_SHA256__c = 'PENDING_CLIENT_PDF'
        );
        insert audit;

        String fakePdfBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakePdfContent'));

        Test.startTest();
        DocGenSignatureController.finishSignatureUpload('tok-finish', fakePdfBase64, 'SignedDoc.pdf');
        Test.stopTest();

        DocGen_Signature_Audit__c updatedAudit = [SELECT Document_Hash_SHA256__c FROM DocGen_Signature_Audit__c WHERE Id = :audit.Id];
        System.assertNotEquals('PENDING_CLIENT_PDF', updatedAudit.Document_Hash_SHA256__c, 'Hash should be updated');
    }

    @isTest
    static void testFinalizeSignature() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-finalize',
            Status__c = 'Sent'
        );
        insert req;

        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        DocGenSignatureFinalizer.FinalizeRequest finReq = new DocGenSignatureFinalizer.FinalizeRequest();
        finReq.token = 'tok-finalize';
        finReq.base64Image = fakeBase64;

        Test.startTest();
        DocGenSignatureFinalizer.finalizeSignature(new List<DocGenSignatureFinalizer.FinalizeRequest>{finReq});
        Test.stopTest();

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Signed', updatedReq.Status__c, 'Should be Signed after finalizer');
    }

    @isTest
    static void testGetRelatedDocuments() {
        Account acc = new Account(Name = 'Doc Acc');
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title = 'RelatedDoc',
            PathOnClient = 'RelatedDoc.docx',
            VersionData = Blob.valueOf('content'),
            IsMajorVersion = true
        );
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = acc.Id,
            ContentDocumentId = cdId,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<ContentVersion> docs = DocGenSignatureSenderController.getRelatedDocuments(acc.Id);
        Test.stopTest();

        System.assertEquals(1, docs.size(), 'Should find 1 related doc');
    }

    @isTest
    static void testCreateSignatureRequest() {
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        Test.startTest();
        String url = DocGenSignatureSenderController.createSignatureRequest(cv.ContentDocumentId, acc.Id, 'John Doe', 'john@example.com');
        Test.stopTest();

        System.assert(url.contains('token='), 'URL should contain token parameter');

        List<DocGen_Signature_Request__c> reqs = [SELECT Id, Status__c, Signer_Name__c FROM DocGen_Signature_Request__c];
        System.assertEquals(1, reqs.size(), 'Request should be created');
        System.assertEquals('Sent', reqs[0].Status__c, 'Status should be Sent');
    }

    @isTest
    static void testSubmitSignature() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-submit',
            Status__c = 'Sent'
        );
        insert req;

        DocGenSignatureSubmitter.FlowInput input = new DocGenSignatureSubmitter.FlowInput();
        input.token = 'tok-submit';
        input.signatureData = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        Test.startTest();
        List<DocGenSignatureSubmitter.FlowOutput> results = DocGenSignatureSubmitter.submitSignature(new List<DocGenSignatureSubmitter.FlowInput>{input});
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 result');
        System.assertEquals(true, results[0].isSuccess, 'Should be successful');
    }

    @isTest
    static void testValidateTokenViaFlow() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-flow',
            Status__c = 'Sent'
        );
        insert req;

        DocGenSignatureValidator.FlowInput input = new DocGenSignatureValidator.FlowInput();
        input.token = 'tok-flow';

        Test.startTest();
        List<DocGenSignatureValidator.FlowOutput> results = DocGenSignatureValidator.validateToken(new List<DocGenSignatureValidator.FlowInput>{input});
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 result');
        System.assertEquals(true, results[0].isValid, 'Should be valid');
        System.assertEquals('John', results[0].signerName, 'Signer name should match');
    }

    @isTest
    static void testVerifyDocumentValidHash() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SignSource' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'Alice',
            Signer_Email__c = 'alice@example.com',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'tok-auth',
            Status__c = 'Signed'
        );
        insert req;

        DocGen_Signature_Audit__c audit = new DocGen_Signature_Audit__c(
            Signature_Request__c = req.Id,
            Signed_Date__c = System.now(),
            Document_Hash_SHA256__c = 'abc123hash',
            IP_Address__c = '127.0.0.1'
        );
        insert audit;

        Test.startTest();
        DocGenAuthenticatorController.VerificationResult res = DocGenAuthenticatorController.verifyDocument('abc123hash');
        Test.stopTest();

        System.assertEquals(true, res.isValid, 'Should be valid');
        System.assertEquals('Alice', res.signerName, 'Signer name should match');
        System.assertEquals('alice@example.com', res.signerEmail, 'Signer email should match');
    }

    @isTest
    static void testVerifyDocumentInvalidHash() {
        Test.startTest();
        DocGenAuthenticatorController.VerificationResult res = DocGenAuthenticatorController.verifyDocument('nonexistenthash');
        Test.stopTest();

        System.assertEquals(false, res.isValid, 'Should be invalid');
        System.assert(res.message.contains('Not Found'), 'Message should mention not found');
    }
}
