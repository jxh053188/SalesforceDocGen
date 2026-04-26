import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveGeneratedDocument from '@salesforce/apex/DocGenController.saveGeneratedDocument';
import getRelatedContacts from '@salesforce/apex/DocGenDocuSignController.getRelatedContacts';
import generateAndSendWithRecipients from '@salesforce/apex/DocGenDocuSignController.generateAndSendWithRecipients';

export default class DocGenPreviewModal extends LightningModal {
    @api pdfBlob;
    @api fileName = 'document.pdf';
    @api recordId;
    @api templateId;
    @api allowDocuSign = false;
    @api signerCount = 1;
    @api allowSave = false;
    @api allowDownload = false;

    pdfUrl;
    showSendForm = false;
    emailSubject = '';
    contactOptions = [];
    selectedContactIds = [];
    isSending = false;
    isSaving = false;

    connectedCallback() {
        if (this.pdfBlob) {
            try {
                this.pdfUrl = URL.createObjectURL(this.pdfBlob);
            } catch (e) {
                this.dispatchEvent(new CustomEvent('error', { detail: { message: 'Unable to prepare PDF preview.', error: e } }));
            }
        }
        this.selectedContactIds = new Array(this.signerCount).fill('');
    }

    disconnectedCallback() {
        if (this.pdfUrl) {
            URL.revokeObjectURL(this.pdfUrl);
            this.pdfUrl = null;
        }
    }

    @wire(getRelatedContacts, { recordId: '$recordId' })
    wiredContacts({ error, data }) {
        if (data) {
            this.contactOptions = [
                { label: '-- Select Contact --', value: '' },
                ...data.map(c => ({ label: c.Name + ' (' + c.Email + ')', value: c.Id }))
            ];
        } else if (error) {
            this.contactOptions = [{ label: '-- Select Contact --', value: '' }];
        }
    }

    handleClose() {
        this.close('closed');
    }

    handleDownload() {
        if (!this.pdfBlob) return;
        const link = document.createElement('a');
        link.href = this.pdfUrl;
        link.download = this.fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    get isDownloadDisabled() {
        return !this.pdfBlob || !this.pdfUrl;
    }

    get signerPickers() {
        const pickers = [];
        for (let i = 0; i < this.signerCount; i++) {
            pickers.push({
                index: i,
                label: 'Signer ' + (i + 1),
                value: this.selectedContactIds[i] || ''
            });
        }
        return pickers;
    }

    async handleSaveToRecord() {
        if (!this.pdfBlob || !this.recordId) return;
        this.isSaving = true;
        try {
            const base64 = await this.blobToBase64(this.pdfBlob);
            if (!base64) throw new Error('Failed to convert file to binary data.');

            const baseName = (this.fileName || 'document').replace(/\.pdf$/i, '');
            await saveGeneratedDocument({
                recordId: this.recordId,
                fileName: baseName,
                base64Data: base64,
                extension: 'pdf'
            });
            this.showToast('Success', 'PDF saved to record.', 'success');
            this.close('saved');
        } catch (e) {
            this.showToast('Error', 'Save failed: ' + (e.body ? e.body.message : e.message), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleSendDocuSign() {
        this.showSendForm = !this.showSendForm;
    }

    handleEmailSubjectChange(event) {
        this.emailSubject = event.detail.value;
    }

    handleRecipientChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.selectedContactIds[index] = event.detail.value;
    }

    async handleConfirmSend() {
        for (let i = 0; i < this.signerCount; i++) {
            if (!this.selectedContactIds[i]) {
                this.showToast('Error', 'Please select a contact for Signer ' + (i + 1) + '.', 'error');
                return;
            }
        }

        this.isSending = true;
        try {
            const recipientInputs = this.selectedContactIds.map((contactId, index) => ({
                contactId: contactId,
                routingOrder: index + 1,
                role: 'Signer ' + (index + 1)
            }));

            const result = await generateAndSendWithRecipients({
                templateId: this.templateId,
                recordId: this.recordId,
                recipientInputs: recipientInputs,
                emailSubject: this.emailSubject,
                envelopeConfigurationId: null
            });

            this.showToast('Success', 'DocuSign envelope sent. ID: ' + result.envelopeId, 'success');
            this.close('sent');
        } catch (e) {
            this.showToast('Error', 'Send failed: ' + (e.body ? e.body.message : e.message), 'error');
        } finally {
            this.isSending = false;
        }
    }

    blobToBase64(blob) {
        return new Promise((resolve, reject) => {
            if (!blob) {
                reject(new Error('Input blob is null or undefined.'));
                return;
            }
            const reader = new FileReader();
            reader.onloadend = () => {
                const base64String = reader.result.split(',')[1];
                resolve(base64String);
            };
            reader.onerror = () => {
                reject(new Error('Error reading file data.'));
            };
            if (blob instanceof ArrayBuffer) {
                reader.readAsDataURL(new Blob([blob]));
            } else if (blob instanceof Blob) {
                reader.readAsDataURL(blob);
            } else {
                try {
                    reader.readAsDataURL(new Blob([blob]));
                } catch (err) {
                    reject(new Error('Input is not a valid Blob or ArrayBuffer.'));
                }
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
