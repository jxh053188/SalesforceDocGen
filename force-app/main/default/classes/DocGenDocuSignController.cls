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
        return DocGenObjectResolver.getRelatedContacts(recordId);
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
