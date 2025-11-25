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
