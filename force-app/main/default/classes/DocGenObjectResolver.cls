public with sharing class DocGenObjectResolver {

    private interface IContactResolver {
        List<Contact> getRelatedContacts(Id recordId);
        Id resolveDefaultRecipient(Id recordId);
    }

    private class OpportunityResolver implements IContactResolver {
        public List<Contact> getRelatedContacts(Id recordId) {
            Set<Id> contactIds = new Set<Id>();
            for (OpportunityContactRole ocr : [
                SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :recordId WITH USER_MODE
            ]) {
                contactIds.add(ocr.ContactId);
            }
            if (contactIds.isEmpty()) return new List<Contact>();
            return [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 100
            ];
        }

        public Id resolveDefaultRecipient(Id recordId) {
            List<Opportunity> opps = [
                SELECT ContactId FROM Opportunity WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!opps.isEmpty() && opps[0].ContactId != null) {
                return opps[0].ContactId;
            }
            return null;
        }
    }

    private class AccountResolver implements IContactResolver {
        public List<Contact> getRelatedContacts(Id recordId) {
            Set<Id> contactIds = new Set<Id>();
            String accountQuery = 'SELECT Id';
            Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
            if (accountFields.containsKey('ispersonaccount')) {
                accountQuery += ', IsPersonAccount';
            }
            if (accountFields.containsKey('personcontactid')) {
                accountQuery += ', PersonContactId';
            }
            accountQuery += ' FROM Account WHERE Id = :recordId LIMIT 1';
            List<Account> accounts = Database.query(accountQuery, AccessLevel.USER_MODE);
            if (!accounts.isEmpty()) {
                Account acc = accounts[0];
                Boolean isPersonAccount = false;
                Id personContactId = null;
                if (accountFields.containsKey('ispersonaccount')) {
                    isPersonAccount = (Boolean) acc.get('IsPersonAccount');
                }
                if (accountFields.containsKey('personcontactid')) {
                    personContactId = (Id) acc.get('PersonContactId');
                }
                if (isPersonAccount == true && personContactId != null) {
                    contactIds.add(personContactId);
                }
                for (AccountContactRole acr : [
                    SELECT ContactId FROM AccountContactRole WHERE AccountId = :recordId WITH USER_MODE LIMIT 100
                ]) {
                    contactIds.add(acr.ContactId);
                }
            }
            if (contactIds.isEmpty()) return new List<Contact>();
            return [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 100
            ];
        }

        public Id resolveDefaultRecipient(Id recordId) {
            String accountQuery = 'SELECT Id';
            Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
            if (accountFields.containsKey('ispersonaccount')) {
                accountQuery += ', IsPersonAccount';
            }
            if (accountFields.containsKey('personcontactid')) {
                accountQuery += ', PersonContactId';
            }
            accountQuery += ' FROM Account WHERE Id = :recordId LIMIT 1';
            List<Account> accounts = Database.query(accountQuery, AccessLevel.USER_MODE);
            if (!accounts.isEmpty()) {
                Account acc = accounts[0];
                Boolean isPersonAccount = false;
                Id personContactId = null;
                if (accountFields.containsKey('ispersonaccount')) {
                    isPersonAccount = (Boolean) acc.get('IsPersonAccount');
                }
                if (accountFields.containsKey('personcontactid')) {
                    personContactId = (Id) acc.get('PersonContactId');
                }
                if (isPersonAccount == true && personContactId != null) {
                    return personContactId;
                }
                List<AccountContactRole> roles = [
                    SELECT ContactId
                    FROM AccountContactRole
                    WHERE AccountId = :recordId AND IsPrimary = true
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!roles.isEmpty()) {
                    return roles[0].ContactId;
                }
            }
            return null;
        }
    }

    private class ContractResolver implements IContactResolver {
        public List<Contact> getRelatedContacts(Id recordId) {
            Set<Id> contactIds = new Set<Id>();
            List<Contract> contracts = [
                SELECT CustomerSignedId FROM Contract WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!contracts.isEmpty() && contracts[0].CustomerSignedId != null) {
                contactIds.add(contracts[0].CustomerSignedId);
            }
            for (ContractContactRole ccr : [
                SELECT ContactId FROM ContractContactRole WHERE ContractId = :recordId WITH USER_MODE
            ]) {
                contactIds.add(ccr.ContactId);
            }
            if (contactIds.isEmpty()) return new List<Contact>();
            return [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 100
            ];
        }

        public Id resolveDefaultRecipient(Id recordId) {
            List<Contract> contracts = [
                SELECT CustomerSignedId FROM Contract WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!contracts.isEmpty() && contracts[0].CustomerSignedId != null) {
                return contracts[0].CustomerSignedId;
            }
            return null;
        }
    }

    private static final Map<Schema.SObjectType, IContactResolver> RESOLVERS = new Map<Schema.SObjectType, IContactResolver>{
        Opportunity.SObjectType => new OpportunityResolver(),
        Account.SObjectType => new AccountResolver(),
        Contract.SObjectType => new ContractResolver()
    };

    public static List<Contact> getRelatedContacts(Id recordId) {
        IContactResolver resolver = RESOLVERS.get(recordId.getSObjectType());
        if (resolver == null) {
            return new List<Contact>();
        }
        return resolver.getRelatedContacts(recordId);
    }

    public static Id resolveDefaultRecipient(Id recordId) {
        IContactResolver resolver = RESOLVERS.get(recordId.getSObjectType());
        if (resolver == null) {
            return null;
        }
        return resolver.resolveDefaultRecipient(recordId);
    }
}
