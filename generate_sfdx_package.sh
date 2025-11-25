#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)/sfdx_final"
ZIP_NAME="sfdx_final_package.zip"

echo "Criando pasta: $ROOT_DIR"
rm -rf "$ROOT_DIR"
mkdir -p "$ROOT_DIR/force-app/main/default"

# helper to write file
write_file() {
  local path="$ROOT_DIR/force-app/main/default/$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo " -> $1"
}

# sfdx-project.json
mkdir -p "$ROOT_DIR"
cat > "$ROOT_DIR/sfdx-project.json" <<'JSON'
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true
    }
  ],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "60.0"
}
JSON

# package.xml
cat > "$ROOT_DIR/package.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types>
    <members>*</members>
    <name>ApexClass</name>
  </types>
  <types>
    <members>*</members>
    <name>ApexTrigger</name>
  </types>
  <types>
    <members>*</members>
    <name>LightningComponentBundle</name>
  </types>
  <types>
    <members>*</members>
    <name>CustomObject</name>
  </types>
  <version>60.0</version>
</Package>
XML

# README
cat > "$ROOT_DIR/README.md" <<'MD'
# Change Request Solution - SFDX Package

Structure: force-app/main/default/...

Deploy with SFDX:
1. Authenticate: sfdx auth:web:login -d -a MyOrg
2. Deploy: sfdx force:source:deploy -p force-app -u MyOrg --wait 10
3. Run tests: sfdx force:apex:test:run -u MyOrg --wait 10 --resultformat human

Post-deploy:
- Create Custom Permission "ChangeRequest_Approver" (optional)
- Ensure Change_Request__c exists (object included)
- Grant FLS for Contact fields to approver profiles
MD

