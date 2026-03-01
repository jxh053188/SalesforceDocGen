/**
 * docGenPdfUtils.js
 * Utility module for handling PDF generation from DocGenPDFEngine iframes.
 */

/**
 * Sends a message to the PDF Engine iframe and returns a Promise that resolves with a Blob
 * containing the generated PDF.
 *
 * @param {HTMLIFrameElement} iframe - The iframe element containing the DocGenPDFEngine.
 * @param {Object} messageData - The data payload to send to the iframe.
 *   - messageData.type {String} - Usually 'generate'
 *   - messageData.html {String} - (Optional) HTML content if generating from HTML.
 *   - messageData.blob {ArrayBuffer} - (Optional) DOCX ArrayBuffer if generating from DOCX.
 *   - messageData.fileName {String} - Name of the output file.
 * @returns {Promise<Blob>} - A Promise that resolves to a PDF Blob.
 */
export function generatePdfFromIframe(iframe, messageData) {
    if (!iframe) {
        return Promise.reject(new Error('PDF Engine iframe not provided.'));
    }

    return new Promise((resolve, reject) => {
        // Define the handler function
        const messageHandler = (event) => {
            // Validate origin if needed (e.g., event.origin === window.location.origin)

            const data = event.data;
            if (data && data.type === 'docgen_success') {
                window.removeEventListener('message', messageHandler);

                // Expecting data.blob to be an ArrayBuffer from the updated engine
                if (data.blob) {
                    try {
                        let pdfBlob;
                        if (data.blob instanceof Blob) {
                            pdfBlob = data.blob;
                        } else {
                            // It's likely an ArrayBuffer
                            pdfBlob = new Blob([data.blob], { type: 'application/pdf' });
                        }

                        console.log('docGenPdfUtils: Successfully received PDF Blob.');
                        resolve(pdfBlob);
                    } catch (err) {
                        reject(new Error('docGenPdfUtils: Failed to convert engine output to Blob: ' + err.message));
                    }
                } else if (data.isDirectDownload) {
                    // For backwards compatibility if any old engine still downloads
                    console.log('docGenPdfUtils: Engine triggered a direct download.');
                    resolve(null);
                } else {
                    reject(new Error('docGenPdfUtils: Success message received but no binary data was found.'));
                }
            } else if (data && data.type === 'docgen_error') {
                window.removeEventListener('message', messageHandler);
                console.error('docGenPdfUtils: PDF Engine reported error:', data.message);
                reject(new Error('PDF Engine Error: ' + data.message));
            }
        };

        // Add the listener
        window.addEventListener('message', messageHandler);

        try {
            // We force the mode to 'returnBuffer' so the engine knows we want the ArrayBuffer back
            const payload = { ...messageData, mode: 'returnBuffer' };
            console.log('docGenPdfUtils: Dispatching generate request to iframe...', payload.fileName);
            iframe.contentWindow.postMessage(payload, '*');
        } catch (e) {
            window.removeEventListener('message', messageHandler);
            reject(new Error('docGenPdfUtils: Failed to post message to iframe: ' + e.message));
        }
    });
}
