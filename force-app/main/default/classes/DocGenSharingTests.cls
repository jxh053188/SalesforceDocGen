@IsTest
private class DocGenSharingTests {

    @TestSetup
    static void setup() {
        DocGen_Template__c t = new DocGen_Template__c(
            Name = 'Sharing Template',
            Base_Object_API__c = 'Account'
        );
        insert t;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole r = new UserRole(Name = 'DocGenTestRole', DeveloperName = 'DocGenTestRole_' + DateTime.now().getTime());
            insert r;

            Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
            User u = new User(Alias = 'standt', Email='standarduser@testorg.com',
                EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US',
                LocaleSidKey='en_US', ProfileId = p.Id, UserRoleId = r.Id,
                TimeZoneSidKey='America/Los_Angeles', UserName='standarduser' + DateTime.now().getTime() + '@testorg.com');
            insert u;
        }
    }

    @IsTest
    static void testSharingOperations() {
        DocGen_Template__c t = [SELECT Id FROM DocGen_Template__c LIMIT 1];
        User u = [SELECT Id FROM User WHERE LastName='Testing' LIMIT 1];
        
        Test.startTest();
        
        // Share
        DocGenController.shareTemplate(t.Id, u.Id, 'Read');
        
        // Verify Share exists via actual SOQL to guarantee valid ID type
        DocGen_Template__Share shareRef = [SELECT Id FROM DocGen_Template__Share WHERE ParentId = :t.Id AND UserOrGroupId = :u.Id LIMIT 1];
        System.assertNotEquals(null, shareRef, 'Share record should exist in DB');
        
        // Remove Share
        DocGenController.removeShare(shareRef.Id);
        
        List<Map<String, String>> shares = DocGenController.getTemplateShares(t.Id);
        Boolean found = false;
        for (Map<String, String> s : shares) {
            if (s.get('UserOrGroupId') == u.Id) found = true;
        }
        System.assert(!found, 'Share should be removed');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testSearch() {
        Test.startTest();
        List<Map<String, String>> results = DocGenController.searchUsersAndGroups('Testing');
        Test.stopTest();
        System.assert(results.size() > 0, 'Should find user');
    }
}