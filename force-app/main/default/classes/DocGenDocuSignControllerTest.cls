@isTest
private class DocGenDocuSignControllerTest {

    @testSetup
    static void setup() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'Test Template',
            Base_Object_API__c = 'Account',
            Query_Config__c = 'Name',
            Type__c = 'Word'
        );
        insert tpl;
    }

    @isTest
    static void testGetTemplatesForRecord() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        List<DocGen_Template__c> templates = DocGenDocuSignController.getTemplatesForRecord(acc.Id);
        Test.stopTest();

        System.assertEquals(1, templates.size(), 'Should return template for Account');
    }

    @isTest
    static void testGetRelatedContacts_Opportunity() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id
        );
        insert opp;

        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = con.Id
        );
        insert ocr;

        Test.startTest();
        List<Contact> contacts = DocGenDocuSignController.getRelatedContacts(opp.Id);
        Test.stopTest();

        System.assertEquals(1, contacts.size(), 'Should return related contact');
        System.assertEquals(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGenerateAndSend_Success() {
        DocGen_Template__c tpl = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

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
        Map<String, String> result = DocGenDocuSignController.generateAndSend(tpl.Id, acc.Id, con.Id, 'Test Subject');
        Test.stopTest();

        System.assertNotEquals(null, result.get('contentDocumentId'), 'Should return contentDocumentId');
        System.assertNotEquals(null, result.get('envelopeId'), 'Should return envelopeId');
    }

    @isTest
    static void testGetTemplatesForRecord_Null() {
        Test.startTest();
        List<DocGen_Template__c> templates = DocGenDocuSignController.getTemplatesForRecord(null);
        Test.stopTest();

        System.assertEquals(0, templates.size(), 'Should return empty list for null recordId');
    }

    @isTest
    static void testGetRelatedContacts_Account() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con1 = new Contact(FirstName = 'Test1', LastName = 'User1', Email = 'test1@example.com', AccountId = acc.Id);
        Contact con2 = new Contact(FirstName = 'Test2', LastName = 'User2', Email = 'test2@example.com', AccountId = acc.Id);
        insert new List<Contact>{ con1, con2 };

        AccountContactRole acr1 = new AccountContactRole(AccountId = acc.Id, ContactId = con1.Id, IsPrimary = true);
        AccountContactRole acr2 = new AccountContactRole(AccountId = acc.Id, ContactId = con2.Id);
        insert new List<AccountContactRole>{ acr1, acr2 };

        Test.startTest();
        List<Contact> contacts = DocGenDocuSignController.getRelatedContacts(acc.Id);
        Test.stopTest();

        System.assertEquals(2, contacts.size(), 'Should return both account contacts');
        Set<Id> contactIds = new Set<Id>{ con1.Id, con2.Id };
        System.assert(contactIds.contains(contacts[0].Id), 'Should include expected contacts');
        System.assert(contactIds.contains(contacts[1].Id), 'Should include expected contacts');
    }

    @isTest
    static void testGetRelatedContacts_Contract() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        Contract ct = new Contract(
            AccountId = acc.Id,
            CustomerSignedId = con.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        insert ct;

        ContractContactRole ccr = new ContractContactRole(ContractId = ct.Id, ContactId = con.Id);
        insert ccr;

        Test.startTest();
        List<Contact> contacts = DocGenDocuSignController.getRelatedContacts(ct.Id);
        Test.stopTest();

        System.assertEquals(1, contacts.size(), 'Should return contract contacts');
        System.assertEquals(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGetRelatedContacts_Empty() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        List<Contact> contacts = DocGenDocuSignController.getRelatedContacts(acc.Id);
        Test.stopTest();

        System.assertEquals(0, contacts.size(), 'Should return empty list when no contacts found');
    }

    @isTest
    static void testGenerateAndSend_NoTemplate() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Boolean threw = false;
        Test.startTest();
        try {
            DocGenDocuSignController.generateAndSend(null, acc.Id, null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw for null template');
    }

    @isTest
    static void testGenerateAndSend_HtmlTemplateError() {
        DocGen_Template__c tpl = new DocGen_Template__c(
            Name = 'HTML Template',
            Base_Object_API__c = 'Account',
            Query_Config__c = 'Name',
            Type__c = 'HTML'
        );
        insert tpl;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenDocuSignController.generateAndSend(tpl.Id, acc.Id, con.Id, 'Test');
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        } catch (Exception e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'Should throw exception for HTML template');
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
}
