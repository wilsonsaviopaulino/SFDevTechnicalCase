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
