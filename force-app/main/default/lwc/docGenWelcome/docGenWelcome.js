import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class DocGenWelcome extends NavigationMixin(LightningElement) {
    
    navigateToTemplates() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'DocGen_Template_Manager' 
            }
        });
    }

    navigateToBulk() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'DocGen_Bulk_Gen' 
            }
        });
    }
}