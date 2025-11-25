import { LightningElement, track, wire, api } from 'lwc';
import getPendingRequests from '@salesforce/apex/ChangeRequestController.getPendingRequests';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const COLUMNS = [
    { label: 'Aluno', fieldName: 'studentName', type: 'text' },
    { label: 'Tipo', fieldName: 'Request_Type__c', type: 'text' },
    { label: 'Novo Valor', fieldName: 'newValuePreview', type: 'text' },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'Abrir', name: 'open' }], menuAlignment: 'right' }
    }
];

export default class ChangeRequestApprovalList extends LightningElement {
    @track requests = [];
    columns = COLUMNS;

    wiredRequestsResult; // store wired result for refreshApex

    @wire(getPendingRequests)
    wiredRequests(result) {
        this.wiredRequestsResult = result;
        const { data, error } = result;
        if (data) {
            this.requests = data.map(r => {
                let preview = r.New_Value__c;
                if (preview && preview.length > 60) preview = preview.substring(0, 57) + '...';
                return {
                    Id: r.Id,
                    studentName: r.Student__r ? r.Student__r.Name : '',
                    Request_Type__c: r.Request_Type__c,
                    newValuePreview: preview
                };
            });
        } else if (error) {
            this.requests = [];
            this.showToast('Erro ao carregar', this._extractError(error), 'error');
        }
    }

    get isEmpty() {
        return !(this.requests && this.requests.length > 0);
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'open') {
            // emit event with requestId
            this.dispatchEvent(new CustomEvent('requestselected', { detail: row.Id }));
        }
    }

    // public method to allow wrapper to refresh list programmatically
    @api
    async refreshList() {
        if (this.wiredRequestsResult) {
            try {
                await refreshApex(this.wiredRequestsResult);
            } catch (e) {
                this.showToast('Erro', 'Falha ao atualizar a lista: ' + this._extractError(e), 'error');
            }
        }
    }

    _extractError(err) {
        if (!err) return 'Erro desconhecido';
        try {
            if (err.body && err.body.message) return err.body.message;
            if (err.message) return err.message;
            return JSON.stringify(err);
        } catch (e) {
            return String(err);
        }
    }

    showToast(title, msg, variant='info') {
        this.dispatchEvent(new ShowToastEvent({ title, message: msg, variant }));
    }
}
