@isTest
private class DocGenTests {

    @testSetup
    static void setup() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Test Template',
            Base_Object_API__c = 'Account',
            Query_Config__c = 'Name, AccountSource',
            Type__c = 'Word'
        );
        insert tpl;

        Account acc = new Account(Name = 'Test Account', AccountSource = 'Web', Website = 'https://www.example.com');
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.docx',
            VersionData = Blob.valueOf('Test Content'),
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
    static void testGenerationFlow() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> result = DocGenController.generateDocumentData(tpl.Id, acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.get('data'), 'Data should not be null');
        System.assertNotEquals(null, result.get('templateFile'), 'File should not be null');
        Map<String, Object> data = (Map<String, Object>) result.get('data');
        System.assertEquals('Test Account', data.get('Name'));
    }

    @isTest
    static void testGetTemplates() {
        List<DocGen_Template__c> tpls = DocGenController.getTemplatesForObject('Account');
        System.assertEquals(1, tpls.size());
    }

    @isTest
    static void testVersioning() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        ContentVersion cv1 = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];

        DocGen_Template_Version__c v1 = new DocGen_Template_Version__c(
            Template__c = tpl.Id,
            Content_Version_Id__c = cv1.Id,
            Is_Active__c = true,
            Type__c = 'Word',
            Base_Object_API__c = 'Account',
            Category__c = 'General',
            Description__c = 'V1 Description'
        );
        insert v1;

        ContentVersion cv2 = new ContentVersion(
            Title = 'TestDoc_V2',
            PathOnClient = 'TestDoc_V2.docx',
            VersionData = Blob.valueOf('V2 Content')
        );
        insert cv2;

        Id conDocId2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id].ContentDocumentId;
        ContentDocumentLink cdl2 = new ContentDocumentLink(
            LinkedEntityId = tpl.Id,
            ContentDocumentId = conDocId2,
            ShareType = 'V'
        );
        insert cdl2;

        DocGen_Template_Version__c v2 = new DocGen_Template_Version__c(
            Template__c = tpl.Id,
            Content_Version_Id__c = cv2.Id,
            Is_Active__c = true,
            Type__c = 'Word',
            Base_Object_API__c = 'Account',
            Category__c = 'General',
            Description__c = 'V2 Description'
        );
        insert v2;

        v1.Is_Active__c = false;
        update v1;

        Test.startTest();
        String contentV2 = DocGenTemplateManager.getTemplateFileContent(tpl.Id);
        System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('V2 Content')), contentV2, 'Should return V2 content');

        DocGenController.activateVersion(v1.Id);

        String contentV1 = DocGenTemplateManager.getTemplateFileContent(tpl.Id);
        System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('Test Content')), contentV1, 'Should return V1 content');
        Test.stopTest();
    }

    @isTest
    static void testGenerateDocumentDataReturnsHtmlTemplateType() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        tpl.Type__c = 'HTML';
        update tpl;
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        Map<String, Object> result = DocGenController.generateDocumentData(tpl.Id, acc.Id);
        Test.stopTest();
        System.assertEquals('HTML', result.get('templateType'), 'templateType should be HTML');
        System.assertNotEquals(null, result.get('templateFile'), 'Template file should be returned');
    }

    @isTest
    static void testDocGenServiceThrowsForHtmlTemplate() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        tpl.Type__c = 'HTML';
        update tpl;
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenService.generateDocument(tpl.Id, acc.Id);
        } catch (DocGenException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();
        System.assert(threw, 'DocGenService should throw for HTML template in bulk/server context');
        System.assert(message.contains('HTML templates are only supported'), 'Exception should mention HTML single-record only');
    }

    @isTest
    static void testGenerateDocumentWord() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{Name}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'WordTemplate',
            PathOnClient = 'WordTemplate.docx',
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

        Test.startTest();
        Id resultDocId = DocGenService.generateDocument(tpl.Id, acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, resultDocId, 'Should return a ContentDocumentId');
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :acc.Id AND ContentDocumentId = :resultDocId];
        System.assertEquals(1, links.size(), 'Generated document should be linked to the account');
    }

    @isTest
    static void testGenerateDocumentNullTemplate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Boolean threw = false;
        Test.startTest();
        try {
            DocGenService.generateDocument(null, acc.Id);
        } catch (DocGenException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null templateId');
    }

    @isTest
    static void testSaveGeneratedDocument() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('Hello World'));

        Test.startTest();
        Id docId = DocGenController.saveGeneratedDocument(acc.Id, 'TestFile', base64, 'docx');
        Test.stopTest();

        System.assertNotEquals(null, docId, 'Should return ContentDocumentId');
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :acc.Id AND ContentDocumentId = :docId];
        System.assertEquals(1, links.size(), 'Document should be linked to account');
    }

    @isTest
    static void testPreviewRecordData() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> data = DocGenController.previewRecordData(acc.Id, 'Account', 'Id, Name');
        Test.stopTest();

        System.assertNotEquals(null, data, 'Data should not be null');
        System.assertEquals('Test Account', data.get('Name'), 'Name should match');
    }

    @isTest
    static void testPreviewRecordDataNullParams() {
        Test.startTest();
        Map<String, Object> data = DocGenController.previewRecordData(null, 'Account', 'Id, Name');
        Test.stopTest();
        System.assertEquals(null, data, 'Should return null for invalid params');
    }

    @isTest
    static void testGetAllTemplates() {
        Test.startTest();
        List<DocGen_Template__c> tpls = DocGenController.getAllTemplates();
        Test.stopTest();
        System.assertEquals(1, tpls.size(), 'Should return 1 template');
    }

    @isTest
    static void testSaveTemplate() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];

        Map<String, Object> fields = new Map<String, Object>{
            'Id' => tpl.Id,
            'Name' => 'Updated Name',
            'Category__c' => 'Updated Category',
            'Type__c' => 'Word',
            'Base_Object_API__c' => 'Contact',
            'Description__c' => 'Updated Desc',
            'Query_Config__c' => 'Name',
            'Query_Metadata__c' => '{}',
            'Test_Record_Id__c' => '',
            'Document_Title_Format__c' => '{Name}'
        };

        Test.startTest();
        DocGenController.saveTemplate(fields, false);
        Test.stopTest();

        DocGen_Template__c updated = [SELECT Name, Base_Object_API__c FROM DocGen_Template__c WHERE Id = :tpl.Id];
        System.assertEquals('Updated Name', updated.Name, 'Name should be updated');
        System.assertEquals('Contact', updated.Base_Object_API__c, 'Base object should be updated');
    }

    @isTest
    static void testDeleteTemplate() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];

        Test.startTest();
        DocGenController.deleteTemplate(tpl.Id);
        Test.stopTest();

        List<DocGen_Template__c> remaining = [SELECT Id FROM DocGen_Template__c WHERE Id = :tpl.Id];
        System.assertEquals(0, remaining.size(), 'Template should be deleted');
    }

    @isTest
    static void testGetTemplateVersions() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];

        DocGen_Template_Version__c v1 = new DocGen_Template_Version__c(
            Template__c = tpl.Id,
            Is_Active__c = true,
            Type__c = 'Word',
            Base_Object_API__c = 'Account'
        );
        insert v1;

        Test.startTest();
        List<DocGen_Template_Version__c> versions = DocGenController.getTemplateVersions(tpl.Id);
        Test.stopTest();

        System.assertEquals(1, versions.size(), 'Should return 1 version');
    }

    @isTest
    static void testSaveTempHtml() {
        Test.startTest();
        String docId = DocGenController.saveTempHtml('<html><body>Test</body></html>', 'TempHtml');
        Test.stopTest();

        System.assertNotEquals(null, docId, 'Should return ContentDocumentId');
    }

    @isTest
    static void testGetObjectOptions() {
        Test.startTest();
        List<Map<String, String>> options = DocGenController.getObjectOptions();
        Test.stopTest();

        System.assert(options.size() > 0, 'Should return object options');
        Boolean foundAccount = false;
        for (Map<String, String> opt : options) {
            if (opt.get('value') == 'Account') foundAccount = true;
        }
        System.assert(foundAccount, 'Should include Account object');
    }

    @isTest
    static void testGetObjectFields() {
        Test.startTest();
        List<Map<String, String>> fields = DocGenController.getObjectFields('Account');
        Test.stopTest();

        System.assert(fields.size() > 0, 'Should return fields for Account');
        Boolean foundName = false;
        for (Map<String, String> f : fields) {
            if (f.get('value') == 'Name') foundName = true;
        }
        System.assert(foundName, 'Should include Name field');
    }

    @isTest
    static void testGetChildRelationships() {
        Test.startTest();
        List<Map<String, String>> rels = DocGenController.getChildRelationships('Account');
        Test.stopTest();

        System.assert(rels.size() > 0, 'Should return child relationships for Account');
    }

    @isTest
    static void testGetParentRelationships() {
        Test.startTest();
        List<Map<String, String>> parents = DocGenController.getParentRelationships('Account');
        Test.stopTest();

        System.assert(parents.size() > 0, 'Should return parent relationships for Account');
    }

    @isTest
    static void testGetObjectFieldsInvalidObject() {
        Test.startTest();
        List<Map<String, String>> fields = DocGenController.getObjectFields('NonExistentObject__c');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Should return empty list for invalid object');
    }

    @isTest
    static void testGetRecordData() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> data = DocGenDataRetriever.getRecordData(acc.Id, 'Account', 'Id, Name, AccountSource');
        Test.stopTest();

        System.assertNotEquals(null, data, 'Data should not be null');
        System.assertEquals('Test Account', data.get('Name'), 'Name should match');
        System.assertEquals('Web', data.get('AccountSource'), 'AccountSource should match');
    }

    @isTest
    static void testGetRecordDataInvalidParams() {
        Boolean threw = false;
        Test.startTest();
        try {
            DocGenDataRetriever.getRecordData(null, 'Account', 'Id');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null recordId');
    }

    @isTest
    static void testGetRecordDataNoResults() {
        Test.startTest();
        Map<String, Object> data = DocGenDataRetriever.getRecordData(UserInfo.getUserId(), 'Account', 'Id');
        Test.stopTest();
        System.assertEquals(null, data, 'Should return null when no records found');
    }

    @isTest
    static void testGetTemplateFileContentFallback() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Fallback Template',
            Base_Object_API__c = 'Account',
            Type__c = 'Word'
        );
        insert tpl;

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>Fallback</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'FallbackDoc',
            PathOnClient = 'FallbackDoc.docx',
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

        Test.startTest();
        String content = DocGenTemplateManager.getTemplateFileContent(tpl.Id);
        Test.stopTest();

        System.assertNotEquals(null, content, 'Should return base64 content via fallback');
    }

    @isTest
    static void testGetTemplateFileContentMissing() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Missing Template',
            Base_Object_API__c = 'Account',
            Type__c = 'Word'
        );
        insert tpl;

        Boolean threw = false;
        Test.startTest();
        try {
            DocGenTemplateManager.getTemplateFileContent(tpl.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw when no template file exists');
    }

    @isTest
    static void testFlowActionGenerateDocument() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

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

        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = tpl.Id;
        req.recordId = acc.Id;

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].contentDocumentId, 'Should return contentDocumentId');
        System.assertEquals(null, responses[0].errorMessage, 'Should have no error');
    }

    @isTest
    static void testFlowActionGenerateDocumentError() {
        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = null;
        req.recordId = UserInfo.getUserId();

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].errorMessage, 'Should contain error message');
        System.assertEquals(null, responses[0].contentDocumentId, 'Should not return contentDocumentId');
    }

    @isTest
    static void testGenerateDocumentWithAnchors() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];

        DocGen_DocuSign_Mapping__mdt mapping = new DocGen_DocuSign_Mapping__mdt(
            DeveloperName = 'Test_Anchor_' + System.currentTimeMillis(),
            MasterLabel = 'Test Anchor',
            Merge_Field__c = 'Name',
            Anchor_Tag__c = '[[SIGN_HERE]]',
            Anchor_Type__c = 'SignHere',
            Template_Id__c = tpl.Id,
            Active__c = true
        );
        insert mapping;

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{Name}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'AnchorTemplate',
            PathOnClient = 'AnchorTemplate.docx',
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

        Test.startTest();
        Id resultDocId = DocGenService.generateDocument(tpl.Id, acc.Id, true);
        Test.stopTest();

        System.assertNotEquals(null, resultDocId, 'Should return a ContentDocumentId');

        ContentVersion resultCv = [
            SELECT Id, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :resultDocId AND IsLatest = true
            LIMIT 1
        ];

        Compression.ZipReader reader = new Compression.ZipReader(resultCv.VersionData);
        String documentXml = reader.extract('word/document.xml').toString();
        System.assert(documentXml.contains('[[SIGN_HERE]]'), 'Anchor tag should appear in generated XML: ' + documentXml);
    }

    @isTest
    static void testGenerateDocumentWithAnchorSuffixInLoop() {
        Account acc = new Account(Name = 'Loop Account');
        insert acc;

        Contact con1 = new Contact(FirstName = 'Alice', LastName = 'Smith', AccountId = acc.Id);
        Contact con2 = new Contact(FirstName = 'Bob', LastName = 'Jones', AccountId = acc.Id);
        insert new List<Contact>{ con1, con2 };

        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Loop Template',
            Base_Object_API__c = 'Account',
            Query_Config__c = 'Name, (SELECT FirstName, LastName FROM Contacts)',
            Type__c = 'Word'
        );
        insert tpl;

        DocGen_DocuSign_Mapping__mdt mapping = new DocGen_DocuSign_Mapping__mdt(
            DeveloperName = 'Test_Loop_Anchor_' + System.currentTimeMillis(),
            MasterLabel = 'Test Loop Anchor',
            Merge_Field__c = 'FirstName',
            Anchor_Tag__c = '[[SIGN]]',
            Anchor_Type__c = 'SignHere',
            Unique_Suffix_Field__c = 'LastName',
            Template_Id__c = tpl.Id,
            Active__c = true
        );
        insert mapping;

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{#Contacts}{FirstName}{/Contacts}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'LoopTemplate',
            PathOnClient = 'LoopTemplate.docx',
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

        Test.startTest();
        Id resultDocId = DocGenService.generateDocument(tpl.Id, acc.Id, true);
        Test.stopTest();

        System.assertNotEquals(null, resultDocId, 'Should return a ContentDocumentId');

        ContentVersion resultCv = [
            SELECT Id, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :resultDocId AND IsLatest = true
            LIMIT 1
        ];

        Compression.ZipReader reader = new Compression.ZipReader(resultCv.VersionData);
        String documentXml = reader.extract('word/document.xml').toString();
        System.assert(documentXml.contains('[[SIGN]]-Smith'), 'First unique anchor should appear: ' + documentXml);
        System.assert(documentXml.contains('[[SIGN]]-Jones'), 'Second unique anchor should appear: ' + documentXml);
    }

    @isTest
    static void testFlowActionSendForSignature() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Contact con = new Contact(FirstName = 'Test', LastName = 'Signer', Email = 'signer@example.com', AccountId = acc.Id);
        insert con;

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{Name}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'FlowSigTemplate',
            PathOnClient = 'FlowSigTemplate.docx',
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
    static void testFlowActionSendForSignatureError() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Blob docxBlob = createTestDocx('<w:document><w:body><w:p><w:r><w:t>{Name}</w:t></w:r></w:p></w:body></w:document>');
        ContentVersion cv = new ContentVersion(
            Title = 'FlowErrTemplate',
            PathOnClient = 'FlowErrTemplate.docx',
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

        DocGenFlowAction.Request req = new DocGenFlowAction.Request();
        req.templateId = tpl.Id;
        req.recordId = acc.Id;
        req.sendForSignature = true;

        Test.startTest();
        List<DocGenFlowAction.Response> responses = DocGenFlowAction.generateDocument(new List<DocGenFlowAction.Request>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Should return 1 response');
        System.assertNotEquals(null, responses[0].errorMessage, 'Should contain error message');
        System.assertEquals(null, responses[0].envelopeId, 'Should not return envelopeId');
    }

    @isTest
    static void testGetOrgUrl() {
        Test.startTest();
        String url = DocGenSetupController.getOrgUrl();
        Test.stopTest();
        System.assertNotEquals(null, url, 'Should return org URL');
        System.assert(url.contains('salesforce.com') || url.contains('force.com'), 'URL should be a Salesforce domain');
    }

    @isTest
    static void testGetSettings() {
        Test.startTest();
        DocGen_Settings__c settings = DocGenSetupController.getSettings();
        Test.stopTest();
        System.assertNotEquals(null, settings, 'Should return settings');
    }

    @isTest
    static void testSaveSettings() {
        Test.startTest();
        DocGenSetupController.saveSettings('https://test.example.com');
        Test.stopTest();

        DocGen_Settings__c settings = DocGen_Settings__c.getOrgDefaults();
        System.assertEquals('https://test.example.com', settings.Experience_Site_Url__c, 'Settings should be saved');
    }
}
