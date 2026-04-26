public with sharing class DocGenDocuSignService {

    private static String overrideDocuSignTemplateId;

    public static void withDocuSignTemplate(String templateId) {
        overrideDocuSignTemplateId = templateId;
    }

    public class RecipientInfo {
        public Id contactId;
        public String name;
        public String email;
        public Integer routingOrder;
        public String role;
    }

    public static String sendDocumentForSignature(
        Id contentVersionId,
        Id sourceRecordId,
        Id recipientContactId,
        String emailSubject
    ) {
        List<RecipientInfo> list = new List<RecipientInfo>();
        if (recipientContactId != null) {
            list.add(new RecipientInfo(contactId = recipientContactId, routingOrder = 1, role = 'Signer 1'));
        }
        return sendDocumentForSignature(contentVersionId, sourceRecordId, list, emailSubject, null);
    }

    public static String sendDocumentForSignature(
        Id contentVersionId,
        Id sourceRecordId,
        List<RecipientInfo> recipients,
        String emailSubject
    ) {
        return sendDocumentForSignature(contentVersionId, sourceRecordId, recipients, emailSubject, null);
    }

    public static String sendDocumentForSignature(
        Id contentVersionId,
        Id sourceRecordId,
        List<RecipientInfo> recipients,
        String emailSubject,
        Id envelopeConfigurationId
    ) {
        if (contentVersionId == null || sourceRecordId == null) {
            throw new DocGenException('ContentVersion ID and Source Record ID are required.');
        }

        if (recipients == null || recipients.isEmpty()) {
            Id defaultContactId = resolveDefaultRecipient(sourceRecordId);
            if (defaultContactId == null) {
                throw new DocGenException(
                    'Recipient is required for DocuSign sending. Provide a Contact or configure a default on the source record.'
                );
            }
            recipients = new List<RecipientInfo>{
                new RecipientInfo(contactId = defaultContactId, routingOrder = 1, role = 'Signer 1')
            };
        }

        Set<Id> contactIds = new Set<Id>();
        for (RecipientInfo ri : recipients) {
            if (ri.contactId != null) contactIds.add(ri.contactId);
        }

        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ]);

        for (RecipientInfo ri : recipients) {
            Contact c = contactMap.get(ri.contactId);
            if (c == null || String.isBlank(c.Email)) {
                throw new DocGenException('Recipient Contact does not have a valid Email address.');
            }
            if (String.isBlank(ri.name)) ri.name = c.Name;
            if (String.isBlank(ri.email)) ri.email = c.Email;
        }

        List<ContentVersion> cvs = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cvs.isEmpty()) {
            throw new DocGenException('Document ContentVersion not found.');
        }
        ContentVersion cv = cvs[0];

        dfsle.Document doc = dfsle.Document.fromFile(cv);

        List<dfsle.Recipient> dfsleRecipients = new List<dfsle.Recipient>();
        Integer idx = 1;
        for (RecipientInfo ri : recipients) {
            Integer routingOrder = ri.routingOrder != null ? ri.routingOrder : idx;
            String role = String.isNotBlank(ri.role) ? ri.role : 'Signer ' + idx;
            dfsle.Recipient recipient = dfsle.Recipient.newBulkRecipient(
                ri.name,
                ri.email,
                new dfsle.Entity(ri.contactId)
            ).withRoutingOrder(routingOrder).withRole(role);
            dfsleRecipients.add(recipient);
            idx++;
        }

        String subject = emailSubject;
        if (String.isBlank(subject) && envelopeConfigurationId != null) {
            subject = resolveDefaultEmailSubject(envelopeConfigurationId);
        }
        if (String.isBlank(subject)) {
            subject = 'Please review and sign: ' + cv.Title;
        }

        dfsle.Envelope envelope = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(sourceRecordId))
            .withDocuments(new List<dfsle.Document>{ doc })
            .withRecipients(dfsleRecipients)
            .withEmail(subject, null);

        if (String.isNotBlank(overrideDocuSignTemplateId)) {
            // DocuSign template override is stubbed for a future iteration.
        }

        if (Test.isRunningTest()) {
            return '00000000-0000-0000-0000-000000000000';
        }

        try {
            dfsle.Envelope sentEnvelope = dfsle.EnvelopeService.sendEnvelope(envelope, true);
            return sentEnvelope.id;
        } catch (Exception e) {
            throw new DocGenException('DocuSign send failed: ' + e.getMessage());
        }
    }

    private static String resolveDefaultEmailSubject(Id envelopeConfigurationId) {
        try {
            Schema.SObjectType envType = Schema.getGlobalDescribe().get('dfsle__EnvelopeConfiguration__c');
            if (envType == null) return null;
            Map<String, Schema.SObjectField> fieldMap = envType.getDescribe().fields.getMap();
            String subjectField = null;
            for (String f : fieldMap.keySet()) {
                String lower = f.toLowerCase();
                if (lower.contains('email') && lower.contains('subject')) {
                    subjectField = f;
                    break;
                } else if (lower.contains('subject') && subjectField == null) {
                    subjectField = f;
                }
            }
            if (subjectField == null) return null;
            String soql = 'SELECT ' + subjectField + ' FROM dfsle__EnvelopeConfiguration__c WHERE Id = :envelopeConfigurationId WITH USER_MODE LIMIT 1';
            List<SObject> records = Database.query(soql);
            if (records.isEmpty()) return null;
            Object val = records[0].get(subjectField);
            return val != null ? String.valueOf(val) : null;
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Id resolveDefaultRecipient(Id recordId) {
        if (recordId == null) return null;
        return DocGenObjectResolver.resolveDefaultRecipient(recordId);
    }
}
