import { LightningElement, track, wire } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';

// Apex
import getAllTemplates from '@salesforce/apex/DocGenController.getAllTemplates';
import deleteTemplate from '@salesforce/apex/DocGenController.deleteTemplate';
import saveTemplate from '@salesforce/apex/DocGenController.saveTemplate';
import getTemplateVersions from '@salesforce/apex/DocGenController.getTemplateVersions';
import generateDocumentData from '@salesforce/apex/DocGenController.generateDocumentData';
// import createSampleData ... removed
import activateVersion from '@salesforce/apex/DocGenController.activateVersion';

// Schema
import DOCGEN_TEMPLATE_OBJECT from '@salesforce/schema/DocGen_Template__c';
import ID_FIELD from '@salesforce/schema/DocGen_Template__c.Id';
import NAME_FIELD from '@salesforce/schema/DocGen_Template__c.Name';
import CATEGORY_FIELD from '@salesforce/schema/DocGen_Template__c.Category__c';
import TYPE_FIELD from '@salesforce/schema/DocGen_Template__c.Type__c';
import BASE_OBJECT_FIELD from '@salesforce/schema/DocGen_Template__c.Base_Object_API__c';
import QUERY_CONFIG_FIELD from '@salesforce/schema/DocGen_Template__c.Query_Config__c';
import QUERY_METADATA_FIELD from '@salesforce/schema/DocGen_Template__c.Query_Metadata__c';
import DESC_FIELD from '@salesforce/schema/DocGen_Template__c.Description__c';

// Static Resources
import PIZZIP_JS from '@salesforce/resourceUrl/pizzip';
import DOCXTEMPLATER_JS from '@salesforce/resourceUrl/docxtemplater';
import FILESAVER_JS from '@salesforce/resourceUrl/filesaver';
import HANDLEBARS_JS from '@salesforce/resourceUrl/handlebars';
import DocGenPreviewModal from 'c/docGenPreviewModal';
import { flattenData, renderDocxTemplate, renderHtmlTemplate, generateBlobFromDocx, orchestratePdfGeneration, downloadBlob } from 'c/docGenEngine';

