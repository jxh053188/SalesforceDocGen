global with sharing class DocGenFlowAction {

    global class Request {
        @InvocableVariable(label='Template ID' required=true)
        global Id templateId;

        @InvocableVariable(label='Base Record ID' required=true)
        global Id recordId;

        @InvocableVariable(label='Send for DocuSign Signature' required=false)
        global Boolean sendForSignature;

        @InvocableVariable(label='Recipient Contact ID' required=false)
        global Id recipientContactId;

        @InvocableVariable(label='Recipient Contact IDs (comma-separated)' required=false)
        global String recipientContactIds;

        @InvocableVariable(label='Email Subject' required=false)
        global String emailSubject;
    }

    global class Response {
        @InvocableVariable(label='Content Document ID')
        global Id contentDocumentId;

        @InvocableVariable(label='Error Message')
        global String errorMessage;

        @InvocableVariable(label='DocuSign Envelope ID')
        global String envelopeId;
    }

    @InvocableMethod(label='Generate Document (Native)' description='Generates a DOCX/PPTX document using the DocGen package. Note: Does not support complex loops or conditional logic in this version.')
    global static List<Response> generateDocument(List<Request> requests) {
        List<Response> responses = new List<Response>();
        List<Integer> signatureIndices = new List<Integer>();
        Set<Id> contentDocIds = new Set<Id>();

        // First pass: generate documents and collect IDs for signature requests
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Response res = new Response();
            try {
                Id docId = DocGenService.generateDocument(
                    req.templateId,
                    req.recordId,
                    req.sendForSignature == true
                );
                res.contentDocumentId = docId;

                if (req.sendForSignature == true) {
                    signatureIndices.add(i);
                    contentDocIds.add(docId);
                }
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
            responses.add(res);
        }

        // Bulk query latest ContentVersions for all signature documents
        Map<Id, Id> contentDocToVersionId = new Map<Id, Id>();
        if (!contentDocIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIds AND IsLatest = true
                WITH USER_MODE
            ]) {
                contentDocToVersionId.put(cv.ContentDocumentId, cv.Id);
            }
        }

        // Second pass: send for DocuSign signature using bulk-queried versions
        for (Integer i : signatureIndices) {
            Request req = requests[i];
            Response res = responses[i];
            Id versionId = contentDocToVersionId.get(res.contentDocumentId);
            if (versionId == null) {
                res.errorMessage = 'Latest ContentVersion not found for generated document.';
                continue;
            }

            try {
                if (String.isNotBlank(req.recipientContactIds)) {
                    List<DocGenDocuSignService.RecipientInfo> recipients = new List<DocGenDocuSignService.RecipientInfo>();
                    List<String> ids = req.recipientContactIds.split(',');
                    Integer idx = 1;
                    for (String cid : ids) {
                        String trimmed = cid.trim();
                        if (String.isBlank(trimmed)) continue;
                        DocGenDocuSignService.RecipientInfo ri = new DocGenDocuSignService.RecipientInfo();
                        ri.contactId = trimmed;
                        ri.routingOrder = idx;
                        ri.role = 'Signer ' + idx;
                        recipients.add(ri);
                        idx++;
                    }
                    res.envelopeId = DocGenDocuSignService.sendDocumentForSignature(
                        versionId,
                        req.recordId,
                        recipients,
                        req.emailSubject
                    );
                } else {
                    res.envelopeId = DocGenDocuSignService.sendDocumentForSignature(
                        versionId,
                        req.recordId,
                        req.recipientContactId,
                        req.emailSubject
                    );
                }
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
        }

        return responses;
    }
}
