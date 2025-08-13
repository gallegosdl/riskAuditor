/**
 * @description Service class for describing and querying Permission Sets and related permissions
 * This class provides utilities for retrieving permission information from Salesforce
 * and handling pagination for larger data sets.
 */
public with sharing class PermissionSetDescribeService {
    
    /**
     * @description Represents a permission field with comparable functionality
     * for sorting permission fields alphabetically by label
     */
    public class PermField implements Comparable {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label { get; set; }
        
        /**
         * @description Constructor to create a new PermField instance
         * @param apiName API name of the permission field
         * @param label User-friendly label of the permission field
         */
        public PermField(String apiName, String label) {
            this.apiName = apiName;
            this.label = label;
        }
        
        /**
         * @description Implementation of Comparable interface to enable sorting
         * @param compareTo Object to compare against (should be another PermField)
         * @return Integer representing sort order (-1, 0, or 1)
         */
        public Integer compareTo(Object compareTo) {
            PermField compareToField = (PermField)compareTo;
            return this.label.compareTo(compareToField.label);
        }
    }
    
    /**
     * @description Represents a row in the permission matrix displaying
     * permissions for profiles and permission sets
     */
    public class MatrixRow {
        @AuraEnabled public String permissionApi { get; set; }     // API name of the permission
        @AuraEnabled public String permissionLabel { get; set; }   // User-friendly label of the permission
        @AuraEnabled public Id permissionSetId { get; set; }       // ID of the permission set
        @AuraEnabled public String permissionSetLabel { get; set; } // Label of the permission set
        @AuraEnabled public Id profileId { get; set; }             // ID of the profile if applicable
        @AuraEnabled public String profileName { get; set; }       // Name of the profile if applicable
    }
    
    /**
     * @description Container for paginated results
     * Provides metadata for pagination controls in the UI
     */
    public class PageResult {
        @AuraEnabled public List<MatrixRow> items { get; set; }    // Collection of matrix rows for current page
        @AuraEnabled public Integer total { get; set; }            // Total number of records available
        @AuraEnabled public Integer page { get; set; }             // Current page number
        @AuraEnabled public Integer pageSize { get; set; }         // Number of records per page
        @AuraEnabled public Boolean hasMore { get; set; }          // Whether more pages exist
    }
    
    /**
     * @description Retrieves all boolean permission fields from PermissionSet object
     * These are fields that start with "Permissions" and are of Boolean type
     * @return List<PermField> Sorted list of permission fields with API names and labels
     */
    @AuraEnabled(cacheable=true)
    public static List<PermField> getPermissionBooleans() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.PermissionSet.fields.getMap();
        List<PermField> permFields = new List<PermField>();
        
        // Debug the field map size
        System.debug('Permission field map size: ' + fieldMap.size());
        
        // For all fields that start with 'Permissions' and are boolean
        for (String fieldName : fieldMap.keySet()) {
            System.debug('Examining field: ' + fieldName);
            if (fieldName.startsWith('permissions')) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (fieldDescribe.getType() == Schema.DisplayType.Boolean) {
                    System.debug('Adding field: ' + fieldName + ', type: ' + fieldDescribe.getType());
                    permFields.add(new PermField(fieldName, fieldDescribe.getLabel()));
                }
            }
        }
        
        // If nothing was found, fallback to known permissions
        if (permFields.isEmpty()) {
            System.debug('No permission fields found automatically, using fallback list');
            List<String> knownPermFields = new List<String>{
                'PermissionsModifyAllData', 
                'PermissionsViewAllData',
                'PermissionsManageUsers',
                'PermissionsEditTask',
                'PermissionsEditEvent'
                // Add more known permission fields here
            };
            
            for (String knownField : knownPermFields) {
                if (fieldMap.containsKey(knownField)) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(knownField).getDescribe();
                    permFields.add(new PermField(knownField, fieldDescribe.getLabel()));
                }
            }
        }
        
        // Sort the fields by label for user-friendly display
        permFields.sort();
        System.debug('permFields count: ' + permFields.size());
        
        // Debug the first few entries without using subList
        if (permFields.size() > 0) {
            System.debug('First permission field: ' + permFields[0].apiName);
            if (permFields.size() > 1) System.debug('Second permission field: ' + permFields[1].apiName);
            if (permFields.size() > 2) System.debug('Third permission field: ' + permFields[2].apiName);
        }
        
        return permFields;
    }

    /**
     * @description Retrieves profiles with a specific permission, with pagination support
     * @param permissionApi API name of the permission to filter by
     * @param pageNum Current page number (1-based)
     * @param pageSize Number of records per page
     * @return PageResult Container with paginated results and pagination metadata
     * @throws AuraHandledException if permissionApi is blank
     */
    @AuraEnabled(cacheable=true)
    public static PageResult getProfilesWithPermission(String permissionApi, Integer pageNum, Integer pageSize) {
        // Input validation
        if (String.isBlank(permissionApi)) {
            throw new AuraHandledException('Permission API name cannot be blank');
        }
        
        // Default pagination values if not provided
        if (pageNum <= 0) {
            pageNum = 1;
        }
        
        if (pageSize <= 0 || pageSize > 1000) {
            pageSize = 25; // Default reasonable limit
        }
        
        // Calculate offset for pagination
        Integer offset = (pageNum - 1) * pageSize;
        
        // Dynamic SOQL to filter profiles with the specific permission set to true
        String soql = 'SELECT Id, Label, ProfileId, Profile.Name FROM PermissionSet ' +
                    'WHERE IsOwnedByProfile = true AND ProfileId != null AND ' + 
                    permissionApi + ' = true ' +
                    'ORDER BY Profile.Name LIMIT ' + pageSize + ' OFFSET ' + offset;
        
        System.debug('Executing SOQL: ' + soql);
        
        // Count total matching records for pagination metadata
        String countSoql = 'SELECT COUNT() FROM PermissionSet ' +
                        'WHERE IsOwnedByProfile = true AND ProfileId != null AND ' + 
                        permissionApi + ' = true';
                        
        Integer totalCount = Database.countQuery(countSoql);
        System.debug('Total matching profiles: ' + totalCount);
        
        // Query for paginated profiles with the specified permission
        List<PermissionSet> permSets = Database.query(soql);
        System.debug('Found permission sets: ' + permSets.size());
        
        // Transform query results to MatrixRows for display
        List<MatrixRow> rows = new List<MatrixRow>();
        for (PermissionSet ps : permSets) {
            MatrixRow row = new MatrixRow();
            row.permissionApi = permissionApi;
            
            // Get the permission label from the field describe
            Schema.DescribeFieldResult fieldDescribe = 
                Schema.SObjectType.PermissionSet.fields.getMap().get(permissionApi).getDescribe();
            row.permissionLabel = fieldDescribe.getLabel();
            
            row.permissionSetId = ps.Id;
            row.permissionSetLabel = ps.Label;
            row.profileId = ps.ProfileId;
            row.profileName = ps.Profile.Name;
            rows.add(row);
        }
        
        // Build and return page result with pagination metadata
        PageResult result = new PageResult();
        result.items = rows;
        result.total = totalCount;
        result.page = pageNum;
        result.pageSize = pageSize;
        result.hasMore = (offset + pageSize < totalCount);
        
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static String getErrorMessage(String errorCode, String permissionApi, Integer recordCount) {
        // Using standard String.format method
        return String.format('{0}: Unable to fetch {1} permission data. Found {2} records.',
            new List<String>{errorCode, permissionApi, String.valueOf(recordCount)});
    }


}
