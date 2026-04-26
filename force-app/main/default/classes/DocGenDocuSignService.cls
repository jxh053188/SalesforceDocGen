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
        Schema.SObjectType recordType = recordId.getSObjectType();

        if (recordType == Opportunity.SObjectType) {
            List<Opportunity> opps = [
                SELECT ContactId FROM Opportunity WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!opps.isEmpty() && opps[0].ContactId != null) {
                return opps[0].ContactId;
            }
        } else if (recordType == Contract.SObjectType) {
            List<Contract> contracts = [
                SELECT CustomerSignedId FROM Contract WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            if (!contracts.isEmpty() && contracts[0].CustomerSignedId != null) {
                return contracts[0].CustomerSignedId;
            }
        } else if (recordType == Account.SObjectType) {
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
        }

        return null;
    }
}
