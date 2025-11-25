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
