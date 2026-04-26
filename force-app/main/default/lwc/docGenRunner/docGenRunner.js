import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplatesForObject from '@salesforce/apex/DocGenController.getTemplatesForObject';
import generateDocumentData from '@salesforce/apex/DocGenController.generateDocumentData';
import PIZZIP_JS from '@salesforce/resourceUrl/pizzip';
import DOCXTEMPLATER_JS from '@salesforce/resourceUrl/docxtemplater';
import FILESAVER_JS from '@salesforce/resourceUrl/filesaver';
import HANDLEBARS_JS from '@salesforce/resourceUrl/handlebars';
import DocGenPreviewModal from 'c/docGenPreviewModal';
import { flattenData, renderDocxTemplate, renderHtmlTemplate, generateBlobFromDocx, orchestratePdfGeneration } from 'c/docGenEngine';

export default class DocGenRunner extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track templateOptions = [];
    @track selectedTemplateId;
    @track templateOutputFormat = 'Document';
    @track selectedTemplateHasEnvelopeConfig = false;
    @track selectedTemplateSignerCount = 1;

    isLoading = false;
    error;
    librariesLoaded = false;
    _librariesPromise;
    _templateData = [];

    get engineUrl() {
        return '/apex/DocGenPDFEngine';
    }

    get isPreviewDisabled() {
        return !this.selectedTemplateId || this.isLoading;
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

        const selected = this._templateData.find(t => t.Id === this.selectedTemplateId);
        if (selected) {
            this.templateOutputFormat = selected.Output_Format__c || 'Document';
            this.selectedTemplateHasEnvelopeConfig = !!selected.DocuSign_Envelope_Configuration__c;
            this.selectedTemplateSignerCount = selected.DocuSign_Signer_Count__c || 1;
        }
    }

    async previewDocument() {
        await this._runGenerationFlow(true);
    }

    async _runGenerationFlow(isPreview) {
        this.isLoading = true;
        this.error = null;

        try {
            if (this._librariesPromise) {
                await this._librariesPromise;
            } else {
                throw new Error('Libraries failed to initialize.');
            }

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

                if (isPreview) {
                    this.showToast('Info', 'Generating PDF Preview...', 'info');
                    const iframe = this.template.querySelector('iframe');
                    if (!iframe) throw new Error('PDF Engine iframe not found.');
                    const messageData = {
                        type: 'generate',
                        html: renderedHtml,
                        fileName: baseName
                    };
                    try {
                        const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                        await this._handlePdfBlobResult(pdfBlob, baseName, true);
                    } catch (pdfErr) {
                        console.error('[docGenRunner] PDF preview failed:', pdfErr);
                        throw pdfErr;
                    }
                }
                return;
            }

            if (!window.PizZip || !window.docxtemplater) {
                throw new Error('Required libraries (PizZip/docxtemplater) not found in window scope.');
            }
            const doc = renderDocxTemplate(templateData, recordData);

            if (isPreview) {
                const pdfGenResult = generateBlobFromDocx(doc, templateType, 'PDF');
                this.showToast('Info', 'Generating PDF Preview...', 'info');
                const iframe = this.template.querySelector('iframe');
                if (!iframe) throw new Error('PDF Engine iframe not found.');
                const messageData = {
                    type: 'generate',
                    blob: pdfGenResult.blob,
                    fileName: baseName
                };
                try {
                    const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                    await this._handlePdfBlobResult(pdfBlob, baseName, true);
                } catch (pdfErr) {
                    console.error('[docGenRunner] PDF preview failed:', pdfErr);
                    throw pdfErr;
                }
                return;
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
                fileName: baseName + '.pdf',
                recordId: this.recordId,
                templateId: this.selectedTemplateId,
                allowDocuSign: this.selectedTemplateHasEnvelopeConfig,
                signerCount: this.selectedTemplateSignerCount || 1,
                allowSave: true,
                allowDownload: true
            });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
