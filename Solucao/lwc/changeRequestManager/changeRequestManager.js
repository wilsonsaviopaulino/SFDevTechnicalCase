import { LightningElement, track } from 'lwc';

export default class ChangeRequestManager extends LightningElement {
    @track selectedRequestId;

    // Disparado quando o usuário clica em um item da lista
    handleRequestSelected(event) {
        this.selectedRequestId = event.detail;
    }

    // Após aprovar/rejeitar: refresh list and clear detail
    handleActionCompleted() {
        // clear selection
        this.selectedRequestId = null;
        // call refresh on list component
        const listComponent = this.template.querySelector('c-change-request-approval-list');
        if (listComponent && listComponent.refreshList) {
            listComponent.refreshList();
        }
    }
}
