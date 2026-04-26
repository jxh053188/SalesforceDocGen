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

        for (Request req : requests) {
            Response res = new Response();
            try {
                Id docId = DocGenService.generateDocument(
                    req.templateId,
                    req.recordId,
                    req.sendForSignature == true
                );
                res.contentDocumentId = docId;

                if (req.sendForSignature == true) {
                    List<ContentVersion> cvs = [
                        SELECT Id
                        FROM ContentVersion
                        WHERE ContentDocumentId = :docId AND IsLatest = true
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    if (cvs.isEmpty()) {
                        throw new DocGenException('Latest ContentVersion not found for generated document.');
                    }

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
                            cvs[0].Id,
                            req.recordId,
                            recipients,
                            req.emailSubject
                        );
                    } else {
                        res.envelopeId = DocGenDocuSignService.sendDocumentForSignature(
                            cvs[0].Id,
                            req.recordId,
                            req.recipientContactId,
                            req.emailSubject
                        );
                    }
                }
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
            responses.add(res);
        }

        return responses;
    }
}