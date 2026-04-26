public with sharing class DocGenDocuSignController {

    @AuraEnabled(cacheable=true)
    public static List<DocGen_Template__c> getTemplatesForRecord(Id recordId) {
        if (recordId == null) return new List<DocGen_Template__c>();
        String objectApiName = String.valueOf(recordId.getSObjectType());
        return DocGenController.getTemplatesForObject(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> getRelatedContacts(Id recordId) {
        if (recordId == null) return new List<Contact>();
        Schema.SObjectType recordType = recordId.getSObjectType();
        Set<Id> contactIds = new Set<Id>();

        if (recordType == Opportunity.SObjectType) {
            for (OpportunityContactRole ocr : [
                SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :recordId WITH USER_MODE
            ]) {
                contactIds.add(ocr.ContactId);
            }
        } else if (recordType == Account.SObjectType) {
            List<Account> accounts = [
                SELECT PersonContactId, IsPersonAccount FROM Account WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                if (accounts[0].IsPersonAccount == true && accounts[0].PersonContactId != null) {
                    contactIds.add(accounts[0].PersonContactId);
                }
                for (AccountContactRole acr : [
                    SELECT ContactId FROM AccountContactRole WHERE AccountId = :recordId WITH USER_MODE LIMIT 100
                ]) {
                    contactIds.add(acr.ContactId);
                }
            }
        } else if (recordType == Contract.SObjectType) {
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

    @AuraEnabled
    public static Map<String, String> generateAndSend(
        Id templateId,
        Id recordId,
        Id recipientContactId,
        String emailSubject
    ) {
        try {
            Id contentDocId = DocGenService.generateDocument(templateId, recordId, true);

            List<ContentVersion> cvs = [
                SELECT Id FROM ContentVersion
                WHERE ContentDocumentId = :contentDocId AND IsLatest = true
                WITH USER_MODE LIMIT 1
            ];
            if (cvs.isEmpty()) {
                throw new DocGenException('Generated document version not found.');
            }

            String envelopeId = DocGenDocuSignService.sendDocumentForSignature(
                cvs[0].Id,
                recordId,
                recipientContactId,
                emailSubject
            );

            return new Map<String, String>{
                'contentDocumentId' => contentDocId,
                'envelopeId' => envelopeId
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