const COLUMNS = [
    { label: 'Category', fieldName: 'Category__c', initialWidth: 150 },
    { label: 'Name', fieldName: 'Name' },
    { label: 'Type', fieldName: 'Type__c', initialWidth: 100 },
    { label: 'Base Object', fieldName: 'Base_Object_API__c' },
    { label: 'Description', fieldName: 'Description__c' },
    {
        type: 'action', typeAttributes: {
            rowActions: [
                { label: 'View', name: 'view' },
                { label: 'Edit', name: 'edit' },
                { label: 'Share', name: 'share' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

const VERSION_COLUMNS = [
    { label: 'Ver', fieldName: 'VersionNumber', initialWidth: 70 },
    {
        label: 'Active', fieldName: 'isActiveLabel', initialWidth: 70, cellAttributes: {
            class: { fieldName: 'activeClass' }
        }
    },
    {
        label: 'Created Date', fieldName: 'CreatedDate', type: 'date', typeAttributes: {
            year: 'numeric', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit'
        }
    },
    { label: 'Created By', fieldName: 'CreatedByName' },
    {
        type: 'button', initialWidth: 100, typeAttributes: {
            label: 'Preview', name: 'preview', variant: 'neutral', iconName: 'utility:preview'
        }
    },
    {
        type: 'button', typeAttributes: {
            label: 'Activate', name: 'restore', title: 'Restore and Activate this version', variant: 'brand',
            disabled: { fieldName: 'Is_Active__c' }
        }
    }
];

export default class DocGenAdmin extends NavigationMixin(LightningElement) {
    @track templates = [];
    columns = COLUMNS;
    versionColumns = VERSION_COLUMNS;
    wiredTemplatesResult;

    librariesLoaded = false;
    @track versions = [];

    // Form/Wizard State
    @track activeMainTab = 'list';
    @track currentWizardStep = '1';

    // Create State
    newTemplateName = '';
    newTemplateCategory = '';
    newTemplateType = 'Word';
    newTemplateOutputFormat = 'PDF';
    newTemplateObject = 'Account';
    newTemplateDesc = '';
    newTemplateQuery = '';
    newTemplateMetadata = '';
    isCreating = true;
    createdTemplateId;

    // Edit State
    @track isEditModalOpen = false;
    @track activeEditTab = 'details';
    editTemplateId;
    editTemplateName;
    editTemplateCategory;
    editTemplateType;
    editTemplateObject;
    editTemplateOutputFormat;
    editTemplateDesc;
    editTemplateQuery;
    editTemplateMetadata;
    editTemplateTestRecordId;
    editTemplateTitleFormat; // New Field

    @track currentFileId;
    @track uploadedFileName = '';

    // Preview/Restore State
    @track isPreviewModalOpen = false;
    @track previewVersion = {};
    isLoadingVersions = false;

    // Manual Query Toggle
    @track isManualQuery = false;

    // Filter State
    searchKey = '';

    @wire(getAllTemplates)
    wiredTemplates(result) {
        this.wiredTemplatesResult = result;
        if (result.data) {
            this.templates = result.data;
        } else if (result.error) {
            this.showToast('Error', 'Error loading templates', 'error');
        }
    }

    get filteredTemplates() {
        if (!this.searchKey) return this.templates;
        const lowerKey = this.searchKey.toLowerCase();
        return this.templates.filter(t =>
            (t.Name && t.Name.toLowerCase().includes(lowerKey)) ||
            (t.Category__c && t.Category__c.toLowerCase().includes(lowerKey)) ||
            (t.Base_Object_API__c && t.Base_Object_API__c.toLowerCase().includes(lowerKey)) ||
            (t.Type__c && t.Type__c.toLowerCase().includes(lowerKey)) ||
            (t.Description__c && t.Description__c.toLowerCase().includes(lowerKey)) ||
            (t.Id && t.Id.toLowerCase().includes(lowerKey))
        );
    }

    handleRefresh() {
        return refreshApex(this.wiredTemplatesResult);
    }

    handleSearch(event) {
        this.searchKey = event.detail.value;
    }

    get showInstallSample() {
        return false; // Disabled per cleanup
    }

    /*
    handleInstallSample() {
        // Removed per cleanup
    }
    */

    renderedCallback() {
        if (this.librariesLoaded) return;
        this.librariesLoaded = true;

        const scripts = [
            { name: 'PizZip', p: loadScript(this, PIZZIP_JS) },
            { name: 'Docxtemplater', p: loadScript(this, DOCXTEMPLATER_JS) },
            { name: 'FileSaver', p: loadScript(this, FILESAVER_JS) },
            { name: 'Handlebars', p: loadScript(this, HANDLEBARS_JS) }
        ];
        const toMsg = (e) => (e && e.message) || (e && e.body && e.body.message) || (typeof e === 'string' ? e : null);
        Promise.all(scripts.map(({ name, p }) =>
            p.catch(err => {
                const msg = toMsg(err) || 'script failed to load';
                throw new Error(name + ': ' + msg);
            })
        ))
            .then(() => {
                this.librariesReady = true;
            })
            .catch(err => {
                const msg = toMsg(err) || 'One or more libraries could not load. Ensure static resources (pizzip, docxtemplater, filesaver, handlebars) are deployed and accessible.';
                this.librariesReady = false;
            });
    }

    // --- Wizard Logic ---

    get isStep1() { return this.currentWizardStep === '1'; }
    get isStep2() { return this.currentWizardStep === '2'; }
    get isStep3() { return this.currentWizardStep === '3'; }
    get isBackDisabled() { return this.currentWizardStep === '1'; }

    handleNextStep() {
        if (this.currentWizardStep === '1') {
            if (!this.newTemplateName || !this.newTemplateType) {
                this.showToast('Error', 'Please fill required fields.', 'error');
                return;
            }
            this.currentWizardStep = '2';
        } else if (this.currentWizardStep === '2') {
            if (!this.newTemplateObject || !this.newTemplateQuery) {
                this.showToast('Error', 'Please configure the query.', 'error');
                return;
            }
            this.currentWizardStep = '3';
        }
    }

    handlePrevStep() {
        if (this.currentWizardStep === '3') this.currentWizardStep = '2';
        else if (this.currentWizardStep === '2') this.currentWizardStep = '1';
    }

    resetForm() {
        this.currentWizardStep = '1';
        this.newTemplateName = '';
        this.newTemplateCategory = '';
        this.newTemplateType = 'Word';
        this.newTemplateOutputFormat = 'PDF';
        this.newTemplateObject = 'Account';
        this.newTemplateDesc = '';
        this.newTemplateQuery = '';
        this.newTemplateMetadata = '';
        this.isCreating = true;
        this.createdTemplateId = null;
    }

    handleWizardTabActive(event) {
        this.activeMainTab = 'new_template';
        this.resetForm();
    }

    handleTabActive(event) {
        this.activeMainTab = event.target.value;
    }

    // --- Create Handlers ---
    handleNameChange(event) { this.newTemplateName = event.detail.value; }
    handleCategoryChange(event) { this.newTemplateCategory = event.detail.value; }
    handleTypeChange(event) { this.newTemplateType = event.detail.value; }
    handleOutputFormatChange(event) { this.newTemplateOutputFormat = event.detail.value; }
    handleDescChange(event) { this.newTemplateDesc = event.detail.value; }

    handleConfigChange(event) {
        this.newTemplateObject = event.detail.objectName;
        this.newTemplateQuery = event.detail.queryConfig;
        this.newTemplateMetadata = event.detail.queryMetadata;
    }

    // --- Edit Handlers ---
    handleEditNameChange(event) { this.editTemplateName = event.detail.value; }
    handleEditCategoryChange(event) { this.editTemplateCategory = event.detail.value; }
    handleEditTypeChange(event) { this.editTemplateType = event.detail.value; }
    handleEditOutputFormatChange(event) { this.editTemplateOutputFormat = event.detail.value; }
    handleEditDescChange(event) { this.editTemplateDesc = event.detail.value; }

    handleManualQueryToggle(event) {
        this.isManualQuery = event.target.checked;
    }

    handleQueryStringChange(event) {
        this.editTemplateQuery = event.target.value;
    }

    handleEditConfigChange(event) {
        this.editTemplateObject = event.detail.objectName;
        this.editTemplateQuery = event.detail.queryConfig;
        this.editTemplateMetadata = event.detail.queryMetadata;
    }

    handleEditTestRecordChange(event) {
        this.editTemplateTestRecordId = event.detail.recordId;
    }

    handleTitleFormatChange(event) {
        this.editTemplateTitleFormat = event.detail.value;
    }

    handleEditTabChange(event) {
        const val = event.target.value;
        if (val) this.activeEditTab = val;
        if (val === 'query' && !this.isManualQuery) {
            this.refreshEditQueryBuilder();
        }
    }

    refreshEditQueryBuilder() {
        const builders = this.template.querySelectorAll('c-doc-gen-query-builder');
        for (const b of builders) {
            if (b.showTagsOnly === true) continue;
            if (typeof b.refreshFromConfig === 'function') {
                b.refreshFromConfig();
                break;
            }
        }
    }

    get isBuilderDisabled() {
        return this.isManualQuery;
    }

    get queryBuilderSectionClass() {
        const show = this.activeEditTab === 'query' && !this.isManualQuery;
        return show ? '' : 'slds-hide';
    }

    // --- Options ---
    get typeOptions() {
        return [
            { label: 'Word', value: 'Word' },
            { label: 'PowerPoint', value: 'PowerPoint' },
            { label: 'HTML', value: 'HTML' }
        ];
    }

    get outputFormatOptions() {
        return [
            { label: 'Native (.docx / .pptx)', value: 'Native' },
            { label: 'PDF', value: 'PDF' }
        ];
    }

    get acceptedFormats() {
        if (this.editTemplateType === 'HTML') return ['.html'];
        if (this.editTemplateType === 'PowerPoint') return ['.pptx'];
        return ['.docx'];
    }

    // --- Create Logic ---
    async createTemplate() {
        const fields = {};
        fields[NAME_FIELD.fieldApiName] = this.newTemplateName;
        fields[CATEGORY_FIELD.fieldApiName] = this.newTemplateCategory;
        fields[TYPE_FIELD.fieldApiName] = this.newTemplateType;
        fields['Output_Format__c'] = this.newTemplateOutputFormat;
        fields[BASE_OBJECT_FIELD.fieldApiName] = this.newTemplateObject;
        fields[QUERY_CONFIG_FIELD.fieldApiName] = this.newTemplateQuery;
        fields[QUERY_METADATA_FIELD.fieldApiName] = this.newTemplateMetadata;
        fields[DESC_FIELD.fieldApiName] = this.newTemplateDesc;

        try {
            const record = await createRecord({ apiName: DOCGEN_TEMPLATE_OBJECT.objectApiName, fields });
            this.createdTemplateId = record.id;
            this.isCreating = false;
            this.showToast('Success', 'Template Record created. Please upload your document.', 'success');

            // Construct row object for edit modal
            const newRow = {
                Id: record.id,
                Name: this.newTemplateName,
                Category__c: this.newTemplateCategory,
                Type__c: this.newTemplateType,
                Base_Object_API__c: this.newTemplateObject,
                Description__c: this.newTemplateDesc,
                Query_Config__c: this.newTemplateQuery,
                Query_Metadata__c: this.newTemplateMetadata,
                Test_Record_Id__c: null,
                Document_Title_Format__c: null,
                ContentDocumentLinks: []
            };

            this.resetForm();
            await refreshApex(this.wiredTemplatesResult);

            // Switch to List Tab and Open Modal
            this.activeMainTab = 'list';
            this.activeEditTab = 'document'; // Explicitly go to document upload for new templates
            this.openEditModal(newRow, 'document');

        } catch (error) {
            this.showToast('Error creating record', error.body ? error.body.message : error.message, 'error');
        }
    }

    // --- Sharing Logic ---
    @track isSharingModalOpen = false;
    sharingTemplateId;

    handleCloseSharing() {
        this.isSharingModalOpen = false;
    }

    // --- Row Action ---
    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'delete') {
            try {
                await deleteTemplate({ templateId: row.Id });
                this.showToast('Success', 'Template deleted', 'success');
                return refreshApex(this.wiredTemplatesResult);
            } catch (error) {
                this.showToast('Error deleting template', error.body ? error.body.message : error.message, 'error');
            }
        } else if (actionName === 'edit') {
            this.openEditModal(row, 'details');
        } else if (actionName === 'view') {
            this.openEditModal(row, 'tags');
        } else if (actionName === 'share') {
            this.sharingTemplateId = row.Id;
            this.isSharingModalOpen = true;
        }
    }

    // --- Edit Modal ---
    openEditModal(row, activeTab) {
        try {
            this.editTemplateId = row.Id;
            this.editTemplateName = row.Name;
            this.editTemplateCategory = row.Category__c;
            this.editTemplateType = row.Type__c;
            this.editTemplateObject = row.Base_Object_API__c;
            this.editTemplateOutputFormat = row.Output_Format__c || 'Native';
            this.editTemplateDesc = row.Description__c;
            this.editTemplateQuery = row.Query_Config__c;
            this.editTemplateMetadata = row.Query_Metadata__c;
            this.editTemplateTestRecordId = row.Test_Record_Id__c;
            this.editTemplateTitleFormat = row.Document_Title_Format__c;

            // Extract ContentDocumentId safely
            let cdLinks = [];
            if (row.ContentDocumentLinks) {
                if (Array.isArray(row.ContentDocumentLinks)) {
                    cdLinks = row.ContentDocumentLinks;
                } else if (row.ContentDocumentLinks.records) {
                    cdLinks = row.ContentDocumentLinks.records;
                }
            }

            if (cdLinks && cdLinks.length > 0) {
                this.currentFileId = cdLinks[0].ContentDocumentId;
            } else {
                this.currentFileId = null;
            }

            // Default to "Document & History" if no file exists to prompt upload
            if (!this.currentFileId) {
                this.activeEditTab = 'document';
            } else {
                this.activeEditTab = activeTab || 'details';
            }

            this.loadVersions(row.Id);
            this.isCreating = false;
            this.isEditModalOpen = true;
            setTimeout(() => this.refreshEditQueryBuilder(), 400);
        } catch (e) {
            this.showToast('Error', 'Failed to open modal: ' + e.message, 'error');
        }
    }

    closeEditModal() {
        this.isEditModalOpen = false;
    }

    // --- Versions Logic ---
    get hasVersions() {
        return this.versions && this.versions.length > 0;
    }

    get currentVersionLabel() {
        if (this.hasVersions) {
            return this.versions[0].VersionNumber;
        }
        return '';
    }

    loadVersions(templateId) {
        getTemplateVersions({ templateId })
            .then(data => {
                if (!data) {
                    this.versions = [];
                    return;
                }
                const total = data.length;
                this.versions = data.map((v, index) => {
                    const isActive = v.Is_Active__c;
                    return {
                        ...v,
                        VersionNumber: 'v' + (total - index),
                        CreatedByName: v.CreatedBy ? v.CreatedBy.Name : '',
                        isActiveLabel: isActive ? '✓' : '',
                        activeClass: isActive ? 'slds-text-color_success slds-text-title_bold' : '',
                        activateVariant: isActive ? 'neutral' : 'brand' // Brand (Blue) for Inactive, Neutral for Active
                    };
                });
            })
            .catch(error => {
                this.versions = [];
            });
    }

    async handleRestoreVersion(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'restore') {
            try {
                this.isLoadingVersions = true;
                await activateVersion({ versionId: row.Id });

                this.showToast('Success', 'Version activated.', 'success');

                // Update local state to match restored version
                this.editTemplateQuery = row.Query_Config__c;
                this.editTemplateMetadata = row.Query_Metadata__c;
                this.editTemplateCategory = row.Category__c;
                this.editTemplateDesc = row.Description__c;
                this.editTemplateType = row.Type__c;

                this.loadVersions(this.editTemplateId);
                refreshApex(this.wiredTemplatesResult);
            } catch (error) {
                this.showToast('Error activating version', error.body ? error.body.message : error.message, 'error');
            } finally {
                this.isLoadingVersions = false;
            }
        } else if (action === 'preview') {
            this.handlePreviewVersion(row);
        }
    }

    handlePreviewVersion(row) {
        this.previewVersion = row;
        this.isPreviewModalOpen = true;
    }

    closePreviewModal() {
        this.isPreviewModalOpen = false;
    }

    handleRestoreFromPreview() {
        const event = {
            detail: {
                action: { name: 'restore' },
                row: this.previewVersion
            }
        };
        this.handleRestoreVersion(event);
        this.closePreviewModal();
    }

    // --- Save Logic ---
    getEditModeQueryConfig() {
        if (this.isManualQuery) {
            return this.editTemplateQuery || '';
        }
        const builders = this.template.querySelectorAll('c-doc-gen-query-builder');
        for (const b of builders) {
            if (b.showTagsOnly === true) continue;
            if (typeof b.getQueryConfig === 'function') {
                const q = b.getQueryConfig();
                if (q && typeof q === 'string' && q.trim().length > 0) return q;
            }
        }
        return this.editTemplateQuery || '';
    }

    getEditModeQueryMetadata() {
        if (this.isManualQuery) {
            const builder = this.template.querySelector('c-doc-gen-query-builder:not([show-tags-only="true"])');
            if (builder && typeof builder.convertSOQLToMetadata === 'function') {
                const newMetadata = builder.convertSOQLToMetadata(this.editTemplateQuery, this.editTemplateObject);
                if (newMetadata) return newMetadata;
            }
            return this.editTemplateMetadata || '';
        }
        const builders = this.template.querySelectorAll('c-doc-gen-query-builder');
        for (const b of builders) {
            if (b.showTagsOnly === true) continue;
            if (typeof b.getQueryMetadata === 'function') {
                const qm = b.getQueryMetadata();
                if (qm && typeof qm === 'string' && qm.trim().length > 0) return qm;
            }
        }
        return this.editTemplateMetadata || '';
    }

    async handleSaveOnly() {
        // Validate
        if (!this.editTemplateName || !this.editTemplateType) {
            this.showToast('Error', 'Name and Type are required.', 'error');
            return;
        }

        const queryToSave = this.getEditModeQueryConfig();
        const fields = {
            Id: this.editTemplateId,
            Name: this.editTemplateName,
            Category__c: this.editTemplateCategory,
            Type__c: this.editTemplateType,
            Output_Format__c: this.editTemplateOutputFormat,
            Base_Object_API__c: this.editTemplateObject,
            Description__c: this.editTemplateDesc,
            Query_Config__c: queryToSave,
            Query_Metadata__c: this.getEditModeQueryMetadata(),
            Test_Record_Id__c: this.editTemplateTestRecordId,
            Document_Title_Format__c: this.editTemplateTitleFormat
        };

        try {
            await saveTemplate({ fields: fields, createVersion: false });
            this.showToast('Success', 'Template Details saved.', 'success');
            return refreshApex(this.wiredTemplatesResult);
        } catch (error) {
            this.showToast('Error saving template', error.body ? error.body.message : error.message, 'error');
        }
    }

    async handleSaveAndClose() {
        // Validate
        if (!this.editTemplateName || !this.editTemplateType) {
            this.showToast('Error', 'Name and Type are required.', 'error');
            return;
        }

        const queryToSave = this.getEditModeQueryConfig();
        const fields = {
            Id: this.editTemplateId,
            Name: this.editTemplateName,
            Category__c: this.editTemplateCategory,
            Type__c: this.editTemplateType,
            Output_Format__c: this.editTemplateOutputFormat,
            Base_Object_API__c: this.editTemplateObject,
            Description__c: this.editTemplateDesc,
            Query_Config__c: queryToSave,
            Query_Metadata__c: this.getEditModeQueryMetadata(),
            Test_Record_Id__c: this.editTemplateTestRecordId,
            Document_Title_Format__c: this.editTemplateTitleFormat
        };

        const createVersion = true;

        try {
            await saveTemplate({ fields: fields, createVersion: createVersion });
            this.showToast('Success', 'Template and Version saved.', 'success');
            this.closeEditModal();
            return refreshApex(this.wiredTemplatesResult);
        } catch (error) {
            this.showToast('Error saving template', error.body ? error.body.message : error.message, 'error');
        }
    }

    // --- Document Generation & Test Logic ---
    get editTemplateTestRecordIdEmpty() {
        return !this.editTemplateTestRecordId;
    }

    async handleTestPreview() {
        await this._runTestGenerationFlow(true);
    }

    async handleTestGenerate() {
        await this._runTestGenerationFlow(false);
    }

    async _runTestGenerationFlow(isPreview) {
        if (!this.editTemplateTestRecordId) {
            this.showToast('Warning', 'Please select a Test Record ID first.', 'warning');
            return;
        }

        // 1. Save First
        await this.handleSaveOnly();

        // 2. Check Libraries
        if (!this.librariesReady) {
            this.showToast('Error', 'Libraries not loaded yet. Please wait.', 'error');
            return;
        }

        this.isLoadingVersions = true;

        try {
            // 3. fetch Data
            const result = await generateDocumentData({
                templateId: this.editTemplateId,
                recordId: this.editTemplateTestRecordId
            });

            const templateData = result.templateFile; // Base64
            const templateType = this.editTemplateType;

            // 4. Sanitize Data
            let recordData;
            try {
                const rawData = JSON.parse(JSON.stringify(result.data));
                recordData = flattenData(rawData);
            } catch (jsonErr) {
                throw new Error('Data sanitization failed: ' + jsonErr.message);
            }

            const baseName = 'Sample_' + (recordData.Name || 'Document');

            if (templateType === 'HTML') {
                if (!window.Handlebars) {
                    throw new Error('Handlebars library not loaded.');
                }
                const renderedHtml = renderHtmlTemplate(templateData, recordData);
                if (this.editTemplateOutputFormat === 'PDF') {
                    this.showToast('Info', 'Generating PDF Sample...', 'info');
                    const iframe = this.template.querySelector('iframe');
                    if (!iframe) {
                        this.showToast('Error', 'PDF Engine not found in DOM.', 'error');
                        return;
                    }

                    const messageData = {
                        type: 'generate',
                        html: renderedHtml,
                        fileName: baseName
                    };

                    const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                    await this._handleTestPdfBlobResult(pdfBlob, baseName, isPreview);

                } else {
                    const blob = new Blob([renderedHtml], { type: 'application/octet-stream' });
                    if (isPreview) {
                        this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                        downloadBlob(blob, baseName + '.html');
                    } else {
                        downloadBlob(blob, baseName + '.html');
                        this.showToast('Success', 'Sample HTML document downloaded.', 'success');
                    }
                }
                return;
            }

            if (!window.PizZip || !window.docxtemplater) {
                this.showToast('Error', 'Required libraries not loaded.', 'error');
                return;
            }

            const doc = renderDocxTemplate(templateData, recordData);
            const { blob, extension, isPDF, isPPT } = generateBlobFromDocx(doc, templateType, this.editTemplateOutputFormat);

            if (isPPT) {
                if (isPreview) {
                    this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                    downloadBlob(blob, baseName + '.pptx');
                } else {
                    downloadBlob(blob, baseName + '.pptx');
                    this.showToast('Success', 'Sample PowerPoint downloaded.', 'success');
                }
            } else if (!isPDF) {
                if (isPreview) {
                    this.showToast('Warning', 'Preview is only supported for PDF output. Downloading instead.', 'warning');
                    downloadBlob(blob, baseName + '.docx');
                } else {
                    downloadBlob(blob, baseName + '.docx');
                    this.showToast('Success', 'Sample Word document downloaded.', 'success');
                }
            } else {
                this.showToast('Info', 'Generating PDF Sample...', 'info');
                const iframe = this.template.querySelector('iframe');
                if (!iframe) {
                    this.showToast('Error', 'PDF Engine not found in DOM.', 'error');
                    return;
                }

                const messageData = {
                    type: 'generate',
                    blob: blob,
                    fileName: baseName
                };

                const pdfBlob = await orchestratePdfGeneration(iframe, messageData);
                await this._handleTestPdfBlobResult(pdfBlob, baseName, isPreview);
            }

        } catch (error) {
            this.showToast('Generation Error', error.message || error, 'error');
        } finally {
            this.isLoadingVersions = false;
        }
    }

    async _handleTestPdfBlobResult(pdfBlob, baseName, isPreview) {
        if (!pdfBlob) {
            this.isLoadingVersions = false;
            return;
        }

        if (isPreview) {
            this.isLoadingVersions = false;
            await DocGenPreviewModal.open({
                size: 'large',
                pdfBlob: pdfBlob,
                fileName: baseName + '.pdf'
            });
        } else {
            downloadBlob(pdfBlob, baseName + '.pdf');
            this.showToast('Success', 'Sample PDF downloaded.', 'success');
            this.isLoadingVersions = false;
        }
    }

    handleEditUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles && uploadedFiles.length > 0) {
            const file = uploadedFiles[0];
            this.showToast('Success', 'File Uploaded: ' + file.name, 'success');
            this.currentFileId = file.documentId;
            this.uploadedFileName = file.name;
        }
    }

    downloadTemplate() {
        if (this.currentFileId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: `/sfc/servlet.shepherd/document/download/${this.currentFileId}`
                }
            });
        } else {
            this.showToast('Error', 'No document found to download.', 'error');
        }
    }

    handleDeleteDocument(event) {
        const docId = event.target.dataset.id;
        if (docId) {
            // ... (requires Apex method to delete ContentDocument) ...
            this.showToast('Info', 'Delete document functionality requires Apex implementation.', 'info');
        }
    }

    get hasDocument() {
        return !!this.currentFileId;
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
}
