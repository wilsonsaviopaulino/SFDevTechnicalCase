public with sharing class ContactUpdateService {

    /**
     * Atualiza Contact a partir de uma Change_Request__c aprovada.
     * Suporta Request_Type__c: Email, Phone, MailingAddress (JSON).
     * Faz validação CRUD/FLS e stripInaccessible antes do update.
     */
    public static void updateContactField(Change_Request__c req) {
        if (req == null || req.Student__c == null) return;

        // Valida permissão de update em Contact (CRUD)
        if (!Schema.sObjectType.Contact.isUpdateable()) {
            throw new AuthorizationException('Sem permissão para atualizar registros Contact.');
        }

        // Build contact minimal
        Contact c = new Contact(Id = req.Student__c);

        try {
            if (req.Request_Type__c == 'Email') {
                // FLS check
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
                // Expect JSON like: {"street":"Rua X, 123","city":"Curitiba","postalCode":"80000-000"}
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

                // Map possible keys to Contact fields (check FLS for each)
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
                // fallback: write to custom field Other_Requested_Value__c if available & updateable
                if (Schema.sObjectType.Contact.fields.getMap().containsKey('Other_Requested_Value__c')) {
                    if (!Schema.sObjectType.Contact.fields.Other_Requested_Value__c.getDescribe().isUpdateable()) {
                        throw new AuthorizationException('Sem permissão para editar Other_Requested_Value__c no Contact.');
                    }
                    // Attempt to place raw value
                    try {
                        ((SObject)c).put('Other_Requested_Value__c', req.New_Value__c);
                    } catch (Exception ex) {
                        throw new AuraHandledException('Não foi possível mapear o tipo de solicitação. ' + ex.getMessage());
                    }
                } else {
                    throw new AuraHandledException('Tipo de solicitação não mapeado: ' + req.Request_Type__c);
                }
            }

            // Use stripInaccessible to remove any fields that current context cannot update
            List<SObject> inputList = new List<SObject>{ c };
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, inputList);
            List<SObject> safeRecords = decision.getRecords();

            if (safeRecords != null && !safeRecords.isEmpty()) {
                // Cast back to Contact list
                List<Contact> contactsToUpdate = (List<Contact>) safeRecords;
                update contactsToUpdate;
            } else {
                // nothing left to update after stripInaccessible
                // optionally log or notify
            }

        } catch (Exception ex) {
            // propagate user-friendly message
            if (ex instanceof AuthorizationException || ex instanceof AuraHandledException) {
                throw ex;
            } else {
                // Wrap unexpected exceptions for clarity
                throw new AuraHandledException('Erro ao atualizar Contact: ' + ex.getMessage());
            }
        }
    }
}
