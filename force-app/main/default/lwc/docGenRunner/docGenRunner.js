import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplatesForObject from '@salesforce/apex/DocGenController.getTemplatesForObject';
import generateDocumentData from '@salesforce/apex/DocGenController.generateDocumentData';
import saveGeneratedDocument from '@salesforce/apex/DocGenController.saveGeneratedDocument';
import PIZZIP_JS from '@salesforce/resourceUrl/pizzip';
import DOCXTEMPLATER_JS from '@salesforce/resourceUrl/docxtemplater';
import FILESAVER_JS from '@salesforce/resourceUrl/filesaver';
import HANDLEBARS_JS from '@salesforce/resourceUrl/handlebars';
import DocGenPreviewModal from 'c/docGenPreviewModal';
import { flattenData, renderDocxTemplate, renderHtmlTemplate, generateBlobFromDocx, orchestratePdfGeneration, downloadBlob } from 'c/docGenEngine';

export default class DocGenRunner extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track templateOptions = [];
    @track selectedTemplateId;
    @track outputMode = 'download';
    @track templateOutputFormat = 'Document';

    isLoading = false;
    error;
    librariesLoaded = false;
    _librariesPromise;
    _templateData = []; // Store raw template metadata

    get engineUrl() {
        return '/apex/DocGenPDFEngine';
    }

    get outputOptions() {
        const formatLabel = this.templateOutputFormat || 'Document';
        return [
            { label: `Download ${formatLabel}`, value: 'download' },
            { label: `Save to Record (${formatLabel})`, value: 'save' }
        ];
    }

    @wire(getTemplatesForObject, { objectApiName: '$objectApiName' })
    wiredTemplates({ error, data }) {
        if (data) {
            this._templateData = data;
            this.templateOptions = data.map(t => ({ label: t.Name, value: t.Id }));
            this.error = undefined;
        } else if (error) {
            this.error = 'Error fetching templates: ' + (error.body ? error.body.message : error.message);
            this.templateOptions = [];
        }
    }

    renderedCallback() {
        if (this.librariesLoaded) return;
        this.librariesLoaded = true;

        const loadPizZip = loadScript(this, PIZZIP_JS)
            .catch(e => { throw e; });

        const loadDocxtemplater = loadScript(this, DOCXTEMPLATER_JS)
            .catch(e => { throw e; });

        const loadFileSaver = loadScript(this, FILESAVER_JS);
        const loadHandlebars = loadScript(this, HANDLEBARS_JS)
            .catch(e => { throw e; });

        this._librariesPromise = Promise.all([
            loadPizZip,
            loadDocxtemplater,
            loadFileSaver,
            loadHandlebars
        ]);
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.error = null;

        // Update the UI labels immediately based on selected template
        const selected = this._templateData.find(t => t.Id === this.selectedTemplateId);
        if (selected) {
            this.templateOutputFormat = selected.Output_Format__c || 'Document';
        }
    }

    handleOutputModeChange(event) {
        this.outputMode = event.detail.value;
    }

    get isGenerateDisabled() {
        return !this.selectedTemplateId || this.isLoading;
    }

    async generateDocument() {
        await this._runGenerationFlow(false);
    }

    async previewDocument() {
        await this._runGenerationFlow(true);
    }

    async _runGenerationFlow(isPreview) {
        this.isLoading = true;
        this.error = null;

        try {
            // 0. Ensure Libraries are loaded
            if (this._librariesPromise) {
                await this._librariesPromise;
            } else {
                throw new Error('Libraries failed to initialize.');
            }

            // 1. Get Data and Template Content
            const result = await generateDocumentData({
                templateId: this.selectedTemplateId,
                recordId: this.recordId
            });

            if (!result || !result.templateFile) {
                throw new Error('Template file content is empty or could not be retrieved.');
            }

            const templateData = result.templateFile;
            const templateType = result.templateType;
            this.templateOutputFormat = result.outputFormat || 'Document';
            let recordData = flattenData(JSON.parse(JSON.stringify(result.data)));
            const baseName = recordData.Name || recordData.QuoteNumber || recordData.CaseNumber || recordData.Subject || 'Document';

            if (templateType === 'HTML') {
                if (!window.Handlebars) {
                    throw new Error('Handlebars library not loaded.');
                }
                const renderedHtml = renderHtmlTemplate(templateData, recordData);
                if (this.templateOutputFormat === 'PDF') {
                    this.showToast('Info', 'Generating PDF...', 'info');
                    const iframe = this.template.querySelector('iframe');
                    if (!iframe) throw new Error('PDF Engine iframe not found.');

                    const messageData = {
                        type: 'generate',
                        html: renderedHtml,
                        fileName: baseName,
                        mode: this.outputMode
                    };

                    const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                    await this._handlePdfBlobResult(pdfBlob, baseName, isPreview);

                } else {
                    // Use application/octet-stream so FileSaver/LWS accepts the blob (filename .html still opens as HTML)
                    const blob = new Blob([renderedHtml], { type: 'application/octet-stream' });
                    if (this.outputMode === 'save' && !isPreview) {
                        await this.saveToSalesforce(baseName, blob, 'html');
                    } else if (isPreview) {
                        this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                        downloadBlob(blob, baseName + '.html');
                        this.isLoading = false;
                    } else {
                        downloadBlob(blob, baseName + '.html');
                        this.showToast('Success', 'HTML document downloaded.', 'success');
                        this.isLoading = false;
                    }
                }
                return;
            }

            if (!window.PizZip || !window.docxtemplater) {
                throw new Error('Required libraries (PizZip/docxtemplater) not found in window scope.');
            }
            const doc = renderDocxTemplate(templateData, recordData);
            const { blob, extension, isPDF, isPPT } = generateBlobFromDocx(doc, templateType, this.templateOutputFormat);

            if (isPPT) {
                if (this.outputMode === 'save' && !isPreview) {
                    await this.saveToSalesforce(baseName, blob, 'pptx');
                } else if (isPreview) {
                    this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                    downloadBlob(blob, baseName + '.pptx');
                    this.isLoading = false;
                } else {
                    downloadBlob(blob, baseName + '.pptx');
                    this.showToast('Success', 'PowerPoint downloaded.', 'success');
                    this.isLoading = false;
                }
            } else if (!isPDF) {
                if (this.outputMode === 'save' && !isPreview) {
                    await this.saveToSalesforce(baseName, blob, 'docx');
                } else if (isPreview) {
                    this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                    downloadBlob(blob, baseName + '.docx');
                    this.isLoading = false;
                } else {
                    downloadBlob(blob, baseName + '.docx');
                    this.showToast('Success', 'Word document downloaded.', 'success');
                    this.isLoading = false;
                }
            } else {
                this.showToast('Info', 'Generating PDF...', 'info');
                const iframe = this.template.querySelector('iframe');
                if (!iframe) throw new Error('PDF Engine iframe not found.');

                const messageData = {
                    type: 'generate',
                    blob: blob,
                    fileName: baseName,
                    mode: this.outputMode
                };

                const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                await this._handlePdfBlobResult(pdfBlob, baseName, isPreview);
            }

        } catch (e) {
            let msg = 'Unknown error during generation';

            if (e.message) {
                msg = e.message;
            } else if (typeof e === 'string') {
                msg = e;
            } else {
                try {
                    msg = JSON.stringify(e);
                } catch (jsonErr) {
                    msg = 'Critical failure (could not stringify error)';
                }
            }

            if (e.properties && e.properties.errors instanceof Array) {
                msg += ': ' + e.properties.errors.map(err => err.properties.explanation).join(', ');
            }
            this.error = 'Generation Error: ' + msg;
            this.isLoading = false;
        }
    }

    async _handlePdfBlobResult(pdfBlob, baseName, isPreview) {
        if (!pdfBlob) {
            this.isLoading = false;
            return;
        }

        if (isPreview) {
            this.isLoading = false;
            await DocGenPreviewModal.open({
                size: 'large',
                pdfBlob: pdfBlob,
                fileName: baseName + '.pdf'
            });
        } else if (this.outputMode === 'save') {
            await this.saveToSalesforce(baseName, pdfBlob, 'pdf');
        } else {
            downloadBlob(pdfBlob, baseName + '.pdf');
            this.showToast('Success', 'Document Generated successfully.', 'success');
            this.isLoading = false;
        }
    }

    connectedCallback() {
        window.addEventListener('message', this.handleMessage);
    }

    disconnectedCallback() {
        window.removeEventListener('message', this.handleMessage);
    }

    handleMessage = async (event) => {
        if (event.origin !== window.location.origin) return;
        if (!event.data) return;
        if (event.data.type === 'docgen_success') {
            if (this.outputMode === 'save' && event.data.blob) {
                await this.saveToSalesforce(event.data.fileName, event.data.blob, 'pdf');
            } else {
                this.showToast('Success', 'Document Generated successfully.', 'success');
                this.isLoading = false;
            }
        } else if (event.data.type === 'docgen_error') {
            this.error = 'PDF Engine Error: ' + event.data.message;
            this.isLoading = false;
        }
    }

    async saveToSalesforce(fileName, blob, extension) {
        try {
            this.showToast('Info', 'Saving to Record...', 'info');

            const base64 = await this.blobToBase64(blob);
            if (!base64) throw new Error('Failed to convert file to binary data.');

            await saveGeneratedDocument({
                recordId: this.recordId,
                fileName: fileName,
                base64Data: base64,
                extension: extension
            });
            this.showToast('Success', `${extension.toUpperCase()} saved to record.`, 'success');
        } catch (e) {
            this.error = 'Save Error: ' + (e.body ? e.body.message : (e.message || e));
            this.showToast('Error', 'Save failed. Check error message.', 'error');
        } finally {
            this.isLoading = false;
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
            reader.onerror = (e) => {
                reject(new Error('Error reading file data.'));
            };

            if (blob instanceof ArrayBuffer) {
                reader.readAsDataURL(new Blob([blob]));
            } else if (blob instanceof Blob) {
                reader.readAsDataURL(blob);
            } else {
                // Try treating it as a buffer if it's an TypedArray
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