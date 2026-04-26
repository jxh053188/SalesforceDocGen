public with sharing class DocGenDocuSignService {

    private static String overrideDocuSignTemplateId;

    public static void withDocuSignTemplate(String templateId) {
        overrideDocuSignTemplateId = templateId;
    }

    public static String sendDocumentForSignature(
        Id contentVersionId,
        Id sourceRecordId,
        Id recipientContactId,
        String emailSubject
    ) {
        if (contentVersionId == null || sourceRecordId == null) {
            throw new DocGenException('ContentVersion ID and Source Record ID are required.');
        }

        Id targetContactId = recipientContactId;
        if (targetContactId == null) {
            targetContactId = resolveDefaultRecipient(sourceRecordId);
        }
        if (targetContactId == null) {
            throw new DocGenException(
                'Recipient is required for DocuSign sending. Provide a Contact or configure a default on the source record.'
            );
        }

        List<Contact> contacts = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id = :targetContactId
            WITH USER_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty() || String.isBlank(contacts[0].Email)) {
            throw new DocGenException('Resolved recipient Contact does not have a valid Email address.');
        }
        Contact recipientContact = contacts[0];

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

        dfsle.Recipient recipient = dfsle.Recipient.newBulkRecipient(
            recipientContact.Name,
            recipientContact.Email,
            new dfsle.Entity(recipientContact.Id)
        ).withRoutingOrder(1).withRole('Signer 1');

        String subject = String.isNotBlank(emailSubject)
            ? emailSubject
            : 'Please review and sign: ' + cv.Title;

        dfsle.Envelope envelope = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(sourceRecordId))
            .withDocuments(new List<dfsle.Document>{ doc })
            .withRecipients(new List<dfsle.Recipient>{ recipient })
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

    @TestVisible
    private static Id resolveDefaultRecipient(Id recordId) {
        if (recordId == null) return null;
        return DocGenObjectResolver.resolveDefaultRecipient(recordId);
    }
}
