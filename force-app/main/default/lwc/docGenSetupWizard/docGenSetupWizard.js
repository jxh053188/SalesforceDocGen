import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/DocGenSetupController.getSettings';
import saveSettings from '@salesforce/apex/DocGenSetupController.saveSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DocGenSetupWizard extends LightningElement {
    @track experienceSiteUrl = '';
    @track isLoaded = false;

    @wire(getSettings)
    wiredSettings({ error, data }) {
        if (data) {
            this.experienceSiteUrl = data.Experience_Site_Url__c || '';
            this.isLoaded = true;
        } else if (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to load settings.', variant: 'error' }));
            this.isLoaded = true;
        }
    }

    handleUrlChange(event) {
        this.experienceSiteUrl = event.target.value;
    }

    handleSaveSettings() {
        this.isLoaded = false;
        saveSettings({ experienceSiteUrl: this.experienceSiteUrl })
            .then(() => {
                this.isLoaded = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Settings saved successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.isLoaded = true;
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to save settings.', variant: 'error' }));
            });
    }
}
