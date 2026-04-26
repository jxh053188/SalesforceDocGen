@isTest
public class DocGenSignatureSenderControllerTest {

    @TestSetup
    static void setupData() {
        // Insert org default settings so URL generation works
        DocGen_Settings__c settings = new DocGen_Settings__c(
            Experience_Site_Url__c = 'https://test.example.com/s/sign'
        );
        insert settings;

        // Create a ContentVersion (auto-creates ContentDocument) for valid-document tests
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.docx',
            VersionData = Blob.valueOf('Test document body'),
            IsMajorVersion = true
        );
        insert cv;
    }

    @isTest
    static void getRelatedDocuments_withDocuments() {
        Account acc = new Account(Name = 'Test Account With Docs');
        insert acc;

        ContentVersion cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Title = 'Test Document'
            LIMIT 1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<ContentVersion> results = DocGenSignatureSenderController.getRelatedDocuments(acc.Id);
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Expected at least one related document');
    }

    @isTest
    static void getRelatedDocuments_noDocuments() {
        Account acc = new Account(Name = 'Test Account No Docs');
        insert acc;

        Test.startTest();
        List<ContentVersion> results = DocGenSignatureSenderController.getRelatedDocuments(acc.Id);
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Expected no related documents');
    }

    @isTest
    static void createSignatureRequest_success() {
        ContentVersion cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Title = 'Test Document'
            LIMIT 1
        ];

        Account acc = new Account(Name = 'Signer Account');
        insert acc;

        Test.startTest();
        String url = DocGenSignatureSenderController.createSignatureRequest(
            cv.ContentDocumentId,
            acc.Id,
            'Test Signer',
            'test@example.com'
        );
        Test.stopTest();

        Assert.isTrue(url.contains('token='), 'Returned URL should contain a token parameter');

        String token = url.substringAfter('token=');
        List<DocGen_Signature_Request__c> requests = [
            SELECT Id, Status__c, Secure_Token__c
            FROM DocGen_Signature_Request__c
            WHERE Secure_Token__c = :token
            LIMIT 1
        ];

        Assert.isFalse(requests.isEmpty(), 'A Signature Request record should exist');
        Assert.areEqual('Sent', requests[0].Status__c, 'Status should be Sent');
        Assert.areEqual(token, requests[0].Secure_Token__c, 'Token should match');
    }

    @isTest
    static void createSignatureRequest_missingDocument() {
        Account acc = new Account(Name = 'Missing Doc Account');
        insert acc;

        Id bogusContentDocId = Id.valueOf('069000000000000AAA');

        Test.startTest();
        Boolean exceptionThrown = false;
        String errorMessage = '';
        try {
            DocGenSignatureSenderController.createSignatureRequest(
                bogusContentDocId,
                acc.Id,
                'Test Signer',
                'test@example.com'
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Expected AuraHandledException for missing document');
        Assert.isTrue(
            errorMessage.containsIgnoreCase('permission') || errorMessage.containsIgnoreCase('deleted'),
            'Error message should mention permission or deleted'
        );
    }

    @isTest
    static void createSignatureRequest_tokenUniqueness() {
        // Create additional ContentDocuments so each request has a unique document
        List<ContentVersion> cvs = new List<ContentVersion>();
        for (Integer i = 0; i < 5; i++) {
            cvs.add(new ContentVersion(
                Title = 'Test Doc ' + i,
                PathOnClient = 'TestDoc' + i + '.docx',
                VersionData = Blob.valueOf('Body ' + i),
                IsMajorVersion = true
            ));
        }
        insert cvs;

        List<ContentVersion> insertedCvs = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE 'Test Doc %'
            ORDER BY Title
        ];

        Account acc = new Account(Name = 'Token Uniqueness Account');
        insert acc;

        Set<String> tokens = new Set<String>();
        Test.startTest();
        for (Integer i = 0; i < insertedCvs.size(); i++) {
            String url = DocGenSignatureSenderController.createSignatureRequest(
                insertedCvs[i].ContentDocumentId,
                acc.Id,
                'Signer ' + i,
                'signer' + i + '@example.com'
            );
            String token = url.substringAfter('token=');
            Assert.isNotNull(token, 'Token should not be null');
            Assert.isTrue(token.length() >= 32, 'Token should be at least 32 characters long');
            Assert.isFalse(tokens.contains(token), 'Token should be unique across requests');
            tokens.add(token);
        }
        Test.stopTest();

        Assert.areEqual(5, tokens.size(), 'All 5 tokens should be unique');
    }
}
