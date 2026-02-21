import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBulkTemplates from '@salesforce/apex/DocGenBulkController.getBulkTemplates';
import validateFilter from '@salesforce/apex/DocGenBulkController.validateFilter';
import submitJob from '@salesforce/apex/DocGenBulkController.submitJob';
import getJobStatus from '@salesforce/apex/DocGenBulkController.getJobStatus';
import getSavedQueries from '@salesforce/apex/DocGenBulkController.getSavedQueries';
import saveQuery from '@salesforce/apex/DocGenBulkController.saveQuery';
import deleteQuery from '@salesforce/apex/DocGenBulkController.deleteQuery';

export default class DocGenBulkRunner extends LightningElement {
    @track templates = [];
    @track selectedTemplateId;
    @track baseObject;
    @track condition = '';
    @track recordCount = null;
    @track isValidating = false;
    
    @track jobId;
    @track jobStatus;
    @track jobProgress = {};
    @track isProcessing = false;
    
    // Saved Queries State
    @track savedQueries = [];
    @track isSaveModalOpen = false;
    newQueryName = '';
    newQueryDesc = '';
    
    pollInterval;
    
    // Wire Templates
    @wire(getBulkTemplates)
    wiredTemplates({ error, data }) {
        if (data) {
            this.templates = data.map(t => ({
                label: t.Name + ' (' + t.Base_Object_API__c + ')',
                value: t.Id,
                baseObject: t.Base_Object_API__c
            }));
        } else if (error) {
            this.showToast('Error', 'Failed to load templates', 'error');
        }
    }
    
    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        const selected = this.templates.find(t => t.value === this.selectedTemplateId);
        if (selected) {
            this.baseObject = selected.baseObject;
            this.recordCount = null; // Reset validation
            this.loadSavedQueries();
        }
    }

    loadSavedQueries() {
        getSavedQueries({ templateId: this.selectedTemplateId })
            .then(data => {
                this.savedQueries = data;
            })
            .catch(error => {
                console.error('Error loading saved queries', error);
            });
    }

    handleLoadQuery(event) {
        const queryId = event.target.dataset.id;
        const query = this.savedQueries.find(q => q.Id === queryId);
        if (query) {
            this.condition = query.Query_Condition__c;
            this.recordCount = null;
        }
    }

    handleDeleteQuery(event) {
        const queryId = event.target.dataset.id;
        if (!confirm('Are you sure you want to delete this saved query?')) return;

        deleteQuery({ queryId })
            .then(() => {
                this.showToast('Success', 'Query deleted', 'success');
                this.loadSavedQueries();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to delete query', 'error');
            });
    }

    // --- Save Modal ---
    openSaveModal() {
        if (!this.condition) {
            this.showToast('Warning', 'Please enter a condition first.', 'warning');
            return;
        }
        this.newQueryName = '';
        this.newQueryDesc = '';
        this.isSaveModalOpen = true;
    }

    closeSaveModal() {
        this.isSaveModalOpen = false;
    }

    handleNewQueryNameChange(event) { this.newQueryName = event.target.value; }
    handleNewQueryDescChange(event) { this.newQueryDesc = event.target.value; }

    handleSaveQuery() {
        if (!this.newQueryName) {
            this.showToast('Error', 'Please enter a name.', 'error');
            return;
        }

        saveQuery({
            templateId: this.selectedTemplateId,
            label: this.newQueryName,
            description: this.newQueryDesc,
            condition: this.condition
        })
        .then(() => {
            this.showToast('Success', 'Query saved.', 'success');
            this.isSaveModalOpen = false;
            this.loadSavedQueries();
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }
    
    handleConditionChange(event) {
        this.condition = event.detail.value || event.target.value; // Support both
        this.recordCount = null;
    }
    
    async handleValidate() {
        if (!this.baseObject) return;
        this.isValidating = true;
        try {
            const count = await validateFilter({ objectName: this.baseObject, condition: this.condition });
            this.recordCount = count;
            this.showToast('Success', `Found ${count} records.`, 'success');
        } catch (error) {
            this.showToast('Validation Error', error.body.message, 'error');
            this.recordCount = null;
        } finally {
            this.isValidating = false;
        }
    }
    
    async handleRun() {
        if (!this.selectedTemplateId) {
            this.showToast('Error', 'Please select a template.', 'error');
            return;
        }
        
        this.isProcessing = true;
        try {
            this.jobId = await submitJob({ templateId: this.selectedTemplateId, condition: this.condition });
            this.showToast('Success', 'Job Started', 'success');
            this.startPolling();
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
            this.isProcessing = false;
        }
    }
    
    startPolling() {
        this.pollInterval = setInterval(async () => {
            await this.pollJob();
        }, 2000);
    }
    
    async pollJob() {
        if (!this.jobId) return;
        try {
            const job = await getJobStatus({ jobId: this.jobId });
            this.jobStatus = job.Status__c;
            const total = job.Total_Records__c || 0;
            const current = (job.Success_Count__c || 0) + (job.Error_Count__c || 0);
            this.jobProgress = {
                success: job.Success_Count__c || 0,
                error: job.Error_Count__c || 0,
                total: total,
                percent: total > 0 ? Math.floor((current / total) * 100) : 0
            };
            
            if (this.jobStatus === 'Completed' || this.jobStatus === 'Failed' || this.jobStatus === 'Completed with Errors') {
                clearInterval(this.pollInterval);
                this.isProcessing = false;
                this.showToast('Job Finished', `Status: ${this.jobStatus}`, 'info');
            }
        } catch (e) {
            console.error(e);
            clearInterval(this.pollInterval);
        }
    }
    
    disconnectedCallback() {
        if (this.pollInterval) clearInterval(this.pollInterval);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    
    get isRunDisabled() {
        return !this.selectedTemplateId || this.isProcessing;
    }
}