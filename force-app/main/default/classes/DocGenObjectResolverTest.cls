@isTest
private class DocGenObjectResolverTest {

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
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(opp.Id);
        Test.stopTest();

        System.assertEquals(1, contacts.size(), 'Should return related contact');
        System.assertEquals(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGetRelatedContacts_OpportunityNoContact() {
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
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(opp.Id);
        Test.stopTest();

        System.assertEquals(0, contacts.size(), 'Should return empty list when no Opportunity contacts');
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
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(acc.Id);
        Test.stopTest();

        System.assertEquals(2, contacts.size(), 'Should return both account contacts');
        Set<Id> contactIds = new Set<Id>{ con1.Id, con2.Id };
        System.assert(contactIds.contains(contacts[0].Id), 'Should include expected contacts');
        System.assert(contactIds.contains(contacts[1].Id), 'Should include expected contacts');
    }

    @isTest
    static void testGetRelatedContacts_AccountPersonAccountPath() {
        // PersonAccount fields may not exist in all orgs; this test verifies the path at minimum returns empty for regular accounts.
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(acc.Id);
        Test.stopTest();

        // For a regular account with no contact roles, the PersonAccount path should not add any contacts.
        System.assertEquals(0, contacts.size(), 'Should return empty for regular account with no roles');
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
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(ct.Id);
        Test.stopTest();

        System.assertEquals(1, contacts.size(), 'Should return contract contacts');
        System.assertEquals(con.Id, contacts[0].Id, 'Should match contact ID');
    }

    @isTest
    static void testGetRelatedContacts_ContractNoSigner() {
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
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(ct.Id);
        Test.stopTest();

        System.assertEquals(0, contacts.size(), 'Should return empty list when Contract has no CustomerSignedId');
    }

    @isTest
    static void testGetRelatedContacts_UnsupportedObject() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'User', AccountId = acc.Id);
        insert con;

        Test.startTest();
        List<Contact> contacts = DocGenObjectResolver.getRelatedContacts(con.Id);
        Test.stopTest();

        System.assertEquals(0, contacts.size(), 'Should return empty list for unsupported object type');
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
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve Opportunity ContactId');
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
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(opp.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when Opportunity has no ContactId');
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
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve primary AccountContactRole');
    }

    @isTest
    static void testResolveDefaultRecipient_AccountPersonAccountPath() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(acc.Id);
        Test.stopTest();

        // Regular account with no primary role should return null; this exercises the PersonAccount check path.
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
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        System.assertEquals(con.Id, resolvedId, 'Should resolve Contract CustomerSignedId');
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
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(ct.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null when Contract has no CustomerSignedId');
    }

    @isTest
    static void testResolveDefaultRecipient_UnsupportedObject() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Contact con = new Contact(FirstName = 'Test', LastName = 'User', AccountId = acc.Id);
        insert con;

        Test.startTest();
        Id resolvedId = DocGenObjectResolver.resolveDefaultRecipient(con.Id);
        Test.stopTest();

        System.assertEquals(null, resolvedId, 'Should return null for unsupported object type');
    }
}
