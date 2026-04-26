public with sharing class DocGenDataRetriever {
    
    /**
     * Executes a dynamic SOQL query based on the fields configuration and record ID.
     * @param recordId The ID of the root record.
     * @param baseObject The API name of the base object.
     * @param fieldsConfig The comma-separated list of fields and subqueries (SELECT part).
     * @return Map<String, Object> The queried data.
     */
    public static Map<String, Object> getRecordData(Id recordId, String baseObject, String fieldsConfig) {
        if (String.isBlank(baseObject) || String.isBlank(fieldsConfig) || recordId == null) {
            throw new AuraHandledException('Invalid parameters for data retrieval.');
        }

        // The query string is constructed safely by the builder, but we still ensure the base string is valid
        String fieldsPart = fieldsConfig.trim();
        if (fieldsPart.toLowerCase().startsWith('select ')) {
            fieldsPart = fieldsPart.substring(7).trim();
        }
        String query = 'SELECT ' + fieldsPart + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';

        try {
            List<SObject> results = Database.query(query, AccessLevel.USER_MODE);
            if (results.isEmpty()) {
                return null;
            }
            return mapSObject(results[0]);
        } catch (Exception e) {
            throw new AuraHandledException('Error executing query. Details: ' + e.getMessage());
        }
    }

    private static Map<String, Object> mapSObject(SObject record) {
        Map<String, Object> data = new Map<String, Object>();
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        
        for (String key : populatedFields.keySet()) {
            try {
                Object value = populatedFields.get(key);
                
                if (value instanceof List<SObject>) {
                    List<Map<String, Object>> childList = new List<Map<String, Object>>();
                    for (SObject child : (List<SObject>) value) {
                        childList.add(mapSObject(child));
                    }
                    data.put(key, new Map<String, Object>{ 'totalSize' => childList.size(), 'records' => childList });
                } else if (value instanceof SObject) {
                    data.put(key, mapSObject((SObject) value));
                } else if (value instanceof Address) {
                     Address addr = (Address) value;
                     data.put(key, new Map<String, Object>{
                         'street' => addr.getStreet(),
                         'city' => addr.getCity(), 
                         'state' => addr.getState(),
                         'postalCode' => addr.getPostalCode(),
                         'country' => addr.getCountry()
                     });
                } else if (value instanceof Location) {
                     Location loc = (Location) value;
                     data.put(key, new Map<String, Object>{
                         'latitude' => loc.getLatitude(),
                         'longitude' => loc.getLongitude()
                     });
                } else {
                    data.put(key, value);
                }
            } catch (Exception e) {
                // Skip this field but allow others
            }
        }

        return data;
    }
}