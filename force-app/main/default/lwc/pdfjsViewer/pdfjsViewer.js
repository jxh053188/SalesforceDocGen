import { LightningElement, api, track } from 'lwc';
import pdfjs from '@salesforce/resourceUrl/pdfjs';

export default class PdfjsViewer extends LightningElement {
    _pdfBytes;

    @api
    get pdfBytes() {
        return this._pdfBytes;
    }

    set pdfBytes(value) {
        console.log('📥 pdfBytes setter called with:', value ? `${value.length || value.byteLength || 'unknown'} bytes` : 'null/undefined');
        this._pdfBytes = value;

        // Trigger rendering if component is ready
        if (this.pdfjsLoaded && value && !this._initialized) {
            console.log('🚀 pdfBytes set - triggering immediate render');
            this._currentPdfBytes = value;
            this.loadAndRenderPdf();
        }
    }
    @api fileName = 'document.pdf';
    @track showViewer = false;
    @track viewerURL;

    // Accept either raw Uint8Array/Blob (pdfBytes) or a direct Object URL (pdfUrl)
    _pdfUrl;

    @api
    get pdfUrl() {
        return this._pdfUrl;
    }

    set pdfUrl(value) {
        console.log('📥 pdfUrl setter called with:', value);
        this._pdfUrl = value;

        if (value) {
            this.viewerURL = pdfjs + '/pdfjs/web/viewer.html?file=' + encodeURIComponent(value);
            this.showViewer = true;
        }
    }

    // Track if we internally generated a blob URL that needs cleanup
    _internalObjectUrl;

    connectedCallback() {
        if (!this._pdfUrl) {
            // Default blank viewer if no URL provided yet
            this.viewerURL = pdfjs + '/pdfjs/web/viewer.html';
        }
    }

    renderedCallback() {
        // showViewer toggled via prop
    }

    testPdfViewer(event) {
        console.log('PDF viewer initiated by iframe onload event.');

        // 1. Get the iframe element using the LWC template method
        // NOTE: If you are using 'onload' in your HTML, the 'event.target' *is* the iframe.
        // However, sticking to 'this.template.querySelector' is generally safer for LWC context.
        // Since you are using 'this.querySelector('iframe');', you must ensure that 'this' 
        // is correctly scoped to the component instance, which it usually is. 
        // Let's switch to the standard LWC pattern for robustness.
        const iframe = this.template.querySelector('iframe');

        if (!iframe) {
            console.error('❌ Iframe element not found in template query.');
            return;
        }

        // 2. Store the element reference immediately
        this.iframeElement = iframe;
        this.hasRenderedIframe = true;
        console.log('✅ Iframe element captured.');
        console.log('iframeElement:', this.iframeElement);

        // 3. REMOVE the 7-SECOND TIMEOUT. The onload event is our timing trigger.
        // Use a minimal timeout (0ms) to ensure the current JavaScript stack completes 
        // and the browser has fully instantiated the 'contentWindow'.
        setTimeout(async () => {
            try {
                // Re-check for safety, though it should exist now
                if (!this.iframeElement || !this.iframeElement.contentWindow) {
                    console.error('❌ Iframe contentWindow is not yet available.');
                    return;
                }

                if (this.pdfUrl) {
                    console.log('✅ PDF URL provided via query string, skipping postMessage.');
                } else if (this.pdfBytes) {
                    const conversionResult = await this.convertPdfDataToBase64AndBlob();

                    if (!conversionResult || !conversionResult.base64String) {
                        console.error('❌ PDF data conversion failed.');
                        return;
                    }

                    // Note: If using PDF.js we can often just pass the base64 or object URL
                    // Since it has historically used base64 in this component, we keep that for pdfBytes fallback
                    const dataUrl = `${conversionResult.base64String}`;
                    this.sendDataToIframe(dataUrl);
                } else {
                    console.warn('⚠️ No PDF Data or URL provided to viewer yet.');
                }
            } catch (e) {
                console.error('❌ Error in PDF Viewer process:', e);
            }
        }, 0);
    }

    sendDataToIframe(data) {
        if (!this.iframeElement || !this.iframeElement.contentWindow) return;
        this.iframeElement.contentWindow.postMessage(data, "*");
        console.log('✅ PostMessage sent to iframe with PDF data.');
    }

    disconnectedCallback() {
        if (this._internalObjectUrl) {
            URL.revokeObjectURL(this._internalObjectUrl);
            this._internalObjectUrl = null;
        }
    }
    async convertPdfDataToBase64AndBlob() {
        // 1. Check for data availability
        if (!this.pdfBytes || !(this.pdfBytes instanceof Uint8Array)) {
            console.error('❌ PDF data (this.pdfBytes) is not available or is not a Uint8Array.');
            return null;
        }

        const uint8array = this.pdfBytes;

        // --- Step 1: Convert Uint8Array to Base64 String ---
        // The most modern and reliable way is to use the FileReader API via a Promise.
        const base64String = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const dataURL = reader.result;
                // The result is a Data URL (e.g., "data:application/pdf;base64,BASE64_STRING")
                // We only want the BASE64_STRING part.
                // The split function is safe because a Data URL format is guaranteed.
                const base64 = dataURL.split(',')[1];
                resolve(base64);
            };
            reader.onerror = (error) => {
                console.error('FileReader error during Base64 conversion:', error);
                reject(error);
            };

            // Create a temporary Blob to use with FileReader
            const tempBlob = new Blob([uint8array], { type: 'application/octet-stream' });
            reader.readAsDataURL(tempBlob);
        });

        // --- Step 2: Create the PDF Blob ---
        // The Blob object represents the raw file data for downloads, uploads, etc.
        const pdfBlob = new Blob(
            [uint8array],
            { type: 'application/pdf' } // IMPORTANT: Set the correct MIME type for PDF
        );

        console.log('✅ PDF data successfully converted to Base64 string and PDF Blob.');

        return {
            base64String: base64String,
            pdfBlob: pdfBlob
        };
    }
}
