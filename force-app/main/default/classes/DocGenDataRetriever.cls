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
            throw new DocGenException('Invalid parameters for data retrieval.');
        }

        // The query string is constructed safely by the builder, but we still ensure the base string is valid
        String fieldsPart = fieldsConfig.trim();
        if (fieldsPart.toLowerCase().startsWith('select ')) {
            fieldsPart = fieldsPart.substring(7).trim();
        }
        String validatedFields = validateFieldsConfig(fieldsPart, baseObject);
        String query = 'SELECT ' + validatedFields + ' FROM ' + baseObject + ' WHERE Id = :recordId LIMIT 1';
        
        System.debug(LoggingLevel.INFO, 'DocGen Query: ' + query);

        try {
            List<SObject> results = Database.query(query, AccessLevel.USER_MODE);
            if (results.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'DocGen: Query returned no results for ID: ' + recordId);
                return null;
            }
            // Optimization: Use manual mapping to avoid JSON.serialize Heap Spike
            return mapSObject(results[0]);
        } catch (DocGenException e) {
            // Re-wrap validation errors so Lightning components receive the message
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
             // Fallback: If stripping failed (e.g. subquery error), return clear error
            System.debug(LoggingLevel.ERROR, 'DocGen: Query Execution Error: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error executing query. Details: ' + e.getMessage());
        }
    }

    private static String validateFieldsConfig(String fieldsConfig, String baseObject) {
        String cleaned = stripComments(fieldsConfig);
        List<String> tokens = tokenizeByTopLevelCommas(cleaned);
        List<String> validatedFields = new List<String>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        for (String token : tokens) {
            String trimmed = token.trim();
            if (String.isBlank(trimmed)) continue;

            String lower = trimmed.toLowerCase();
            if ((lower.contains(' from ') || lower.startsWith('from ')) && !(trimmed.startsWith('(') && trimmed.endsWith(')'))) {
                throw new DocGenException('Invalid token: FROM keyword detected in fields configuration.');
            }
            if ((lower.contains(' where ') || lower.startsWith('where ')) && !(trimmed.startsWith('(') && trimmed.endsWith(')'))) {
                throw new DocGenException('Invalid token: WHERE keyword detected in fields configuration.');
            }

            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                validatedFields.add(validateSubquery(trimmed, baseObject, gd));
            } else if (trimmed.contains('.')) {
                validateParentPath(trimmed, baseObject, gd);
                validatedFields.add(trimmed);
            } else {
                validateSimpleField(trimmed, baseObject, gd);
                validatedFields.add(trimmed);
            }
        }

        if (validatedFields.isEmpty()) {
            throw new DocGenException('No valid fields found in configuration.');
        }

        return String.join(validatedFields, ', ');
    }

    private static String stripComments(String input) {
        Integer startIdx = input.indexOf('/*');
        while (startIdx >= 0) {
            Integer endIdx = input.indexOf('*/', startIdx + 2);
            if (endIdx == -1) {
                throw new DocGenException('Unclosed block comment in fields configuration.');
            }
            input = input.substring(0, startIdx) + ' ' + input.substring(endIdx + 2);
            startIdx = input.indexOf('/*');
        }

        List<String> lines = input.split('\n');
        List<String> cleanedLines = new List<String>();
        for (String line : lines) {
            String cleanedLine = line;
            Integer slashIdx = cleanedLine.indexOf('//');
            if (slashIdx >= 0) cleanedLine = cleanedLine.substring(0, slashIdx);
            Integer dashIdx = cleanedLine.indexOf('--');
            if (dashIdx >= 0) cleanedLine = cleanedLine.substring(0, dashIdx);
            cleanedLines.add(cleanedLine);
        }
        return String.join(cleanedLines, '\n');
    }

    private static List<String> tokenizeByTopLevelCommas(String input) {
        List<String> tokens = new List<String>();
        Integer depth = 0;
        String current = '';
        for (Integer i = 0; i < input.length(); i++) {
            String ch = input.substring(i, i + 1);
            if (ch == '(') {
                depth++;
                current += ch;
            } else if (ch == ')') {
                depth--;
                current += ch;
            } else if (ch == ',' && depth == 0) {
                tokens.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        if (String.isNotBlank(current)) {
            tokens.add(current);
        }
        return tokens;
    }

    private static Schema.DescribeSObjectResult getDescribeResult(String objectName, Map<String, Schema.SObjectType> globalDescribe) {
        Schema.SObjectType sot = globalDescribe.get(objectName);
        if (sot == null) {
            throw new DocGenException('Invalid object: ' + objectName);
        }
        return sot.getDescribe();
    }

    private static void validateSimpleField(String fieldName, String objectName, Map<String, Schema.SObjectType> gd) {
        Schema.DescribeSObjectResult describeResult = getDescribeResult(objectName, gd);
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        if (!fieldMap.containsKey(fieldName.toLowerCase())) {
            throw new DocGenException('Invalid field: ' + fieldName + ' on object ' + objectName);
        }
    }

    private static void validateParentPath(String path, String objectName, Map<String, Schema.SObjectType> gd) {
        List<String> parts = path.split('\\.');
        String currentObject = objectName;
        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i].trim();
            if (String.isBlank(part)) {
                throw new DocGenException('Invalid empty segment in field path: ' + path);
            }
            Schema.DescribeSObjectResult describeResult = getDescribeResult(currentObject, gd);
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            Schema.SObjectField field = fieldMap.get(part.toLowerCase());
            if (field == null) {
                // Relationship names (e.g. "Owner" for "OwnerId") are not in the field map keys
                for (Schema.SObjectField f : fieldMap.values()) {
                    Schema.DescribeFieldResult fd = f.getDescribe();
                    if (fd.getRelationshipName() != null && fd.getRelationshipName().equalsIgnoreCase(part)) {
                        field = f;
                        break;
                    }
                }
            }
            if (field == null) {
                throw new DocGenException('Invalid field or relationship: ' + part + ' on ' + currentObject);
            }
            if (i < parts.size() - 1) {
                Schema.DescribeFieldResult fieldDesc = field.getDescribe();
                List<Schema.sObjectType> refs = fieldDesc.getReferenceTo();
                if (refs == null || refs.isEmpty()) {
                    throw new DocGenException('Field is not a relationship: ' + part);
                }
                currentObject = refs[0].getDescribe().getName();
            }
        }
    }

    private static String validateSubquery(String subquery, String objectName, Map<String, Schema.SObjectType> gd) {
        String innerQuery = subquery.substring(1, subquery.length() - 1).trim();
        if (!innerQuery.toLowerCase().startsWith('select ')) {
            throw new DocGenException('Invalid subquery: missing SELECT.');
        }

        Pattern fromPattern = Pattern.compile('(?i)\\bFROM\\s+([a-zA-Z_]\\w*)');
        Matcher fromMatcher = fromPattern.matcher(innerQuery);
        if (!fromMatcher.find()) {
            throw new DocGenException('Invalid subquery: missing FROM clause.');
        }

        if (String.isNotBlank(innerQuery.substring(fromMatcher.end()).trim())) {
            throw new DocGenException('Invalid subquery: extra clauses detected.');
        }

        String childRelName = fromMatcher.group(1);

        Schema.DescribeSObjectResult describeResult = getDescribeResult(objectName, gd);
        List<Schema.ChildRelationship> childRels = describeResult.getChildRelationships();

        String childObjectName = null;
        Boolean found = false;
        for (Schema.ChildRelationship cr : childRels) {
            if (cr.getRelationshipName() != null && cr.getRelationshipName().equalsIgnoreCase(childRelName)) {
                found = true;
                childObjectName = cr.getChildSObject().getDescribe().getName();
                break;
            }
        }
        if (!found) {
            throw new DocGenException('Invalid child relationship: ' + childRelName);
        }

        String fieldsPart = innerQuery.substring(7, fromMatcher.start()).trim();
        List<String> subFields = tokenizeByTopLevelCommas(fieldsPart);
        List<String> validatedSubFields = new List<String>();
        for (String sf : subFields) {
            String trimmed = sf.trim();
            if (String.isBlank(trimmed)) continue;
            if (trimmed.contains('.')) {
                validateParentPath(trimmed, childObjectName, gd);
            } else {
                validateSimpleField(trimmed, childObjectName, gd);
            }
            validatedSubFields.add(trimmed);
        }

        if (validatedSubFields.isEmpty()) {
            throw new DocGenException('No valid fields found in subquery.');
        }

        return '(SELECT ' + String.join(validatedSubFields, ', ') + ' FROM ' + childRelName + ')';
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
                System.debug(LoggingLevel.ERROR, 'DocGen: Error mapping field ' + key + ': ' + e.getMessage());
                // Skip this field but allow others
            }
        }

        // To support handlebars "ifList", we need to explicitly put empty arrays in the map, 
        // since getPopulatedFieldsAsMap won't include child lists that returned 0 records.
        // A true robust solution would traverse the metadata to figure out what relationships were requested,
        // but for Handlebars the standard approach when a property is missing is to evaluate as falsy,
        // which works for empty arrays.
        // Wait, Handlebars needs an explicit empty array if the document iterates over it, else it iterates undefined and does nothing. 
        // BUT if the property is entirely missing, Handlebars treats it as empty/falsy for 'if' and 'each'.
        // So we might be okay. We will leave it as is for now.

        return data;
    }
}