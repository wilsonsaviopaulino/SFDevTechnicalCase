public with sharing class ChangeRequestController {

    @AuraEnabled
    public static Id createRequest(Id studentId, String requestType, String newValue) {

        // Validação mínima
        if (studentId == null || String.isBlank(requestType) || String.isBlank(newValue)) {
            throw new AuraHandledException('Dados inválidos para criação da solicitação.');
        }

        // Busca valor atual (Old_Value__c)
        Contact c = [
            SELECT Id, Name, Phone, Email 
            FROM Contact 
            WHERE Id = :studentId 
            LIMIT 1
        ];

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
