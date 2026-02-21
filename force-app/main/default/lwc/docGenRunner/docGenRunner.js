import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplatesForObject from '@salesforce/apex/DocGenController.getTemplatesForObject';
import generateDocumentData from '@salesforce/apex/DocGenController.generateDocumentData';
import PIZZIP_JS from '@salesforce/resourceUrl/pizzip';
import DOCXTEMPLATER_JS from '@salesforce/resourceUrl/docxtemplater';
import FILESAVER_JS from '@salesforce/resourceUrl/filesaver';
import DOCGEN_ENGINE from '@salesforce/resourceUrl/DocGenEngine';

export default class DocGenRunner extends LightningElement {
    @api recordId;
    @api objectApiName;
    
    // Use VF Page for PDF
    get engineUrl() {
        return '/apex/DocGenPDFEngine';
    }
    
    @track templateOptions = [];
    @track selectedTemplateId;
    
    isLoading = false;
    
    isLoading = false;
    error;
    librariesLoaded = false;
    _librariesPromise;

    @wire(getTemplatesForObject, { objectApiName: '$objectApiName' })
    wiredTemplates({ error, data }) {
        if (data) {
            this.templateOptions = data.map(t => ({ label: t.Name, value: t.Id }));
            this.error = undefined;
        } else if (error) {
            this.error = 'Error fetching templates';
            this.templateOptions = [];
        }
    }

    renderedCallback() {
        if (this.librariesLoaded) return;
        this.librariesLoaded = true;

        const loadPizZip = loadScript(this, PIZZIP_JS)
            .then(() => console.log('PizZip loaded', !!window.PizZip))
            .catch(e => { console.error('Failed to load PizZip', e); throw e; });
            
        const loadDocxtemplater = loadScript(this, DOCXTEMPLATER_JS)
            .then(() => console.log('Docxtemplater loaded', !!window.docxtemplater))
            .catch(e => { console.error('Failed to load Docxtemplater', e); throw e; });
            
        const loadFileSaver = loadScript(this, FILESAVER_JS);

        this._librariesPromise = Promise.all([
            loadPizZip,
            loadDocxtemplater,
            loadFileSaver
        ])
        .then(() => {
             console.log('All libraries loaded successfully');
        })
        .catch(error => {
            console.error('Library load error:', error);
            // Don't set this.error yet to avoid scaring user before they click 'Generate'
            // But we log it.
        });
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.error = null; // Clear any previous errors
    }

    // Standard LWC Getters
    get isGenerateDisabled() {
        return !this.selectedTemplateId || this.isLoading;
    }

