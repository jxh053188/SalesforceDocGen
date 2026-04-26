@isTest
private class DocGenObjectResolverTest {

    @TestSetup
    static void setupData() {
        Account acc1 = new Account(Name = 'Test Account 1');
        Account acc2 = new Account(Name = 'Test Account 2');
        insert new List<Account>{ acc1, acc2 };

        Contact con1 = new Contact(FirstName = 'Test1', LastName = 'User1', Email = 'test1@example.com', AccountId = acc1.Id);
        Contact con2 = new Contact(FirstName = 'Test2', LastName = 'User2', Email = 'test2@example.com', AccountId = acc1.Id);
        insert new List<Contact>{ con1, con2 };

        Opportunity oppWithContact = new Opportunity(
            Name = 'Test Opp With Contact',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc1.Id,
            ContactId = con1.Id
        );
        Opportunity oppNoContact = new Opportunity(
            Name = 'Test Opp No Contact',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = acc2.Id
        );
        insert new List<Opportunity>{ oppWithContact, oppNoContact };

        Contract ctWithSigner = new Contract(
            AccountId = acc1.Id,
            CustomerSignedId = con1.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        Contract ctNoSigner = new Contract(
            AccountId = acc2.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        insert new List<Contract>{ ctWithSigner, ctNoSigner };

        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = oppWithContact.Id,
            ContactId = con1.Id
        );
        insert ocr;

        AccountContactRole acr1 = new AccountContactRole(AccountId = acc1.Id, ContactId = con1.Id, IsPrimary = true);
        AccountContactRole acr2 = new AccountContactRole(AccountId = acc1.Id, ContactId = con2.Id);
        insert new List<AccountContactRole>{ acr1, acr2 };

        ContractContactRole ccr = new ContractContactRole(ContractId = ctWithSigner.Id, ContactId = con1.Id);
        insert ccr;
    }

    @isTest
    static void testGetRelatedContacts_Opportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp With Contact' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(opp.Id);
        Test.stopTest();

        Assert.areEqual(1, contacts.size(), 'Should return related contact');
        Assert.areEqual(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGetRelatedContacts_OpportunityNoContact() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp No Contact' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(opp.Id);
        Test.stopTest();

        Assert.areEqual(0, contacts.size(), 'Should return empty list when no Opportunity contacts');
    }

    @isTest
    static void testGetRelatedContacts_Account() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Contact con1 = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];
        Contact con2 = [SELECT Id FROM Contact WHERE Email = 'test2@example.com' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(acc.Id);
        Test.stopTest();

        Assert.areEqual(2, contacts.size(), 'Should return both account contacts');
        Set<Id> contactIds = new Set<Id>{ con1.Id, con2.Id };
        Assert.isTrue(contactIds.contains(contacts[0].Id), 'Should include expected contacts');
        Assert.isTrue(contactIds.contains(contacts[1].Id), 'Should include expected contacts');
    }

    @isTest
    static void testGetRelatedContacts_AccountPersonAccountPath() {
        // PersonAccount fields may not exist in all orgs; this test verifies the path at minimum returns empty for regular accounts.
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 2' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(acc.Id);
        Test.stopTest();

        // For a regular account with no contact roles, the PersonAccount path should not add any contacts.
        Assert.areEqual(0, contacts.size(), 'Should return empty for regular account with no roles');
    }

    @isTest
    static void testGetRelatedContacts_Contract() {
        Contract ct = [SELECT Id FROM Contract WHERE Account.Name = 'Test Account 1' AND CustomerSignedId != null LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(ct.Id);
        Test.stopTest();

        Assert.areEqual(1, contacts.size(), 'Should return contract contacts');
        Assert.areEqual(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGetRelatedContacts_ContractNoSigner() {
        Contract ct = [SELECT Id FROM Contract WHERE Account.Name = 'Test Account 2' AND CustomerSignedId = null LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(ct.Id);
        Test.stopTest();

        Assert.areEqual(0, contacts.size(), 'Should return empty list when Contract has no CustomerSignedId');
    }

    @isTest
    static void testGetRelatedContacts_UnsupportedObject() {
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(con.Id);
        Test.stopTest();

        Assert.areEqual(0, contacts.size(), 'Should return empty list for unsupported object type');
    }

    @isTest
    static void testResolveDefaultRecipient_Opportunity() {
        Opportunity opp = [SELECT Id, ContactId FROM Opportunity WHERE Name = 'Test Opp With Contact' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        Assert.areEqual(con.Id, resolvedId, 'Should resolve Opportunity ContactId');
    }

    @isTest
    static void testResolveDefaultRecipient_OpportunityNoContact() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp No Contact' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        Assert.isNull(resolvedId, 'Should return null when Opportunity has no ContactId');
    }

    @isTest
    static void testResolveDefaultRecipient_Account() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        Assert.areEqual(con.Id, resolvedId, 'Should resolve primary AccountContactRole');
    }

    @isTest
    static void testResolveDefaultRecipient_AccountPersonAccountPath() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 2' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        // Regular account with no primary role should return null; this exercises the PersonAccount check path.
        Assert.isNull(resolvedId, 'Should return null for regular account without primary role');
    }

    @isTest
    static void testResolveDefaultRecipient_Contract() {
        Contract ct = [SELECT Id FROM Contract WHERE Account.Name = 'Test Account 1' AND CustomerSignedId != null LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        Assert.areEqual(con.Id, resolvedId, 'Should resolve Contract CustomerSignedId');
    }

    @isTest
    static void testResolveDefaultRecipient_ContractNoSigner() {
        Contract ct = [SELECT Id FROM Contract WHERE Account.Name = 'Test Account 2' AND CustomerSignedId = null LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        Assert.isNull(resolvedId, 'Should return null when Contract has no CustomerSignedId');
    }

    @isTest
    static void testResolveDefaultRecipient_UnsupportedObject() {
        Contact con = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(con.Id);
        Test.stopTest();

        Assert.isNull(resolvedId, 'Should return null for unsupported object type');
    }
}
