import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import { getRecord } from 'lightning/uiRecordApi';
import createRequest from '@salesforce/apex/ChangeRequestController.createRequest';

import CONTACT_ID_FIELD from '@salesforce/schema/User.ContactId';

export default class StudentChangeRequestForm extends LightningElement {
    @track requestType;
    @track newValue;

    requestTypeOptions = [
        { label: 'Email', value: 'Email' },
        { label: 'Phone', value: 'Phone' },
        { label: 'Mailing Address', value: 'MailingAddress' }
    ];

    // Get current user's ContactId (works for Experience Cloud users)
    userId = USER_ID;
    contactId;
    @wire(getRecord, { recordId: USER_ID, fields: [CONTACT_ID_FIELD] })
    wiredUser({error, data}) {
        if (data) {
            this.contactId = data.fields.ContactId.value;
        }
    }

    handleTypeChange(event) {
        this.requestType = event.detail.value;
    }
    handleValueChange(event) {
        this.newValue = event.target.value;
    }

    handleClear() {
        this.requestType = null;
        this.newValue = null;
        // clear inputs
        this.template.querySelectorAll('lightning-combobox, lightning-textarea').forEach(el => {
            if (el) el.value = null;
        });
    }

    async handleSubmit() {
        if (!this.contactId) {
            this.showToast('Erro', 'Não foi possível identificar seu cadastro (Contact).', 'error');
            return;
        }
        if (!this.requestType || !this.newValue) {
            this.showToast('Atenção', 'Preencha o tipo e o novo valor.', 'warning');
            return;
        }
        try {
            const id = await createRequest({ studentId: this.contactId, requestType: this.requestType, newValue: this.newValue });
            this.showToast('Enviado', 'Solicitação criada com sucesso.', 'success');
            this.handleClear();
            // dispatch event so container pages can refresh lists
            this.dispatchEvent(new CustomEvent('submitted', { detail: { requestId: id } }));
        } catch (err) {
            this.showToast('Erro', this._extractError(err), 'error');
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
