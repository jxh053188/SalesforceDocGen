import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplatesForRecord from '@salesforce/apex/DocGenDocuSignController.getTemplatesForRecord';
import getRelatedContacts from '@salesforce/apex/DocGenDocuSignController.getRelatedContacts';
import generateAndSend from '@salesforce/apex/DocGenDocuSignController.generateAndSend';

export default class DocGenDocuSignSender extends LightningElement {
    @api recordId;
    @track templateOptions = [];
    @track contactOptions = [];
    @track selectedTemplateId = '';
    @track selectedContactId = '';
    @track emailSubject = '';
    @track isLoading = true;
    @track error;

    @wire(getTemplatesForRecord, { recordId: '$recordId' })
    wiredTemplates({ error, data }) {
        this.isLoading = true;
        if (data) {
            this.templateOptions = data.map(tpl => {
                return { label: tpl.Name, value: tpl.Id };
            });
            this.error = undefined;
        } else if (error) {
            this.error = 'Error loading templates: ' + error.body.message;
            this.templateOptions = [];
        }
        this.isLoading = false;
    }

    @wire(getRelatedContacts, { recordId: '$recordId' })
    wiredContacts({ error, data }) {
        if (data) {
            this.contactOptions = [
                { label: '-- Use Record Default --', value: '' },
                ...data.map(contact => {
                    return { label: contact.Name + (contact.Email ? ' (' + contact.Email + ')' : ''), value: contact.Id };
                })
            ];
        } else if (error) {
            this.contactOptions = [{ label: '-- Use Record Default --', value: '' }];
        }
    }

    get isGenerateDisabled() {
        return !this.selectedTemplateId || this.isLoading;
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
    }

    handleEmailSubjectChange(event) {
        this.emailSubject = event.target.value;
    }

    async handleGenerateAndSend() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const result = await generateAndSend({
                templateId: this.selectedTemplateId,
                recordId: this.recordId,
                recipientContactId: this.selectedContactId || null,
                emailSubject: this.emailSubject
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'DocuSign Sent',
                    message: 'Envelope ID: ' + result.envelopeId,
                    variant: 'success'
                })
            );
        } catch (err) {
            this.error = 'Error sending via DocuSign: ' + (err.body ? err.body.message : err.message);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.error,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}
