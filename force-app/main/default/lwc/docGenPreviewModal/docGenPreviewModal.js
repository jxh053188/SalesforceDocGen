import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class DocGenPreviewModal extends LightningModal {
    @api pdfBlob;
    @api fileName = 'document.pdf';

    pdfUrl;

    connectedCallback() {
        if (this.pdfBlob) {
            try {
                this.pdfUrl = URL.createObjectURL(this.pdfBlob);
            } catch (e) {
                this.dispatchEvent(new CustomEvent('error', { detail: { message: 'Unable to prepare PDF preview.', error: e } }));
            }
        }
    }

    disconnectedCallback() {
        if (this.pdfUrl) {
            URL.revokeObjectURL(this.pdfUrl);
            this.pdfUrl = null;
        }
    }

    handleClose() {
        this.close('closed');
    }

    handleDownload() {
        if (!this.pdfBlob) return;

        // Create a temporary link to trigger the download of the blob
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
}
