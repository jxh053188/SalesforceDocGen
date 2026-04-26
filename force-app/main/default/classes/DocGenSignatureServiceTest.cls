@isTest
private class DocGenSignatureServiceTest {

    @TestSetup
    static void setup() {
        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>Test Document {#Signature}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'SourceDoc',
            PathOnClient = 'SourceDoc.docx',
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
    static void testStampSignatureToBlob() {
        ContentVersion cv = [SELECT Id, VersionData FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        Test.startTest();
        Blob result = DocGenSignatureService.stampSignatureToBlob(cv.Id, fakeBase64, 'REQ-001');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result blob should not be null');
        System.assert(result.size() > cv.VersionData.size(), 'Stamped doc should be larger than original');
    }

    @isTest
    static void testStampSignature() {
        ContentVersion cv = [SELECT Id, Title FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        Test.startTest();
        Id newCvId = DocGenSignatureService.stampSignature(cv.Id, fakeBase64, 'REQ-001', acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, newCvId, 'Should return new ContentVersion Id');
        ContentVersion newCv = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id = :newCvId];
        System.assert(newCv.Title.contains('Signed'), 'Title should contain Signed');

        List<ContentDocumentLink> links = [SELECT Id, Visibility FROM ContentDocumentLink WHERE LinkedEntityId = :acc.Id];
        System.assertEquals(1, links.size(), 'Should be linked to account');
        System.assertEquals('InternalUsers', links[0].Visibility, 'Visibility should be restricted to InternalUsers');
    }

    @isTest
    static void testHandleSignatureSubmission() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John Doe',
            Signer_Email__c = 'john@example.com',
            Source_Document_Id__c = cv.Id,
            Related_Record_Id__c = acc.Id,
            Secure_Token__c = 'test-token-123',
            Status__c = 'Sent'
        );
        insert req;

        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        Test.startTest();
        DocGenSignatureService.handleSignatureSubmission('test-token-123', fakeBase64);
        Test.stopTest();

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Signed', updatedReq.Status__c, 'Request should be signed');

        List<DocGen_Signature_Audit__c> audits = [SELECT Id, Document_Hash_SHA256__c FROM DocGen_Signature_Audit__c WHERE Signature_Request__c = :req.Id];
        System.assertEquals(1, audits.size(), 'Audit should be created');
        System.assertNotEquals(null, audits[0].Document_Hash_SHA256__c, 'Hash should be populated');

        Id signedDocId = Id.valueOf(audits[0].Document_Hash_SHA256__c);
        List<ContentDocumentLink> links = [SELECT Id, Visibility FROM ContentDocumentLink WHERE ContentDocumentId = :signedDocId AND LinkedEntityId = :acc.Id];
        System.assertEquals(1, links.size(), 'Document should be linked to account');
        System.assertEquals('InternalUsers', links[0].Visibility, 'Visibility should be restricted to InternalUsers');
    }

    @isTest
    static void testHandleSignatureSubmissionAlreadySigned() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John Doe',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'test-token-signed',
            Status__c = 'Signed'
        );
        insert req;

        Test.startTest();
        DocGenSignatureService.handleSignatureSubmission('test-token-signed', 'fakeBase64');
        Test.stopTest();

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Signed', updatedReq.Status__c, 'Status should remain Signed');
    }

    @isTest
    static void testHandleSignatureSubmissionCancelled() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
        DocGen_Signature_Request__c req = new DocGen_Signature_Request__c(
            Signer_Name__c = 'John Doe',
            Source_Document_Id__c = cv.Id,
            Secure_Token__c = 'test-token-cancelled',
            Status__c = 'Cancelled'
        );
        insert req;

        Test.startTest();
        DocGenSignatureService.handleSignatureSubmission('test-token-cancelled', 'fakeBase64');
        Test.stopTest();

        DocGen_Signature_Request__c updatedReq = [SELECT Status__c FROM DocGen_Signature_Request__c WHERE Id = :req.Id];
        System.assertEquals('Cancelled', updatedReq.Status__c, 'Status should remain Cancelled');
    }

    @isTest
    static void testHandleSignatureSubmissionInvalidToken() {
        Test.startTest();
        DocGenSignatureService.handleSignatureSubmission('nonexistent-token', 'fakeBase64');
        Test.stopTest();

        System.assert(true, 'Method should complete without error for invalid token');
    }

    @isTest
    static void testStampSignatureToBlobNoSignaturePlaceholder() {
        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>Test Document</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'NoPlaceholder',
            PathOnClient = 'NoPlaceholder.docx',
            VersionData = docxBlob,
            IsMajorVersion = true
        );
        insert cv;

        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fakeImage'));

        Test.startTest();
        Blob result = DocGenSignatureService.stampSignatureToBlob(cv.Id, fakeBase64, 'REQ-002');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result blob should not be null');
    }

    @isTest
    static void testSubmitSignature() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'SourceDoc' LIMIT 1];
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
}
