public with sharing class DocGenDocuSignController {

    /**
     * Exception Convention:
     * - Validation / business logic errors -> throw new DocGenException(...)
     * - Errors surfaced to LWC/Aura components -> throw new AuraHandledException(...)
     * - Unexpected system errors -> wrap in AuraHandledException with a generic message
     */

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
                throw new AuraHandledException('Generated document version not found.');
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

    /**
     * Generates a document from the specified template and sends it for DocuSign signature
     * with multiple recipients.
     *
     * @param templateId The DocGen template ID to use for document generation.
     * @param recordId The source record ID to generate the document for.
     * @param recipientInputs List of maps containing contactId for each recipient.
     * @param emailSubject Optional custom email subject for the DocuSign envelope.
     * @return Map containing contentDocumentId and envelopeId.
     */
    @AuraEnabled
    public static Map<String, String> generateAndSendWithRecipients(
        Id templateId,
        Id recordId,
        List<Map<String, String>> recipientInputs,
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
                throw new AuraHandledException('Generated document version not found.');
            }

            List<DocGenDocuSignService.RecipientInfo> recipients = new List<DocGenDocuSignService.RecipientInfo>();
            Integer idx = 1;
            for (Map<String, String> ri : recipientInputs) {
                DocGenDocuSignService.RecipientInfo r = new DocGenDocuSignService.RecipientInfo();
                r.contactId = ri.get('contactId');
                r.routingOrder = idx;
                r.role = 'Signer ' + idx;
                recipients.add(r);
                idx++;
            }

            String envelopeId = DocGenDocuSignService.sendDocumentForSignature(
                cvs[0].Id,
                recordId,
                recipients,
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