# ========== Apex Classes ==========
mkdir -p "$ROOT_DIR/force-app/main/default/classes"

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestController.cls" <<'APEX'
public with sharing class ChangeRequestController {
    
    @AuraEnabled
    public static Id createRequest(Id studentId, String requestType, String newValue) {

        if (studentId == null || String.isBlank(requestType) || String.isBlank(newValue)) {
            throw new AuraHandledException('Dados inválidos para criação da solicitação.');
        }

        Contact c = [SELECT Id, Name, Phone, Email FROM Contact WHERE Id = :studentId LIMIT 1];

        Change_Request__c req = new Change_Request__c(
            Student__c = studentId,
            Request_Type__c = requestType,
            New_Value__c = newValue,
            Old_Value__c = ChangeRequestUtil.getOldValue(requestType, c),
            Status__c = 'Pendente'
        );
        insert req;

        return req.Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<Change_Request__c> getStudentRequests(Id studentId) {
        if (studentId == null) studentId = UserInfo.getUserId();
        return [
            SELECT Id, Request_Type__c, Status__c, New_Value__c, Old_Value__c, CreatedDate, Student__r.Name
            FROM Change_Request__c
            WHERE Student__c = :studentId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Change_Request__c> getPendingRequests() {
        return [
            SELECT Id, Student__c, Student__r.Name, Request_Type__c,
                   New_Value__c, Old_Value__c, Status__c, CreatedDate
            FROM Change_Request__c
            WHERE Status__c = 'Pendente'
            ORDER BY CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static Change_Request__c getRequestById(Id reqId) {
        return [
            SELECT Id, Student__c, Student__r.Name, Request_Type__c,
                   New_Value__c, Old_Value__c, Status__c, Reason__c
            FROM Change_Request__c
            WHERE Id = :reqId LIMIT 1
        ];
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestController.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestApprovalService.cls" <<'APEX'
public with sharing class ChangeRequestApprovalService {

    @AuraEnabled
    public static void approveRequest(Id reqId) {

        Change_Request__c req = [
            SELECT Id, Student__c, Request_Type__c, New_Value__c, Status__c
            FROM Change_Request__c
            WHERE Id = :reqId
            LIMIT 1
        ];

        if (req.Status__c != 'Pendente') {
            throw new AuraHandledException('Esta solicitação já foi processada.');
        }

        req.Status__c = 'Aprovado';
        req.Reviewer__c = UserInfo.getUserId();
        update req;

        System.enqueueJob(new ContactUpdateQueueable(new List<Id>{req.Id}));
    }

    @AuraEnabled
    public static void rejectRequest(Id reqId, String reason) {

        Change_Request__c req = [
            SELECT Id, Status__c
            FROM Change_Request__c
            WHERE Id = :reqId
            LIMIT 1
        ];

        if (req.Status__c != 'Pendente') {
            throw new AuraHandledException('Esta solicitação já foi processada.');
        }

        req.Status__c = 'Rejeitado';
        req.Reviewer__c = UserInfo.getUserId();
        req.Reason__c = reason;

        update req;
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestApprovalService.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

cat > "$ROOT_DIR/force-app/main/default/classes/ContactUpdateService.cls" <<'APEX'
public with sharing class ContactUpdateService {

    public static void updateContactField(Change_Request__c req) {
        if (req == null || req.Student__c == null) return;

        if (!Schema.sObjectType.Contact.isUpdateable()) {
            throw new AuthorizationException('Sem permissão para atualizar registros Contact.');
        }

        Contact c = new Contact(Id = req.Student__c);

        try {
            if (req.Request_Type__c == 'Email') {
                if (!Schema.sObjectType.Contact.fields.Email.getDescribe().isUpdateable()) {
                    throw new AuthorizationException('Sem permissão para editar o campo Email no Contact.');
                }
                c.Email = req.New_Value__c;
            }
            else if (req.Request_Type__c == 'Phone') {
                if (!Schema.sObjectType.Contact.fields.Phone.getDescribe().isUpdateable()) {
                    throw new AuthorizationException('Sem permissão para editar o campo Phone no Contact.');
                }
                c.Phone = req.New_Value__c;
            }
            else if (req.Request_Type__c == 'MailingAddress') {
                if (String.isBlank(req.New_Value__c)) {
                    throw new AuraHandledException('New_Value__c vazio para MailingAddress.');
                }
                Object parsed = null;
                try {
                    parsed = JSON.deserializeUntyped(req.New_Value__c);
                } catch (Exception ex) {
                    throw new AuraHandledException('JSON inválido em New_Value__c para MailingAddress: ' + ex.getMessage());
                }
                if (!(parsed instanceof Map<String, Object>)) {
                    throw new AuraHandledException('Formato de MailingAddress inválido. Aguarda JSON com street, city, postalCode.');
                }
                Map<String, Object> m = (Map<String, Object>) parsed;
                if (m.containsKey('street')) {
                    if (!Schema.sObjectType.Contact.fields.MailingStreet.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar MailingStreet no Contact.');
                    }
                    c.MailingStreet = String.valueOf(m.get('street'));
                }
                if (m.containsKey('city')) {
                    if (!Schema.sObjectType.Contact.fields.MailingCity.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar MailingCity no Contact.');
                    }
                    c.MailingCity = String.valueOf(m.get('city'));
                }
                if (m.containsKey('postalCode') || m.containsKey('postalcode') || m.containsKey('postal_code')) {
                    if (!Schema.sObjectType.Contact.fields.MailingPostalCode.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar MailingPostalCode no Contact.');
                    }
                    Object val = m.containsKey('postalCode') ? m.get('postalCode') : (m.containsKey('postalcode') ? m.get('postalcode') : m.get('postal_code'));
                    c.MailingPostalCode = String.valueOf(val);
                }
                if (m.containsKey('state')) {
                    if (!Schema.sObjectType.Contact.fields.MailingState.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar MailingState no Contact.');
                    }
                    c.MailingState = String.valueOf(m.get('state'));
                }
                if (m.containsKey('country')) {
                    if (!Schema.sObjectType.Contact.fields.MailingCountry.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar MailingCountry no Contact.');
                    }
                    c.MailingCountry = String.valueOf(m.get('country'));
                }
            }
            else {
                if (Schema.sObjectType.Contact.fields.getMap().containsKey('Other_Requested_Value__c')) {
                    if (!Schema.sObjectType.Contact.fields.Other_Requested_Value__c.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar Other_Requested_Value__c no Contact.');
                    }
                    try {
                        ((SObject)c).put('Other_Requested_Value__c', req.New_Value__c);
                    } catch (Exception ex) {
                        throw new AuraHandledException('Não foi possível mapear o tipo de solicitação. ' + ex.getMessage());
                    }
                } else {
                    throw new AuraHandledException('Tipo de solicitação não mapeado: ' + req.Request_Type__c);
                }
            }

            List<SObject> inputList = new List<SObject>{ c };
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, inputList);
            List<SObject> safeRecords = decision.getRecords();

            if (safeRecords != null && !safeRecords.isEmpty()) {
                List<Contact> contactsToUpdate = (List<Contact>) safeRecords;
                update contactsToUpdate;
            }
        } catch (Exception ex) {
            if (ex instanceof AuthorizationException || ex instanceof AuraHandledException) {
                throw ex;
            } else {
                throw new AuraHandledException('Erro ao atualizar Contact: ' + ex.getMessage());
            }
        }
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ContactUpdateService.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

cat > "$ROOT_DIR/force-app/main/default/classes/ContactUpdateQueueable.cls" <<'APEX'
public with sharing class ContactUpdateQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> requestIds;
    public ContactUpdateQueueable(List<Id> requestIds) {
        this.requestIds = requestIds;
    }
    public void execute(QueueableContext ctx) {
        List<Change_Request__c> reqs = [
            SELECT Id, Student__c, Request_Type__c, New_Value__c, Old_Value__c
            FROM Change_Request__c
            WHERE Id IN :requestIds AND Status__c = 'Aprovado'
        ];
        if (!reqs.isEmpty()) {
            for (Change_Request__c r : reqs) {
                ContactUpdateService.updateContactField(r);
            }
        }
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ContactUpdateQueueable.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestUtil.cls" <<'APEX'
public with sharing class ChangeRequestUtil {

    public static String getOldValue(String requestType, Contact c) {

        switch on requestType {
            when 'Email' {
                return c.Email;
            }
            when 'Phone' {
                return c.Phone;
            }
            when else {
                return null;
            }
        }
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestUtil.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestTests.cls" <<'APEX'
@IsTest
public class ChangeRequestTests {

    static Contact createContact() {
        Contact c = new Contact(
            LastName = 'Aluno Teste',
            Email = 'old@test.com',
            Phone = '111111'
        );
        insert c;
        return c;
    }

    @IsTest
    static void testCreateRequest() {

        Contact c = createContact();

        Test.startTest();
        Id reqId = ChangeRequestController.createRequest(
            c.Id, 'Email', 'new@test.com'
        );
        Test.stopTest();

        Change_Request__c req = [
            SELECT Id, New_Value__c
            FROM Change_Request__c
            WHERE Id = :reqId
        ];

        System.assertEquals('new@test.com', req.New_Value__c);
    }

    @IsTest
    static void testApproveRequest() {

        Contact c = createContact();

        Change_Request__c req = new Change_Request__c(
            Student__c = c.Id,
            Request_Type__c = 'Email',
            New_Value__c = 'approved@test.com',
            Old_Value__c = c.Email,
            Status__c = 'Pendente'
        );
        insert req;

        Test.startTest();
        ChangeRequestApprovalService.approveRequest(req.Id);
        Test.stopTest();

        c = [SELECT Email FROM Contact WHERE Id = :c.Id];

        System.assertEquals('approved@test.com', c.Email);
    }

    @IsTest
    static void testRejectRequest() {

        Contact c = createContact();

        Change_Request__c req = new Change_Request__c(
            Student__c = c.Id,
            Request_Type__c = 'Phone',
            New_Value__c = '222222',
            Old_Value__c = c.Phone,
            Status__c = 'Pendente'
        );
        insert req;

        Test.startTest();
        ChangeRequestApprovalService.rejectRequest(req.Id, 'Incompleto');
        Test.stopTest();

        req = [SELECT Status__c, Reason__c FROM Change_Request__c WHERE Id = :req.Id];

        System.assertEquals('Rejeitado', req.Status__c);
        System.assertEquals('Incompleto', req.Reason__c);
    }
}
APEX

cat > "$ROOT_DIR/force-app/main/default/classes/ChangeRequestTests.cls-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexClass>
XML

# Trigger
mkdir -p "$ROOT_DIR/force-app/main/default/triggers"
cat > "$ROOT_DIR/force-app/main/default/triggers/ChangeRequestTrigger.trigger" <<'TRG'
trigger ChangeRequestTrigger on Change_Request__c (after update) {
    List<Id> toProcess = new List<Id>();
    for (Change_Request__c cr : Trigger.new) {
        Change_Request__c oldCr = Trigger.oldMap.get(cr.Id);
        if (oldCr.Status__c != 'Aprovado' && cr.Status__c == 'Aprovado') {
            toProcess.add(cr.Id);
        }
    }
    if (!toProcess.isEmpty()) {
        System.enqueueJob(new ContactUpdateQueueable(toProcess));
    }
}
TRG

cat > "$ROOT_DIR/force-app/main/default/triggers/ChangeRequestTrigger.trigger-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <status>Active</status>
</ApexTrigger>
XML

# ========== LWCs ==========
# studentChangeRequestForm
mkdir -p "$ROOT_DIR/force-app/main/default/lwc/studentChangeRequestForm"
cat > "$ROOT_DIR/force-app/main/default/lwc/studentChangeRequestForm/studentChangeRequestForm.html" <<'HTML'
<template>
    <lightning-card title="Nova Solicitação de Alteração">
        <div class="slds-p-around_medium">
            <lightning-combobox
                name="requestType"
                label="Tipo de solicitação"
                options={requestTypeOptions}
                value={requestType}
                onchange={handleTypeChange}>
            </lightning-combobox>

            <lightning-textarea
                label="Novo valor"
                value={newValue}
                placeholder="Informe o novo valor"
                onchange={handleValueChange}>
            </lightning-textarea>

            <div class="slds-m-top_medium">
                <lightning-button variant="brand" label="Enviar" onclick={handleSubmit} class="slds-m-right_small"></lightning-button>
                <lightning-button variant="neutral" label="Limpar" onclick={handleClear}></lightning-button>
            </div>
        </div>
    </lightning-card>
</template>
HTML

cat > "$ROOT_DIR/force-app/main/default/lwc/studentChangeRequestForm/studentChangeRequestForm.js" <<'JS'
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
JS

cat > "$ROOT_DIR/force-app/main/default/lwc/studentChangeRequestForm/studentChangeRequestForm.js-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <isExposed>true</isExposed>
  <targets>
    <target>lightningCommunity__Page</target>
    <target>lightning__AppPage</target>
    <target>lightning__RecordPage</target>
  </targets>
</LightningComponentBundle>
XML

# changeRequestApprovalList
mkdir -p "$ROOT_DIR/force-app/main/default/lwc/changeRequestApprovalList"
cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestApprovalList/changeRequestApprovalList.html" <<'HTML'
<template>
    <lightning-card title="Solicitações Pendentes">
        <div class="slds-p-around_medium">
            <template if:true={requests}>
                <lightning-datatable
                    data={requests}
                    columns={columns}
                    key-field="Id"
                    onrowaction={handleRowAction}
                    hide-checkbox-column
                >
                </lightning-datatable>
            </template>

            <template if:true={isEmpty}>
                <div class="slds-text-body_regular slds-m-top_small">Nenhuma solicitação pendente.</div>
            </template>
        </div>
    </lightning-card>
</template>
HTML

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestApprovalList/changeRequestApprovalList.js" <<'JS'
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

    wiredRequestsResult;

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
            this.dispatchEvent(new CustomEvent('requestselected', { detail: row.Id }));
        }
    }

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
JS

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestApprovalList/changeRequestApprovalList.js-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <isExposed>true</isExposed>
  <targets>
    <target>lightning__AppPage</target>
    <target>lightning__RecordPage</target>
    <target>lightning__HomePage</target>
    <target>lightningCommunity__Page</target>
  </targets>
</LightningComponentBundle>
XML

# changeRequestDetail
mkdir -p "$ROOT_DIR/force-app/main/default/lwc/changeRequestDetail"
cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestDetail/changeRequestDetail.html" <<'HTML'
<template>
    <lightning-card title="Detalhe da Solicitação">
        <div class="slds-p-around_medium">
            <template if:true={request}>
                <div class="slds-m-bottom_small"><b>Aluno:</b> {request.studentName}</div>
                <div class="slds-m-bottom_small"><b>Tipo:</b> {request.Request_Type__c}</div>
                <div class="slds-m-bottom_small"><b>Valor atual:</b> {request.Old_Value__c}</div>
                <div class="slds-m-bottom_small"><b>Novo valor:</b> {renderedNewValue}</div>

                <lightning-textarea label="Motivo (opcional)" value={reason} onchange={handleReasonChange}></lightning-textarea>

                <div class="slds-m-top_medium">
                    <lightning-button variant="brand" label="Aprovar" onclick={handleApprove} class="slds-m-right_small"></lightning-button>
                    <lightning-button variant="destructive" label="Rejeitar" onclick={handleReject}></lightning-button>
                </div>
            </template>

            <template if:false={request}>
                <div>Selecione uma solicitação para ver detalhes.</div>
            </template>
        </div>
    </lightning-card>
</template>
HTML

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestDetail/changeRequestDetail.js" <<'JS'
import { LightningElement, api, track, wire } from 'lwc';
import getRequestById from '@salesforce/apex/ChangeRequestController.getRequestById';
import approveRequest from '@salesforce/apex/ChangeRequestApprovalService.approveRequest';
import rejectRequest from '@salesforce/apex/ChangeRequestApprovalService.rejectRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ChangeRequestDetail extends LightningElement {
    @api recordId;
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
        try {
            const parsed = JSON.parse(this.request.New_Value__c);
            if (parsed && typeof parsed === 'object') {
                return Object.keys(parsed).map(k => `${k}: ${parsed[k]}`).join(' | ');
            }
        } catch (e) {}
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
JS

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestDetail/changeRequestDetail.js-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <isExposed>true</isExposed>
  <targets>
    <target>lightning__AppPage</target>
    <target>lightning__RecordPage</target>
    <target>lightning__HomePage</target>
    <target>lightningCommunity__Page</target>
  </targets>
  <properties>
    <property name="recordId" type="String" label="Request Id" />
  </properties>
</LightningComponentBundle>
XML

# wrapper changeRequestManager
mkdir -p "$ROOT_DIR/force-app/main/default/lwc/changeRequestManager"
cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestManager/changeRequestManager.html" <<'HTML'
<template>
    <lightning-card title="Gerenciamento de Solicitações de Alteração">
        <div class="container" style="display:flex;gap:1rem">
            <div style="width:40%">
                <c-change-request-approval-list onrequestselected={handleRequestSelected}></c-change-request-approval-list>
            </div>
            <div style="width:60%">
                <template if:true={selectedRequestId}>
                    <c-change-request-detail record-id={selectedRequestId} onactioncompleted={handleActionCompleted}></c-change-request-detail>
                </template>
                <template if:false={selectedRequestId}>
                    <div class="placeholder">Selecione uma solicitação na lista para visualizar os detalhes.</div>
                </template>
            </div>
        </div>
    </lightning-card>
</template>
HTML

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestManager/changeRequestManager.js" <<'JS'
import { LightningElement, track } from 'lwc';

export default class ChangeRequestManager extends LightningElement {
    @track selectedRequestId;

    handleRequestSelected(event) {
        this.selectedRequestId = event.detail;
    }

    handleActionCompleted() {
        this.selectedRequestId = null;
        const listComponent = this.template.querySelector('c-change-request-approval-list');
        if (listComponent && listComponent.refreshList) {
            listComponent.refreshList();
        }
    }
}
JS

cat > "$ROOT_DIR/force-app/main/default/lwc/changeRequestManager/changeRequestManager.js-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>60.0</apiVersion>
  <isExposed>true</isExposed>
  <masterLabel>Change Request Manager</masterLabel>
  <targets>
    <target>lightning__RecordPage</target>
    <target>lightning__AppPage</target>
    <target>lightning__HomePage</target>
    <target>lightning__Tab</target>
  </targets>
</LightningComponentBundle>
XML

# ========== Custom Object and Fields ==========
mkdir -p "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields"

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/Change_Request__c.object" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>Change Request</label>
  <pluralLabel>Change Requests</pluralLabel>
  <nameField>
    <type>AutoNumber</type>
    <label>Request #</label>
    <displayFormat>CR-{0000}</displayFormat>
  </nameField>
  <deploymentStatus>Deployed</deploymentStatus>
  <sharingModel>ReadWrite</sharingModel>
  <enableHistory>true</enableHistory>
  <description>Objeto para solicitações de alteração cadastral</description>
</CustomObject>
XML

# fields
cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Student__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Student__c</fullName>
  <label>Student</label>
  <type>Lookup</type>
  <referenceTo>Contact</referenceTo>
  <relationshipLabel>Student</relationshipLabel>
  <relationshipName>Student</relationshipName>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Request_Type__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Request_Type__c</fullName>
  <label>Request Type</label>
  <type>Picklist</type>
  <valueSet>
    <valueSetDefinition>
      <sorted>false</sorted>
      <value><fullName>Email</fullName></value>
      <value><fullName>Phone</fullName></value>
      <value><fullName>MailingAddress</fullName></value>
      <value><fullName>Other</fullName></value>
    </valueSetDefinition>
  </valueSet>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/New_Value__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>New_Value__c</fullName>
  <label>New Value</label>
  <type>LongTextArea</type>
  <length>32768</length>
  <visibleLines>5</visibleLines>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Old_Value__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Old_Value__c</fullName>
  <label>Old Value</label>
  <type>LongTextArea</type>
  <length>32768</length>
  <visibleLines>5</visibleLines>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Status__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Status__c</fullName>
  <label>Status</label>
  <type>Picklist</type>
  <valueSet>
    <valueSetDefinition>
      <sorted>false</sorted>
      <value><fullName>Pendente</fullName><default>true</default></value>
      <value><fullName>Aprovado</fullName></value>
      <value><fullName>Rejeitado</fullName></value>
    </valueSetDefinition>
  </valueSet>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Reason__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Reason__c</fullName>
  <label>Reason</label>
  <type>Text</type>
  <length>255</length>
</CustomField>
XML

cat > "$ROOT_DIR/force-app/main/default/objects/Change_Request__c/fields/Reviewer__c.field-meta.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Reviewer__c</fullName>
  <label>Reviewer</label>
  <type>Lookup</type>
  <referenceTo>User</referenceTo>
  <relationshipLabel>Reviewer</relationshipLabel>
  <relationshipName>Reviewer</relationshipName>
</CustomField>
XML

# ZIP the package
pushd "$ROOT_DIR" >/dev/null
zip -r "../$ZIP_NAME" . >/dev/null
popd >/dev/null

echo "Pacote gerado: $ROOT_DIR/../$ZIP_NAME"
echo "Extraia ou copie para o seu fork e faça commit/push."
