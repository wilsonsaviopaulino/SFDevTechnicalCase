import { LightningElement, api, track, wire } from 'lwc';
import getRequestById from '@salesforce/apex/ChangeRequestController.getRequestById';
import approveRequest from '@salesforce/apex/ChangeRequestApprovalService.approveRequest';
import rejectRequest from '@salesforce/apex/ChangeRequestApprovalService.rejectRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ChangeRequestDetail extends LightningElement {
    @api recordId; // requestId
    @track request;
    @track reason;

    @wire(getRequestById, { reqId: '$recordId' })
    wiredRequest({ error, data }) {
        if (data) {
            this.request = {
                Id: data.Id,
                studentId: data.Student__c,
                studentName: data.Student__r ? data.Student__r.Name : '',
                Request_Type__c: data.Request_Type__c,
                Old_Value__c: data.Old_Value__c,
                New_Value__c: data.New_Value__c,
                Status__c: data.Status__c
            };
        } else if (error) {
            this.request = null;
            this.showToast('Erro', this._extractError(error), 'error');
        }
    }

    get renderedNewValue() {
        if (!this.request || !this.request.New_Value__c) return '';
        // If JSON (address), pretty print
        try {
            const parsed = JSON.parse(this.request.New_Value__c);
            if (parsed && typeof parsed === 'object') {
                return Object.keys(parsed).map(k => `${k}: ${parsed[k]}`).join(' | ');
            }
        } catch (e) {
            // not JSON, return raw
        }
        return this.request.New_Value__c;
    }

    handleReasonChange(event) {
        this.reason = event.target.value;
    }

    async handleApprove() {
        if (!this.recordId) return;
        try {
            await approveRequest({ reqId: this.recordId });
            this.showToast('Aprovado', 'Solicitação aprovada com sucesso.', 'success');
            // emit event to parent to refresh and clear detail
            this.dispatchEvent(new CustomEvent('actioncompleted'));
        } catch (err) {
            this.showToast('Erro ao aprovar', this._extractError(err), 'error');
        }
    }

    async handleReject() {
        if (!this.recordId) return;
        try {
            await rejectRequest({ reqId: this.recordId, reason: this.reason || '' });
            this.showToast('Rejeitado', 'Solicitação rejeitada.', 'success');
            this.dispatchEvent(new CustomEvent('actioncompleted'));
        } catch (err) {
            this.showToast('Erro ao rejeitar', this._extractError(err), 'error');
        }
    }

    _extractError(err) {
        if (!err) return 'Erro desconhecido';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }

    showToast(title, msg, variant='info') {
        this.dispatchEvent(new ShowToastEvent({ title, message: msg, variant }));
    }
}
