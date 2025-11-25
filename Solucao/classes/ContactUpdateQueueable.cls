public with sharing class ContactUpdateQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> requestIds;
    public ContactUpdateQueueable(List<Id> requestIds) {
        this.requestIds = requestIds;
    }
    public void execute(QueueableContext ctx) {
        // Query approved requests
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