    async generateDocument() {
        this.isLoading = true;
        this.error = null;
        
        try {
            console.log('Starting generation...');
            
            // 0. Ensure Libraries are loaded
            if (this._librariesPromise) {
                try {
                    await this._librariesPromise;
                } catch (loadError) {
                    this.error = 'Libraries failed to load properly. Check browser console.';
                    this.isLoading = false;
                    return;
                }
            } else {
                 this.error = 'Libraries failed to initialize.';
                 this.isLoading = false;
                 return;
            }

            // 1. Explicit Check for Global Objects
            if (!window.PizZip) {
                this.error = 'PizZip library not loaded. Ensure static resource "pizzip" is valid.';
                this.isLoading = false;
                return;
            }
            if (!window.docxtemplater) {
                 this.error = 'docxtemplater library not loaded. Ensure static resource "docxtemplater" is valid.';
                 this.isLoading = false;
                 return;
            }
            
            console.log('Libraries verified. Fetching data...');

            // 1. Get Data and Template Content
            const result = await generateDocumentData({ 
                templateId: this.selectedTemplateId, 
                recordId: this.recordId 
            });
            
            const templateData = result.templateFile; // Base64
            const templateType = result.templateType;

            console.log('Data received. Sanitizing...');
            // LWS Check: Scrub data completely to remove any Proxies
            let recordData;
            try {
                const rawData = JSON.parse(JSON.stringify(result.data));
                recordData = this.flattenData(rawData);
                console.log('Final Record Data Keys:', Object.keys(recordData));
                if (recordData.QuoteLineItems) {
                    console.log('QuoteLineItems Found:', Array.isArray(recordData.QuoteLineItems) ? recordData.QuoteLineItems.length : 'Not an Array');
                } else {
                    console.log('QuoteLineItems MISSING in flattened data.');
                }
            } catch (jsonErr) {
                 throw new Error('Data sanitization failed: ' + jsonErr.message);
            }

            // 2. Load Zip
            const binaryString = atob(templateData);
            const len = binaryString.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            
            let zip;
            try {
                console.log('Initializing PizZip...');
                // PizZip
                zip = new window.PizZip(bytes.buffer);
            } catch (zipErr) {
                console.error('PizZip Init Error', zipErr);
                throw new Error('PizZip initialization failed: ' + zipErr.message);
            }
            
            let doc;
            try {
                console.log('Initializing Docxtemplater...');
                // 3. Docxtemplater
                doc = new window.docxtemplater(zip, {
                    paragraphLoop: true,
                    linebreaks: true,
                    delimiters: {start: '{', end: '}'},
                    nullGetter: () => { return ""; },
                    parser: (tag) => {
                        return {
                            get: (scope, context) => {
                                if (tag === '.') return scope;
                                const keys = tag.split('.');
                                let value = scope;
                                for (let i = 0; i < keys.length; i++) {
                                    if (value === undefined || value === null) return '';
                                    value = value[keys[i]];
                                }
                                return value;
                            }
                        };
                    }
                });
            } catch (docErr) {
                console.error('Docxtemplater Init Error', docErr);
                 throw new Error('Docxtemplater initialization failed: ' + docErr.message);
            }
            
            try {
                console.log('Rendering Document...');
                // 4. Render
                doc.render(recordData);
            } catch (renderErr) {
                console.error('Render Error', renderErr);
                 throw new Error('Template Rendering failed (LWS Blocked?): ' + renderErr.message);
            }
            
            // 5. Output
            const isPPT = templateType === 'PowerPoint';
            const mimeType = isPPT ? 'application/vnd.openxmlformats-officedocument.presentationml.presentation' : 'application/pdf';
                
            const outZip = doc.getZip().generate({
                type: 'uint8array'
            });
            
            const baseName = recordData.Name || recordData.QuoteNumber || recordData.CaseNumber || recordData.Subject || 'Document';

            if (isPPT) {
                 // PPTX: Download directly
                 const out = new Blob([outZip], { type: mimeType });
                 window.saveAs(out, baseName + '.pptx');
                 this.showToast('Success', 'PowerPoint Generated', 'success');
            } else {
                 // DOCX -> High Fidelity PDF (Sandboxed)
                 this.showToast('Info', 'Preparing PDF...', 'info');
                 
                 // Get ArrayBuffer for docx-preview
                 const docxBuffer = doc.getZip().generate({
                    type: 'arraybuffer'
                 });

                 // Send to Sandboxed Engine (iframe)
                 const iframe = this.template.querySelector('iframe');
                 if (!iframe) {
                     throw new Error('PDF Engine not loaded. Please refresh.');
                 }
                 
                 iframe.contentWindow.postMessage({
                     type: 'generate',
                     blob: docxBuffer, // Send binary directly
                     fileName: baseName
                 }, '*'); 
            }

        } catch (e) {
            console.error(e);
            let msg = e.message || e;
            if (typeof e === 'object' && e !== null) {
                msg = JSON.stringify(e, Object.getOwnPropertyNames(e));
            }
            this.error = 'Generation Error: ' + msg;
            
            if (e.properties && e.properties.errors) {
                 const errorMessages = e.properties.errors.map(err => err.properties.explanation).join('\n');
                 this.error += '\n' + errorMessages;
            }
        } finally {
            this.isLoading = false;
        }
    }
    
    // Listen for Engine Responses
    connectedCallback() {
        window.addEventListener('message', this.handleMessage);
    }
    
    disconnectedCallback() {
        window.removeEventListener('message', this.handleMessage);
    }
    
    handleMessage = (event) => {
        if (event.data.type === 'docgen_success') {
            this.showToast('Success', 'PDF Generated and Downloaded', 'success');
            this.isLoading = false;
        } else if (event.data.type === 'docgen_error') {
            this.error = 'PDF Engine Error: ' + event.data.message;
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    /**
     * Recursively flattens Salesforce subquery results ({ totalSize, records: [] }) 
     * into simple arrays for docxtemplater.
     */
    flattenData(obj) {
        if (!obj || typeof obj !== 'object') {
            return obj;
        }
        
        // If it's an array, map over it
        if (Array.isArray(obj)) {
            return obj.map(item => this.flattenData(item));
        }

        // If it's a subquery result object (has done, totalSize, records)
        if (obj.hasOwnProperty('totalSize') && obj.hasOwnProperty('records') && Array.isArray(obj.records)) {
             return this.flattenData(obj.records);
        }

        // Otherwise, it's a standard object. Iterate keys.
        const newObj = {};
        for (const key in obj) {
            if (Object.prototype.hasOwnProperty.call(obj, key)) {
                // Skip attributes
                if (key === 'attributes') continue; 
                newObj[key] = this.flattenData(obj[key]);
            }
        }
        return newObj;
    }
}