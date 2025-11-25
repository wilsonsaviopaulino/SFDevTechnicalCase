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

        ContactUpdateService.updateContactField(req);
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
