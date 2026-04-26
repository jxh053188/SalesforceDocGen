import { generatePdfFromIframe } from 'c/docGenPdfUtils';

export function registerHandlebarsHelpers() {
    window.Handlebars.registerHelper('each', function (context, options) {
        let ret = '';
        let inverse = options.inverse || function () { return ''; };

        // Duck-typing for arrays across Lightning Web Security boundaries
        if (context && typeof context === 'object' && typeof context.length === 'number') {
            if (context.length === 0) {
                return inverse(this);
            }
            for (let i = 0; i < context.length; i++) {
                ret += options.fn(context[i]);
            }
        } else {
            return inverse(this);
        }
        return ret;
    });

    window.Handlebars.registerHelper('ifList', function (...args) {
        const options = args[args.length - 1]; // Handlebars options always last
        let list = args[0];
        const operator = args.length > 2 ? args[1] : ">0";

        // Duck-typing for arrays traversing Lightning Web Security boundary
        // Note: direct length checks fail on LWS Proxies, we must test iteration length or assume array if it's an object with >0 keys
        const isListDef = list && typeof list === 'object' && (Array.isArray(list) || typeof list.length === 'number');

        if (!isListDef) {
            return (typeof options.inverse === 'function') ? options.inverse(this) : '';
        }

        // For LWS Proxies we try to force it to a real array if it acts like one
        if (!Array.isArray(list)) {
            try {
                list = Array.from(list);
            } catch (e) {
                // Fallback if Array.from fails on the proxy
                const temp = [];
                for (let i = 0; i < list.length; i++) temp.push(list[i]);
                list = temp;
            }
        }

        let isMatch = false;

        // "count" indicates we want to filter the list and THEN check length > 0
        if (operator === 'count' && args.length >= 6) {
            const field = args[2];
            const compOp = args[3];
            const compVal = args[4];

            const filtered = list.filter(item => {
                let itemVal = item[field];
                if (itemVal === undefined || itemVal === null) return false;

                // Numeric comparison if possible
                if (!isNaN(itemVal) && !isNaN(compVal)) {
                    if (compOp === '=' || compOp === '==' || compOp === '===') {
                        return Number(itemVal) === Number(compVal);
                    }
                    if (compOp === '!=' || compOp === '!==') {
                        return Number(itemVal) !== Number(compVal);
                    }
                    if (compOp === '>') return Number(itemVal) > Number(compVal);
                    if (compOp === '>=') return Number(itemVal) >= Number(compVal);
                    if (compOp === '<') return Number(itemVal) < Number(compVal);
                    if (compOp === '<=') return Number(itemVal) <= Number(compVal);
                }

                // String default
                let sItem = String(itemVal).trim().toLowerCase();
                let sComp = String(compVal).trim().toLowerCase();
                switch (compOp) {
                    case '=':
                    case '==':
                    case '===':
                        return sItem === sComp;
                    case '!=':
                    case '!==':
                        return sItem !== sComp;
                    default:
                        return false;
                }
            });
            isMatch = (filtered.length > 0);
        } else {
            // Simple length check
            if (operator === '>0' || !operator) {
                isMatch = (list.length > 0);
            } else if (operator === '=0') {
                isMatch = (list.length === 0);
            }
        }

        if (isMatch) {
            return (typeof options.fn === 'function') ? options.fn(this) : '';
        } else {
            return (typeof options.inverse === 'function') ? options.inverse(this) : '';
        }
    });
}

export function base64ToUtf8String(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return new TextDecoder('utf-8').decode(bytes);
}

export function base64ToBinaryUint8Array(base64) {
    const binaryString = atob(base64);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes;
}

export function flattenData(obj) {
    if (!obj || typeof obj !== 'object') return obj;

    // Deep clone arrays to natively bypass LWS Object.keys() / length proxy blocks
    if (Array.isArray(obj)) {
        return obj.map(item => flattenData(item));
    }

    if (obj.hasOwnProperty('totalSize') && obj.hasOwnProperty('records')) {
        return flattenData(obj.records);
    }

    const newObj = {};
    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) {
            if (key === 'attributes') continue;
            newObj[key] = flattenData(obj[key]);
        }
    }
    return newObj;
}

export function configureDocxtemplater(zipBuffer) {
    const zip = new window.PizZip(zipBuffer);
    return new window.docxtemplater(zip, {
        paragraphLoop: true,
        linebreaks: true,
        delimiters: { start: '{', end: '}' },
        nullGetter: () => { return ''; },
        parser: (tag) => {
            return {
                get: (scope) => {
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
}

export function renderDocxTemplate(templateBase64, recordData) {
    const zipBuffer = base64ToBinaryUint8Array(templateBase64);
    const doc = configureDocxtemplater(zipBuffer.buffer);
    doc.render(recordData);
    return doc;
}

export function renderHtmlTemplate(templateBase64, recordData) {
    registerHandlebarsHelpers();
    const htmlString = base64ToUtf8String(templateBase64);
    const template = window.Handlebars.compile(htmlString);
    return template(recordData, {
        allowProtoPropertiesByDefault: false,
        allowProtoMethodsByDefault: false
    });
}

export function generateBlobFromDocx(doc, templateType, outputFormat) {
    const isPPT = templateType === 'PowerPoint';
    const isPDF = outputFormat === 'PDF';
    if (isPPT && !isPDF) {
        return {
            blob: doc.getZip().generate({ type: 'blob' }),
            extension: 'pptx',
            isPDF: false,
            isPPT: true
        };
    } else if (!isPDF) {
        return {
            blob: doc.getZip().generate({ type: 'blob' }),
            extension: 'docx',
            isPDF: false,
            isPPT: false
        };
    } else {
        return {
            blob: doc.getZip().generate({ type: 'arraybuffer' }),
            extension: 'pdf',
            isPDF: true,
            isPPT: isPPT
        };
    }
}

export function orchestratePdfGeneration(iframe, messageData) {
    const payload = { ...messageData, mode: 'returnBuffer' };
    return generatePdfFromIframe(iframe, payload);
}

export function downloadBlob(blob, fileName) {
    if (typeof window.saveAs !== 'function') {
        throw new Error('FileSaver library (window.saveAs) is not available. Ensure the static resource is loaded.');
    }
    window.saveAs(blob, fileName);
}
