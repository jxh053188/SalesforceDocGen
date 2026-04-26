@isTest
private class DocGenFlowActionTest {

    @TestSetup
    static void setup() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Test Template',
            Base_Object_API__c = 'Account',
            Query_Config__c = 'Name',
            Type__c = 'Word'
        );
        insert tpl;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{Name}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'FlowTemplate',
            PathOnClient = 'FlowTemplate.docx',
            VersionData = docxBlob,
            IsMajorVersion = true
        );
        insert cv;
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = tpl.Id,
            ContentDocumentId = conDocId,
            ShareType = 'V'
        );
        insert cdl;
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
    static void testExecute_WithSingleRecipient() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Contact con = new Contact(FirstName = 'Test', LastName = 'Signer', Email = 'signer@example.com', AccountId = acc.Id);
        insert con;

        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = tpl.Id;
        req.recordId = acc.Id;
        req.sendForSignature = true;
        req.recipientContactId = con.Id;
        req.emailSubject = 'Please sign this';

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].contentDocumentId, 'Should return contentDocumentId');
        System.assertNotEquals(null, responses[0].envelopeId, 'Should return envelopeId');
        System.assertEquals(null, responses[0].errorMessage, 'Should have no error');
    }

    @isTest
    static void testExecute_WithMultipleRecipients() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Contact con1 = new Contact(FirstName = 'Test1', LastName = 'Signer1', Email = 'signer1@example.com', AccountId = acc.Id);
        Contact con2 = new Contact(FirstName = 'Test2', LastName = 'Signer2', Email = 'signer2@example.com', AccountId = acc.Id);
        insert new List<Contact>{ con1, con2 };

        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = tpl.Id;
        req.recordId = acc.Id;
        req.sendForSignature = true;
        req.recipientContactIds = con1.Id + ', ' + con2.Id;
        req.emailSubject = 'Please sign this';

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].contentDocumentId, 'Should return contentDocumentId');
        System.assertNotEquals(null, responses[0].envelopeId, 'Should return envelopeId');
        System.assertEquals(null, responses[0].errorMessage, 'Should have no error');
    }

    @isTest
    static void testExecute_WithMultipleRecipientsAndSignature() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Contact con1 = new Contact(FirstName = 'Alice', LastName = 'Signer', Email = 'alice@example.com', AccountId = acc.Id);
        Contact con2 = new Contact(FirstName = 'Bob', LastName = 'Signer', Email = 'bob@example.com', AccountId = acc.Id);
        insert new List<Contact>{ con1, con2 };

        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = tpl.Id;
        req.recordId = acc.Id;
        req.sendForSignature = true;
        req.recipientContactIds = con1.Id + ',' + con2.Id;
        req.emailSubject = 'Multi-recipient signature request';

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].contentDocumentId, 'Should return contentDocumentId');
        System.assertNotEquals(null, responses[0].envelopeId, 'Should return envelopeId');
        System.assertEquals(null, responses[0].errorMessage, 'Should have no error');
    }
}
