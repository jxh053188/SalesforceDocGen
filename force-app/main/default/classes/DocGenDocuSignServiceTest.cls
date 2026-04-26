/**
 * @description Tests for DocGenDocuSignService.
 * Note: resolveDefaultRecipient logic now delegates to DocGenObjectResolver.
 */
@isTest
private class DocGenDocuSignServiceTest {

    @isTest
    static void testSendDocumentForSignature_Success() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.docx',
            VersionData = Blob.valueOf('Test'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        cv = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :contentDocId AND IsLatest = true LIMIT 1];

        Test.startTest();
        String envelopeId = DocGenDocuSignService.sendDocumentForSignature(cv.Id, acc.Id, con.Id, 'Test Subject');
        Test.stopTest();

        System.assertEquals('00000000-0000-0000-0000-000000000000', envelopeId, 'Should return dummy envelope ID in test context');
    }

    @isTest
    static void testSendDocumentForSignature_MissingContentVersion() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenDocuSignService.sendDocumentForSignature(null, acc.Id, null, null);
        } catch (DocGenException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'Should throw for null contentVersionId');
        System.assert(message.contains('ContentVersion ID and Source Record ID are required'), message);
    }

    @isTest
    static void testSendDocumentForSignature_MissingRecipient() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.docx',
            VersionData = Blob.valueOf('Test'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        cv = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :contentDocId AND IsLatest = true LIMIT 1];

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenDocuSignService.sendDocumentForSignature(cv.Id, acc.Id, null, null);
        } catch (DocGenException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when recipient cannot be resolved');
        System.assert(message.contains('Recipient is required'), message);
    }

    @isTest
    static void testResolveDefaultRecipient_Opportunity() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id,
            ContactId = con.Id
        );
        insert opp;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve Opportunity ContactId');
    }

    @isTest
    static void testResolveDefaultRecipient_Account() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        AccountContactRole acr = new AccountContactRole(AccountId = acc.Id, ContactId = con.Id, IsPrimary = true);
        insert acr;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve primary AccountContactRole');
    }

    @isTest
    static void testResolveDefaultRecipient_AccountPersonAccount() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null for regular account without primary role');
    }

    @isTest
    static void testResolveDefaultRecipient_Contract() {
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

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve Contract CustomerSignedId');
    }

    @isTest
    static void testResolveDefaultRecipient_NoDefault() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when no default recipient found');
    }

    @isTest
    static void testSendDocumentForSignature_ResolvedContactNoEmail() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = null, AccountId = acc.Id);
        insert con;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.docx',
            VersionData = Blob.valueOf('Test'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        cv = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :contentDocId AND IsLatest = true LIMIT 1];

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenDocuSignService.sendDocumentForSignature(cv.Id, acc.Id, con.Id, 'Test Subject');
        } catch (DocGenException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when resolved contact has no email');
        System.assert(message.contains('valid Email address'), message);
    }

    @isTest
    static void testSendDocumentForSignature_WithTemplateOverride() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.docx',
            VersionData = Blob.valueOf('Test'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        cv = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :contentDocId AND IsLatest = true LIMIT 1];

        DocGenDocuSignService.withDocuSignTemplate('override-template-id');

        Test.startTest();
        String envelopeId = DocGenDocuSignService.sendDocumentForSignature(cv.Id, acc.Id, con.Id, 'Test Subject');
        Test.stopTest();

        System.assertEquals('00000000-0000-0000-0000-000000000000', envelopeId, 'Should return dummy envelope ID with template override');

        DocGenDocuSignService.withDocuSignTemplate(null);
    }

    @isTest
    static void testResolveDefaultRecipient_OpportunityNoContact() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc.Id
        );
        insert opp;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when Opportunity has no ContactId');
    }

    @isTest
    static void testResolveDefaultRecipient_ContractNoSigner() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contract ct = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        insert ct;

        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when Contract has no CustomerSignedId');
    }

    @isTest
    static void testResolveDefaultRecipient_Null() {
        Test.startTest();
        Id resolvedId = DocGenDocuSignService.resolveDefaultRecipient(null);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when recordId is null');
    }

    @isTest
    static void testSendDocumentForSignature_MissingContentVersionRecord() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@example.com', AccountId = acc.Id);
        insert con;

        Id fakeCvId = '068000000000000';

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            DocGenDocuSignService.sendDocumentForSignature(fakeCvId, acc.Id, con.Id, 'Test Subject');
        } catch (DocGenException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when ContentVersion record is missing');
        System.assert(message.contains('Document ContentVersion not found'), message);
    }
}
