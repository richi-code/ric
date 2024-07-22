public with sharing class CaseAssignmentService {

    public static Map<String, Id> queueIdByName;
    public static Map<String, List<String>> queueNameToEmailAddresses;
    public static Map<String, String> queueNameBySalesRegion;
    private static Map<Id, User> usersMap;
    public static Map<String,Set<Id>> userAMRegionMap;

    private static final List<Id> NOT_APPLICABLE_CASE_RECORDTYPE_IDS = new List<Id>{
        Schema.SObjectType.Case.getRecordTypeInfosByName().get('Bizops').getRecordTypeId(),
        Schema.SObjectType.Case.getRecordTypeInfosByName().get('Legal').getRecordTypeId(),
		Schema.SObjectType.Case.getRecordTypeInfosByName().get('Fraud Escalation').getRecordTypeId(),
        Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Termination Request').getRecordTypeId(),
		Schema.SObjectType.Case.getRecordTypeInfosByName().get('Renewals').getRecordTypeId()
        
    };
    public static final String QUEUE_NAME_IMPLEMENTATION = 'Implementation';
    public static final String QUEUE_NAME_GLOBALSUPPORT = 'Global Support';
    public static final String QUEUE_NAME_ONBOARDINGJAPAN = 'Onboarding Japan';
    public static final String QUEUE_NAME_FINANCE = 'Finance';
    public static final String QUEUE_NAME_INTEGRATIONS = 'Integrations';
    public static final String QUEUE_NAME_RENEWALS = 'Renewals Case Queue';
    public static final String QUEUE_NAME_PRODUCT_SPECIALISTS = 'Product Specialists';
    public static final String QUEUE_NAME_SUPPORT_EMEA = 'Support EMEA';
    public static final String QUEUE_NAME_SUPPORT_APAC = 'Support APAC';
    public static final String QUEUE_NAME_SUPPORT_SEA = 'Support SEA';
    public static final String QUEUE_NAME_SUPPORT_JAPAN = 'Support Japan';
    public static final String QUEUE_NAME_SUPPORT_US = 'Support US';
    public static final String QUEUE_NAME_ACQUIRED_SUPPORT = 'Acquired support';
    public static final String QUEUE_NAME_FRAUD_SUPPORT = 'Fraud';
    public static final String SUBJECT_OF_NEW_PARTNER_INTEGRATION = 'New partner for Campaign Wizard:';
    public static final String ACOUNT_LINE_FOR_NEW_PARTNER_INTEGRATION = 'https://adjust.my.salesforce.com/';
    public static final String FROM_ADRESS_DOMAIN_FOR_NEW_PARTNER_INTEGRATION = '@adjust.com';
    private static final Id INTEGRATIONS_USER_ROLE_ID = [SELECT Id, Name FROM UserRole WHERE Name =: QUEUE_NAME_INTEGRATIONS].Id;

    public static final Time GMT_START_TIME_EMEA = Time.newInstance(7, 0, 0, 0);
    public static final Time GMT_START_TIME_US = Time.newInstance(15, 0, 0, 0);
    public static final Time GMT_START_TIME_APAC = Time.newInstance(23, 0, 0, 0);

    public static Map<Id, Map<Id, CaseTeamMember>> CASE_OWNERS_BY_TEAM;
    public static Map<String, BusinessHours> BUSINESS_HOURS_BY_NAME;
    public static Map<String, String> REGION_TO_BUSINESS_HOURS_MAP;

    public static boolean isOOOLogic =false;

    @TestVisible
   private static void initCaseOwnersByTeam() {	
    List<String> oooEnabledTeamNames = new List<String>();
    for (OutOfOfficeEnabledTeam__mdt oooTeam : [SELECT Id, MasterLabel FROM OutOfOfficeEnabledTeam__mdt]) {
        oooEnabledTeamNames.add(oooTeam.MasterLabel);
    }

    usersMap = new Map<Id, User>([
        SELECT Id, UserRoleId,  AM_Entitlement_Region__c,Sub_AM_Regions__c,AM_Region__c
        FROM User
        WHERE IsActive = true
            AND (
                OutOfOfficeEndDateTime__c = null 
                OR OutOfOfficeEndDateTime__c < :System.now()
                OR OutOfOfficeStartDateTime__c = null
                OR OutOfOfficeStartDateTime__c > :System.now()
            )
            AND UserRole.Name IN :oooEnabledTeamNames
            AND IncludeInOooReassignment__c = true
    ]);
     
    system.debug('Maap==' + usersMap);
     
    CASE_OWNERS_BY_TEAM = new Map<Id, Map<Id, CaseTeamMember>>();

    for (User u : usersMap.values()) {
        if (!CASE_OWNERS_BY_TEAM.containsKey(u.UserRoleId)) {
            CASE_OWNERS_BY_TEAM.put(u.UserRoleId, new Map<Id, CaseTeamMember>());
        }
        CASE_OWNERS_BY_TEAM.get(u.UserRoleId).put(u.Id, new CaseTeamMember(u.Id, 0));
    }

    for (AggregateResult ar : [
        SELECT SUM(Score_Calculate__c) totalScore, OwnerId ownerId, RecordTypeId
        FROM Case
        WHERE OwnerId IN :usersMap.keySet()
            AND (
                (Status IN ('Open', 'New', 'Follow Up', 'Snoozed'))
                OR (Status = 'Pending' AND IsReassignedAutomatically__c = true)
            )
            AND RecordTypeId NOT IN :NOT_APPLICABLE_CASE_RECORDTYPE_IDS
        GROUP BY OwnerId, RecordTypeId
    ]) {
        Id ownerId = (Id)ar.get('ownerId');
        Decimal totalScore = (Decimal)ar.get('totalScore');

        User u = usersMap.get(ownerId);
       CASE_OWNERS_BY_TEAM.get(u.UserRoleId).get(u.Id).totalScore = totalScore;
       System.debug('CASE_OWNERS_BY_TEAM'+CASE_OWNERS_BY_TEAM);
    }
}


    public static List<Case> checkForNeedToReassign(List<Case> cases) {
        if (CASE_OWNERS_BY_TEAM == null) {
            initCaseOwnersByTeam();
        }
        List<Id> ids = new List<Id>();
        List<Id> accountIds = new List<Id>();
        List<Case> updatedCases = new List<Case>();
        for (Case c : cases) {
            ids.add(c.OwnerId);
            accountIds.add(c.AccountId);
        }
        Map<Id, User> users = new Map<Id, User> ([
            SELECT Id, UserRoleId, UserRole.Name, IsActive, OutOfOfficeStartDateTime__c, OutOfOfficeEndDateTime__c, AM_Entitlement_Region__c
            FROM User
            WHERE Id IN :ids 
        ]);
        Map<Id, Account> accounts = new Map<Id, Account> ([
            SELECT 
                Id,
            	SupportRegionPicklist__c,
            	Case_Assignment_Region__c,
                Account_Manager__r.Id,
                Account_Manager__r.AM_Entitlement_Region__c,
                Account_Manager__r.UserRoleId,
                Account_Manager__r.IsActive,
                Account_Manager__r.OutOfOfficeStartDateTime__c,
                Account_Manager__r.OutOfOfficeEndDateTime__c,
                UseSecondAccountManager__c,
                HolidayStartDateTime__c,
                HolidayEndDateTime__c,
                HolidayAccountManager__c,
                HolidayAccountManager__r.Id,
                HolidayAccountManager__r.UserRoleId,
                HolidayAccountManager__r.IsActive,
                HolidayAccountManager__r.OutOfOfficeStartDateTime__c,
                HolidayAccountManager__r.OutOfOfficeEndDateTime__c,
                HolidayAccountManager__r.AM_Entitlement_Region__c,
                IgnoreSalesRegionInCaseAssignment__c
            FROM Account 
            WHERE Id IN :accountIds
        ]);

        for (Case c : cases) {
            if (c.OwnerId.getSobjectType() != Schema.User.SObjectType || NOT_APPLICABLE_CASE_RECORDTYPE_IDS.contains(c.RecordTypeId)) {
                continue;
            }
            CaseAssignment ca = new CaseAssignment(
                c, accounts.get(c.AccountId)
            );
            Boolean needsToBeReassigned = ca.isNeedToReassign(users.get(c.OwnerId));
            if (!needsToBeReassigned) {
                continue;
            }
           // ca.isFromOOOLogic=true;
            ca.reassign(users.get(c.OwnerId));
           //ca.assignToTeamMembers(users.get(c.OwnerId));
            updatedCases.add(ca.c);
        }
        return updatedCases;
    }

    @future
    public static void assignBasedOnSocialPost(List<Id> socialPostIds) {
        if (CASE_OWNERS_BY_TEAM == null) {
            initCaseOwnersByTeam();
        }
        if (BUSINESS_HOURS_BY_NAME == null) {
            initBusinessHours();
        }
        List<Case> cases = fetchCaseRecordsFromSocialPosts(socialPostIds);

        for (Case c : cases) {
            if(NOT_APPLICABLE_CASE_RECORDTYPE_IDS.contains(c.RecordTypeId)){
                continue;
            }
            CaseAssignment ca = new CaseAssignment(
                c
            );
            ca.assign();
        }
        update cases;
    }
    
    @future
    public static void assignCasesFromWeb(Set<Id> casesFromWebIds) {
        list<case> caseToAssign= new list<case>();
        
        
        if (CASE_OWNERS_BY_TEAM == null) {
            initCaseOwnersByTeam();
        }
       
        if (BUSINESS_HOURS_BY_NAME == null) {
            initBusinessHours();
        }
        List<Case> casesFromWeb = CaseService.retrieveCasesWithAssignmentDetails(casesFromWebIds);
        for(case c: casesFromWeb){
            if(c.Belongs_to_Implementation_Queue__c	== true || c.Belongs_to_Onboarding_Japan_Queue__c== true){
                continue;
            }
            caseToAssign.add(c);

        }
        for (Case c : caseToAssign) {
            
            if(NOT_APPLICABLE_CASE_RECORDTYPE_IDS.contains(c.RecordTypeId)){
                continue;
            }
            CaseAssignment ca = new CaseAssignment(
                c
            );
            System.debug(c);
            ca.assign();
            
        }
        update caseToAssign;
    }

    private static List<Case> fetchCaseRecordsFromSocialPosts(List<Id> socialPostIds) {
        Map<Id, Id> caseIdBySocialPostId = new Map<Id, Id>();
        for (SocialPost sp : [
            SELECT Id, ParentId
            FROM SocialPost
            WHERE Id IN :socialPostIds
        ]) {
            caseIdBySocialPostId.put(sp.Id, sp.ParentId);
        }
        return CaseService.retrieveCasesWithAssignmentDetails(new Set<Id>(caseIdBySocialPostId.values()));
    }

    @future
    public static void assignBasedOnEmailMessage(List<Id> emailMessageIds) {
        if (CASE_OWNERS_BY_TEAM == null) {
            initCaseOwnersByTeam();
        }
        if (BUSINESS_HOURS_BY_NAME == null) {
            initBusinessHours();
        }
        Set<Id> caseId=new Set<Id>(); 
        Map<EmailMessage, Case> emailMessageToCase = fetchCaseRecordsFromEmails(emailMessageIds);
        Map<Id, List<User>> emailMessageIdToRecipients = fetchRecipients(emailMessageToCase.keySet());
        Map<Id, Account> emailMessageIdToPartnerAccount = fetchPartnerAccounts(emailMessageToCase.keySet());
        Map<Id, Contact> accountIdToContactForIntegration = fetchContactsForIntegrations(emailMessageToCase.keySet());
        for (EmailMessage em : emailMessageToCase.keySet()) {
            if (emailMessageIdToRecipients.get(em.Id) == null) {
                system.debug('@@@@id'+em.Id);
                system.debug('####'+emailMessageIdToRecipients.get(em.Id));
                continue;
            }
            if(em.PareNtId!=null ){
               caseId.add(em.ParentId);
            }
            If(em.CcAddress != Null && em.parent.Account.Account_Manager__c == Null){
                If(em.parent.Account.Case_Assignment_Region__c == 'EMEA' ||
                   em.parent.Account.Case_Assignment_Region__c == 'Global Support' ||
                   em.parent.Account.Case_Assignment_Region__c == 'US-SF' ||
                   em.parent.Account.Case_Assignment_Region__c == 'UK'){
                       If(!em.parent.Account.Freemium__c && em.parent.Account.Signed_Up_Date__c >= Date.today().addMonths(-6)){
                           em.parent.ownerId = CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_IMPLEMENTATION);
                           continue;
                       }
                       If(em.parent.Account.Freemium__c){
                           em.parent.ownerId = CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_GLOBALSUPPORT);
                           continue;
                       }
                   }
                If( em.parent.Account.Signed_Up_Date__c >= Date.today().addMonths(-6) && 
                   em.parent.Account.Case_Assignment_Region__c == 'Japan' && !em.parent.Account.Freemium__c){
                    em.parent.ownerId = CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_ONBOARDINGJAPAN);
                    continue;
                }
            }
            CaseAssignment ca = new CaseAssignment(
                emailMessageToCase.get(em), em, emailMessageIdToRecipients.get(em.Id), emailMessageIdToPartnerAccount.get(em.Id)
            );
            ca.setTechContactMap(accountIdToContactForIntegration);
            ca.assign();
        }
        update emailMessageToCase.values();
        if(!caseId.isEmpty()){
            setStatusToSpam(caseId);
        }
    }
    
    public static void setStatusToSpam(Set<Id> caseId){
        List<Case> caseStatusUpdated = new List<Case>();
        if(!caseId.isEmpty()){
            Group supportUSQueuesId = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Support US' LIMIT 1];
            for(Case cs:[Select Id,Subject, status,Owner.Name From Case Where Id=:caseId]){
                if( cs.Subject.contains(Label.Auto_spamming_Subject) && (cs.OwnerId==supportUSQueuesId.Id ||cs.Owner.Name==QUEUE_NAME_SUPPORT_EMEA ||cs.Owner.Name==QUEUE_NAME_SUPPORT_US)){
                    cs.status='Spam';
                    caseStatusUpdated.add(cs);
                }
            }
            if(!caseStatusUpdated.isEmpty()){
                Update caseStatusUpdated;
            }
        }
    }
    private static Map<EmailMessage, Case> fetchCaseRecordsFromEmails(List<Id> emailMessageIds) {
        Set<string> emailCCAddress = New Set<string>();
        Set<string> conEmail = New Set<string>();
        If(!emailMessageIds.isEmpty()){
            For(EmailMessage em : [Select Id,FromAddress,CcAddress From EmailMessage 
                                    WHERE Id IN :emailMessageIds AND CcAddress != NULL]){
                emailCCAddress.add(em.CcAddress);
            }
        }
        If(!emailMessageIds.isEmpty()){
            List<Contact> conList = [Select Id,Email, AccountId,Account.Id From Contact Where Email =: emailCCAddress];
            For(Contact cn : conList){
                conEmail.add(cn.Email);
            }
        }
        
        Map<string, Contact> emailToContact = getContactByEmail(conEmail);
        Map<EmailMessage, Case> emailMessageToCase = new Map<EmailMessage, Case>();
        for (EmailMessage em : [
            SELECT Id, Subject, TextBody, ToAddress, FromAddress, CcAddress, ParentId, Parent.Id,
            Parent.CreatedDate, Parent.AccountId, Parent.OwnerId, Parent.Account.Freemium__c,
            Parent.Account.SupportRegionPicklist__c, Parent.Account.Account_Manager__c, 
            Parent.Account.Case_Assignment_Region__c, Parent.Account.HolidayAccountManager__c,
            Parent.Account.IgnoreBlankAccountManager__c, Parent.Account.IgnoreSalesRegionInCaseAssignment__c,
            Parent.Account.Account_Manager__r.Id, Parent.Account.Signed_Up_Date__c,
            Parent.Account.Account_Manager__r.AM_Entitlement_Region__c,
            Parent.Account.Account_Manager__r.UserRoleId,
            Parent.Account.Account_Manager__r.IsActive,
            Parent.Account.Account_Manager__r.OutOfOfficeStartDateTime__c,
            Parent.Account.Account_Manager__r.OutOfOfficeEndDateTime__c,
            Parent.Account.HolidayAccountManager__r.Id,
            Parent.Account.HolidayAccountManager__r.UserRoleId,
            Parent.Account.HolidayAccountManager__r.IsActive,
            Parent.Account.HolidayAccountManager__r.OutOfOfficeStartDateTime__c,
            Parent.Account.HolidayAccountManager__r.OutOfOfficeEndDateTime__c,
            Parent.Account.HolidayAccountManager__r.AM_Entitlement_Region__c,
            Parent.Account.HolidayStartDateTime__c,
            Parent.Account.HolidayEndDateTime__c,
            Parent.Account.X2nd_Account_Manager__c,
            Parent.Account.X2nd_Account_Manager__r.Id,
            Parent.Account.X2nd_Account_Manager__r.AM_Entitlement_Region__c,
            Parent.Account.X2nd_Account_Manager__r.UserRoleId,
            Parent.Account.X2nd_Account_Manager__r.IsActive,
            Parent.Account.X2nd_Account_Manager__r.OutOfOfficeStartDateTime__c,
            Parent.Account.X2nd_Account_Manager__r.OutOfOfficeEndDateTime__c,
            Parent.Account.UseSecondAccountManager__c,
            Parent.Account.Client_Summary__c, Parent.contact.Id
            FROM EmailMessage
            WHERE Id IN :emailMessageIds
            AND Parent.RecordTypeId NOT IN :NOT_APPLICABLE_CASE_RECORDTYPE_IDS
        ]) {
            If(em.CcAddress != Null && conEmail.contains(em.CcAddress) && (em.ToAddress.contains('@paramyter.tech')==true
                                                    || em.ToAddress.contains('@adjust.com')==true
                                                    || em.ToAddress.contains('@adeven.com')==true
                                                    || em.ToAddress.contains('@support.adjust.com')==true)){
                                                        
                                                        Case parentCase = em.Parent;
                                                        Contact matchingContact = emailToContact.get(em.CcAddress);
                                                        
                                                        parentCase.contactId = matchingContact.Id;
                                                        parentCase.contact = matchingContact;
                                                        parentCase.accountId = matchingContact.accountId;
                                                        parentCase.account = matchingContact.account;
                                                        emailMessageToCase.put(em, parentCase);
                                                    }
            										Else{
                                                        emailMessageToCase.put(em, em.Parent);
                                                    }
        }
        return emailMessageToCase;
    }
    
    private static Map<String,Contact> getContactByEmail(Set<String> email) {
        Map<String,Contact> emailToContact = New Map<String,Contact>();
        List<Contact> matchingContacts = [SELECT Id, Email, AccountId, Account.Account_Manager__c,
                                          CreatedDate, OwnerId, Account.Freemium__c,
                                          Account.Case_Assignment_Region__c, Account.HolidayAccountManager__c,
                                          Account.IgnoreBlankAccountManager__c, Account.IgnoreSalesRegionInCaseAssignment__c,
                                          Account.Account_Manager__r.Id, Account.Signed_Up_Date__c,
                                          Account.Account_Manager__r.AM_Entitlement_Region__c,
                                          Account.Account_Manager__r.UserRoleId,
                                          Account.Account_Manager__r.IsActive,
                                          Account.Account_Manager__r.OutOfOfficeStartDateTime__c,
                                          Account.Account_Manager__r.OutOfOfficeEndDateTime__c,
                                          Account.HolidayAccountManager__r.Id,
                                          Account.SupportRegionPicklist__c,
                                          Account.HolidayAccountManager__r.UserRoleId,
                                          Account.HolidayAccountManager__r.IsActive,
                                          Account.HolidayAccountManager__r.OutOfOfficeStartDateTime__c,
                                          Account.HolidayAccountManager__r.OutOfOfficeEndDateTime__c,
                                          Account.HolidayAccountManager__r.AM_Entitlement_Region__c,
                                          Account.HolidayStartDateTime__c,
                                          Account.HolidayEndDateTime__c,
                                          Account.X2nd_Account_Manager__c,
                                          Account.X2nd_Account_Manager__r.Id,
                                          Account.X2nd_Account_Manager__r.AM_Entitlement_Region__c,
                                          Account.X2nd_Account_Manager__r.UserRoleId,
                                          Account.X2nd_Account_Manager__r.IsActive,
                                          Account.X2nd_Account_Manager__r.OutOfOfficeStartDateTime__c,
                                          Account.X2nd_Account_Manager__r.OutOfOfficeEndDateTime__c,
                                          Account.UseSecondAccountManager__c,
                                          Account.Client_Summary__c
                                          FROM Contact WHERE Email = :email];
        If(!matchingContacts.isEmpty()){
            For(Contact cn : matchingContacts){
                emailToContact.put(cn.email,cn);
            }
        }
        return (!emailToContact.isEmpty()) ? emailToContact : null;
    }

    private static Map<Id, List<User>> fetchRecipients(Set<EmailMessage> emailMessages) {
        Map<Id, Set<String>> emailMessageIdToRecipients = new Map<Id, Set<String>>();
        Set<String> recipientAddresses = new Set<String>();
        for (EmailMessage em : emailMessages) {
            Set<String> emailAddresses = new Set<String>();
            if (em.ToAddress != null) {
                for (String s : em.ToAddress.split(';')) {
                    emailAddresses.add(s.trim());
                }
            }
            if (em.CcAddress != null) {
                for (String s : em.CcAddress.split(';')) {
                    emailAddresses.add(s.trim());
                }
            }
            recipientAddresses.addAll(emailAddresses);
            emailMessageIdToRecipients.put(em.Id, emailAddresses);
        }

        Map<String, User> usersByEmailAddress = new Map<String, User>();
        for (User u : [
            SELECT Id, IsActive, Email,Old_Email__c, OutOfOfficeStartDateTime__c, OutOfOfficeEndDateTime__c, UserRoleId, AM_Entitlement_Region__c
            FROM User
            WHERE (Email IN :recipientAddresses OR Old_Email__c IN :recipientAddresses)
                AND (Email LIKE '%@support.adjust.com' OR Old_Email__c LIKE '%@support.adjust.com')
        ]) {
            String emailAddress;
            if (recipientAddresses.contains(u.Email)) {
                emailAddress = u.Email;
            } else if (recipientAddresses.contains(u.Old_Email__c)) {
                emailAddress = u.Old_Email__c;
            }
            usersByEmailAddress.put(emailAddress, u);
        }

        Map<Id, List<User>> emailMessageIdToRecipientUsers = new Map<Id, List<User>>();
        for (Id emId : emailMessageIdToRecipients.keySet()) {
            emailMessageIdToRecipientUsers.put(emId, new List<User>());
            for (String emailAddress : emailMessageIdToRecipients.get(emId)) {
                if (!usersByEmailAddress.containsKey(emailAddress)) {
                    continue;
                }
                emailMessageIdToRecipientUsers.get(emId).add(usersByEmailAddress.get(emailAddress));
            }
        }
        return emailMessageIdToRecipientUsers;
    }
    
    private static Map<Id, Account> fetchPartnerAccounts(Set<EmailMessage> emailMessages) {
        Map<Id, String> emailMessageIdToSenderDomain = new Map<Id, String>();
        for (EmailMessage em : emailMessages) {
            emailMessageIdToSenderDomain.put(em.Id, em.FromAddress.substringAfter('@'));
        }
        Map<String, Account> partnerByDomain = new Map<String, Account>();
        for (Account a : [
            SELECT Id, Partner_Email_URL__c, Account_Manager__c,
                Account_Manager__r.Id,
                Account_Manager__r.UserRoleId,
                Account_Manager__r.IsActive,
                Account_Manager__r.OutOfOfficeStartDateTime__c,
                Account_Manager__r.OutOfOfficeEndDateTime__c,
                Account_Manager__r.AM_Entitlement_Region__c,
                UseSecondAccountManager__c,
                X2nd_Account_Manager__r.Id,
                X2nd_Account_Manager__r.AM_Entitlement_Region__c,
                X2nd_Account_Manager__r.UserRoleId,
                X2nd_Account_Manager__r.IsActive,
                X2nd_Account_Manager__r.OutOfOfficeStartDateTime__c,
                X2nd_Account_Manager__r.OutOfOfficeEndDateTime__c,
                HolidayAccountManager__c,
                HolidayAccountManager__r.AM_Entitlement_Region__c,
                HolidayAccountManager__r.UserRoleId,
                HolidayAccountManager__r.IsActive,
                HolidayAccountManager__r.OutOfOfficeStartDateTime__c,
                HolidayAccountManager__r.OutOfOfficeEndDateTime__c,
                HolidayStartDateTime__c,
                HolidayEndDateTime__c
            FROM Account
            WHERE Partner__c = true
                AND Partner_Email_URL__c IN :emailMessageIdToSenderDomain.values()
        ]) {
            partnerByDomain.put(a.Partner_Email_URL__c, a);
        }
        Map<Id, Account> emailMessageIdToPartner = new Map<Id, Account>();
        for (Id emId : emailMessageIdToSenderDomain.keySet()) {
            emailMessageIdToPartner.put(
                emId,
                partnerByDomain.get(emailMessageIdToSenderDomain.get(emId))
            );
        }
        
        return emailMessageIdToPartner;
    }
    
    private static Map<Id, Contact> fetchContactsForIntegrations(Set<EmailMessage> emailMessages) {
        Set<String> accountIds = new Set<String>();
        Set<String> ccAddress = new Set<String>();
        for(EmailMessage email : emailMessages){
            if(
                email.Subject.startsWith(SUBJECT_OF_NEW_PARTNER_INTEGRATION) && 
                email.TextBody != null && 
                email.TextBody.contains(ACOUNT_LINE_FOR_NEW_PARTNER_INTEGRATION)
            ){
                String accId = getAccountIdFromEmailBody(email.TextBody);
                if(accId != null)
                    accountIds.add(accId);
            }
        }
        Map<Id, Contact> accountIdToContactForIntegration = new Map<Id, Contact>();
        for(Contact con : [
                SELECT Id, AccountId 
                FROM Contact 
                WHERE Technical_Contact__c = true AND AccountId IN: accountIds 
                ORDER BY CreatedDate ASC
            ]
        ){
            if(!accountIdToContactForIntegration.containsKey(con.AccountId)){
                accountIdToContactForIntegration.put(con.AccountId, con);
            }
        }
        return accountIdToContactForIntegration;
    }
    
    public static String getAccountIdFromEmailBody(String emailBody) {
        return emailBody.substring(
                emailBody.indexOf(ACOUNT_LINE_FOR_NEW_PARTNER_INTEGRATION)
            ).remove(ACOUNT_LINE_FOR_NEW_PARTNER_INTEGRATION).left(15);
    }

    public static List<String> getQueueEmailAddresses(String queueName) {
        if (queueNameToEmailAddresses == null) {
            initQueueMaps();
        }
        return queueNameToEmailAddresses.get(queueName);
    }

    public static Id getQueueId(String queueName) {
        if (queueIdByName == null) {
            initQueueMaps();
        }
        return queueIdByName.get(queueName);
    }

    public static String getSupportQueueName(String salesRegion) {
        if (queueNameBySalesRegion == null) {
            initQueueMaps();
        }
        return queueNameBySalesRegion.get(salesRegion);
    }

    private static void initQueueMaps() {
        queueIdByName = new Map<String, Id>();
        for (Group g : [SELECT Id, Name FROM Group WHERE Type = 'Queue']) {
            queueIdByName.put(g.Name, g.Id);
        }

        queueNameToEmailAddresses = new Map<String, List<String>>();
        for (QueueEmailAddress__mdt qea : [SELECT Id, Queue__c, EmailAddress__c FROM QueueEmailAddress__mdt WHERE IsTestRecord__c = :Test.isRunningTest()]) {
            if (!queueNameToEmailAddresses.containsKey(qea.Queue__c)) {
                queueNameToEmailAddresses.put(qea.Queue__c, new List<String>());
            }
            queueNameToEmailAddresses.get(qea.Queue__c).add(qea.EmailAddress__c);
        }

        queueNameBySalesRegion = new Map<String, String>();
        for (SupportSalesRegion__mdt ssr : [SELECT Id, MasterLabel, QueueName__c FROM SupportSalesRegion__mdt]) {
            queueNameBySalesRegion.put(ssr.MasterLabel, ssr.QueueName__c);
        }
    }

    public static void disableAssignmentForCases(Set<Id> ids) {
        List<Case> casesToUpdate = new List<Case>();
        for (Id caseId : ids) {
            casesToUpdate.add(new Case(
                Id = caseId,
                ManuallyAssigned__c = true
            ));
        }
        update casesToUpdate;
    }

     public static void assignWhenCaseReopen(List<Case> casesToAssign, Map<Id, User> casesIdToWners) {
        
        if (CASE_OWNERS_BY_TEAM == null) {
            initCaseOwnersByTeam();
        }
        for (Case c : casesToAssign) {
            if(NOT_APPLICABLE_CASE_RECORDTYPE_IDS.contains(c.RecordTypeId)){
                continue;
            }
            CaseAssignment ca = new CaseAssignment(
                c,
                casesIdToWners.get(c.Id)
            );
            ca.assign();
        }
        update casesToAssign;
    } 

    public static void initBusinessHours() {
        List<BusinessHours> hours = [SELECT Id, Name FROM BusinessHours WHERE IsActive = true];
        BUSINESS_HOURS_BY_NAME = new Map<String, BusinessHours>();
        for (BusinessHours h : hours) {
            BUSINESS_HOURS_BY_NAME.put(h.Name, h);
        }
    }

    public static void initRegionToBusinessHoursMap() {
        List<RegionToBusinessHours__mdt> mappings = [SELECT Id, MasterLabel, BusinessHoursName__c FROM RegionToBusinessHours__mdt];
        REGION_TO_BUSINESS_HOURS_MAP = new Map<String, String>();
        for(RegionToBusinessHours__mdt mapping : mappings){
            REGION_TO_BUSINESS_HOURS_MAP.put(mapping.MasterLabel, mapping.BusinessHoursName__c);
        }
    }

    @TestVisible
    private class CaseAssignment {
        @TestVisible private Case c;
        private EmailMessage em;
        private SocialPost sp;
        private List<User> recipientUsers;
        private Boolean isAssigned = false;
        private Account partner;
        private Account reassignAccount;
        private Boolean isAmAvailable = false;
        private Boolean hasActiveHolidayManager = false;
        private User newOwner;
        private User currentOwner;
        private Boolean isReassignment = false;
        private Map<Id, Contact> accountIdToContactForIntegration;
        private Boolean isFromOOOLogic = false;

        CaseAssignment(Case c, EmailMessage em, List<User> recipientUsers, Account partner) {
            this.c = c;
            this.em = em;
            this.recipientUsers = recipientUsers;
            this.partner = partner;
        }

        @TestVisible CaseAssignment(Case c, Account reassignAccount) {
            this.c = c;
            this.reassignAccount = reassignAccount;
        }

       	@TestVisible CaseAssignment(Case c) {
            this.c = c;
        }
        @TestVisible CaseAssignment(Case c, User currentOwner) {
            this.c = c;
            this.currentOwner = currentOwner;
        }


        @TestVisible
        private void assign() {
            assignToPreviousOwnerIfAvaliable();
            assignBasedOnPartnerDomain();
            assignToAccountManager();
            assignToFinance();
            assignToIntegrations();
            assignToProductSpecialists();
            assignToAcquiredSupport();
            assignToFraudSupport();
            assignToSupport(this.c.Account);
            c.SystemAssigned__c = isAssigned;
            c.IgnoreOoo__c = true;
        }

        private void assignBasedOnPartnerDomain() {
            if (isAssigned || this.partner == null) {
                return;
            }
            this.hasActiveHolidayManager = isHolidayManagerActive(this.partner);
            recipientUsersAssignmentIgnoringBusinessHours();
            assignToAccountManager();
            if (!this.isAssigned) {
                this.c.OwnerId = CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_INTEGRATIONS);
                this.c.AccountId = this.partner.Id;
                this.isAssigned = true;
            }
        }
        private void assignToPreviousOwnerIfAvaliable() {
            if (isAssigned || currentOwner == null) {
                return;
            }
            if(isUserAvailable(currentOwner)){
                this.newOwner = currentOwner;
                this.c.OwnerId = this.newOwner.Id;
                this.isAssigned = true;
            }
        }
        

        private Boolean isHolidayManagerActive(Account acc) {
            return  acc != null
                    && acc.HolidayAccountManager__c != null
                    && System.now() >= acc.HolidayStartDateTime__c
                    && System.now() <= acc.HolidayEndDateTime__c
                    && this.isUserAvailable(acc.HolidayAccountManager__r);
        }

        private void recipientUsersAssignment(Account acc) {            
            if(acc == null || acc.Account_Manager__c == null){
                recipientUsersAssignmentIgnoringBusinessHours();
            }
        }

        private void recipientUsersAssignmentWithinBusinessHours() {            
            if (!this.isAssigned && recipientUsers != null && !recipientUsers.isEmpty() && isUserAvailable(recipientUsers.get(0))) {
                Datetime createdTimeGmt = this.c.CreatedDate;
                String recipientUserRegion = recipientUsers.get(0)?.AM_Entitlement_Region__c;
                
                if( recipientUserRegion == null || 
                    !BUSINESS_HOURS_BY_NAME.containsKey(recipientUserRegion) ||
                    !BusinessHours.isWithin(BUSINESS_HOURS_BY_NAME.get(recipientUserRegion).Id, createdTimeGmt)){
                        return;
                }

                this.newOwner = recipientUsers.get(0);
                this.isAmAvailable = this.isUserAvailable(this.newOwner);
                this.c.OwnerId = this.newOwner.Id;
                this.isAssigned = true;
            }
        }

        private void recipientUsersAssignmentIgnoringBusinessHours() {
            if (!this.isAssigned && recipientUsers != null && !recipientUsers.isEmpty()) {
                if(isUserAvailable(recipientUsers.get(0))){
                    this.newOwner = recipientUsers.get(0);
                    this.isAmAvailable = this.isUserAvailable(this.newOwner);
                    this.c.OwnerId = this.newOwner.Id;
                    this.isAssigned = true;
                } else {
                    assignToTeamMembers(recipientUsers.get(0));
                }
            }
        }

        private Boolean isUserAvailable(User user) {
            return user.IsActive
                    && (user.OutOfOfficeStartDateTime__c == null
                    || System.now() < user.OutOfOfficeStartDateTime__c
                    || user.OutOfOfficeEndDateTime__c == null
                    || System.now() > user.OutOfOfficeEndDateTime__c);
        }

        private void managerAssignment(Account acc) {
            if (this.isAssigned) {
                return;
            }
            if (this.hasActiveHolidayManager) {
                assignToHolidayManager(acc);
            } else {
                assignToOneOfManagers(acc);
            }
        }

        private void assignToHolidayManager(Account acc) {
            this.newOwner = acc.HolidayAccountManager__r;
            this.isAssigned = true;
            this.c.OwnerId = this.newOwner.Id;
            this.isAmAvailable = this.isUserAvailable(this.newOwner);
        }

        private void assignToOneOfManagers(Account acc) {
            if(acc == null || acc.Account_Manager__c == null){
                return;
            }
            User manager  = pickAccountManager(acc);
            if (!isUserAvailable(manager)){
                return;
            }
            this.c.OwnerId = manager.Id;
            this.isAssigned = true;
            this.newOwner = manager;
            this.isAmAvailable = this.isUserAvailable(manager);
        }

        @TestVisible
        private User pickAccountManager(Account acc) {
            if (REGION_TO_BUSINESS_HOURS_MAP == null) {
                initRegionToBusinessHoursMap();
            }

            String regionAm = acc?.Account_Manager__r?.AM_Entitlement_Region__c;
            String region2ndAm = acc?.X2nd_Account_Manager__r?.AM_Entitlement_Region__c;

            String businessHoursNameForAm = REGION_TO_BUSINESS_HOURS_MAP.get(regionAm) == null ? 
                regionAm : 
                REGION_TO_BUSINESS_HOURS_MAP.get(regionAm);
            String businessHoursNameFor2ndAm = REGION_TO_BUSINESS_HOURS_MAP.get(region2ndAm) == null ?
                region2ndAm : 
                REGION_TO_BUSINESS_HOURS_MAP.get(region2ndAm);

            if(acc.X2nd_Account_Manager__c == null || 
                !acc.UseSecondAccountManager__c || 
                BUSINESS_HOURS_BY_NAME.get(businessHoursNameForAm) == null ||
                BUSINESS_HOURS_BY_NAME.get(businessHoursNameFor2ndAm) == null){
                    return acc.Account_Manager__r;
            }
            Datetime createdTimeGmt = this.c.CreatedDate;
            if(BusinessHours.isWithin(BUSINESS_HOURS_BY_NAME.get(businessHoursNameForAm).Id, createdTimeGmt) && 
                isUserAvailable(acc.Account_Manager__r)) {
                    return acc.Account_Manager__r;
            }
            else if(BusinessHours.isWithin(BUSINESS_HOURS_BY_NAME.get(businessHoursNameFor2ndAm).Id, createdTimeGmt) && 
                isUserAvailable(acc.X2nd_Account_Manager__r)){
                    return acc.X2nd_Account_Manager__r;
            }
            return acc.Account_Manager__r;
        }

        private void assignToAccountManager() {
            recipientUsersAssignment(this.c.Account);
            if (isAssigned || isAccountWithoutManager()) {
                return;
            }
            this.hasActiveHolidayManager = isHolidayManagerActive(this.c.Account);
            managerAssignment(this.c.Account);
            holidayOrTeamAssignment();
        }

        private Boolean isAccountWithoutManager() {
            If(this.c.Account != Null){                
                return c.AccountId != null && c.Account.Account_Manager__c == null && !c.Account.IgnoreBlankAccountManager__c;
            }
            return false;
        }

        private void holidayOrTeamAssignment() {
            if (this.isAssigned && !this.isAmAvailable) {
                if (this.hasActiveHolidayManager && this.newOwner.Id != c.Account.HolidayAccountManager__c) {
                    this.newOwner = c.Account.HolidayAccountManager__r;
                    this.c.OwnerId = this.newOwner.Id;
                    this.isAssigned = true;
                    return;        
                }
                if (!this.newOwner.isActive) {
                    this.isAssigned = false;
                }
                
            } 
            if(this.c.Account.Account_Manager__r != null){
                assignToTeamMembers(this.c.Account.Account_Manager__r);
            }

        }

        private void assignToTeamMembers(User user) {
            if (this.isAssigned) {
                return;
            }
            if(user != null){
            user usr=[select id,UserRoleId,UserRole.Name,AM_Region__c,Sub_AM_Regions__c from user where id =: user.id limit 1];

            // isFromOOOLo
            Id userRoleId = usr?.UserRoleId;
            string userRole=usr?.UserRole.Name;
            if(userRole.contains('Team Lead') && isOOOLogic==true ){
                list<string> roleName= userRole.split(' Team');
                List<UserRole> userRoleList= new List<UserRole>();
                UserRoleList=[select name,id from userrole where name =:roleName];
                if(UserRoleList != null && UserRoleList.isEmpty() == false){
                userRoleId=UserRoleList[0].Id;}
                isOOOLogic=false;
                
              //  userRoleId='00Eb0000000en4P';

            }
            if(userRoleId == INTEGRATIONS_USER_ROLE_ID){
                assignToIntegrationsTeam();
            }
           else if (CASE_OWNERS_BY_TEAM.containsKey(userRoleId)) {
                List<CaseTeamMember> teamMembers = CASE_OWNERS_BY_TEAM.get(userRoleId).values();
                teamMembers.sort();
                CaseTeamMember ctm = getTeamMemberWithLeastCases(teamMembers);
                this.c.OwnerId = ctm.userId;
              //  ctm.nCases++;
                this.isAssigned = true;

                if (!Test.isRunningTest()) {
                    postOooReassignmentMessageOnCaseFeed(this.c.OwnerId, user.Id);
                }
            }
        }
    }

        private void assignToIntegrationsTeam(){
            this.c.OwnerId = CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_INTEGRATIONS);
            isAssigned = true;
        }

      private CaseTeamMember getTeamMemberWithLeastCases(List<CaseTeamMember> teamMembers) {
    List<CaseTeamMember> teamMembersWithLeastScore = collectTeamMembersWithLeastScore(teamMembers);
    Boolean isTieBetweenTeamMembers = teamMembersWithLeastScore.size() > 1;
    Integer index = isTieBetweenTeamMembers ? getRandomNumber(teamMembersWithLeastScore.size()) : 0;

    return teamMembersWithLeastScore.get(index);
}

private List<CaseTeamMember> collectTeamMembersWithLeastScore(List<CaseTeamMember> teamMembers) {
    Decimal smallestTotalScore = teamMembers.get(0).totalScore;
    List<CaseTeamMember> teamMembersWithLeastScore = new List<CaseTeamMember>{};

    for (CaseTeamMember ctm : teamMembers) {
        if (ctm.totalScore != smallestTotalScore) {
            continue;
        }
        teamMembersWithLeastScore.add(ctm);
    }

    return teamMembersWithLeastScore;
}


        private Integer getRandomNumber(Integer upperLimit) {
            return Test.isRunningTest() ? 1 : (Math.random() * upperlimit).intValue();
        }

        private void postOooReassignmentMessageOnCaseFeed(Id oldOwnerId, Id newOwnerId) {
            String reassignMessage = String.format(Label.CaseReassignMessage, new String[]{'{', oldOwnerId, '}','{', newOwnerId, '}'});
            ConnectApiHelper.postFeedItemWithMentions(null, this.c.Id, reassignMessage);
        }

        private void assignToFinance() {
            if (isAssigned) {
                return;
            }
            assignBasedOnAddress(CaseAssignmentService.QUEUE_NAME_FINANCE);
            return;
        }

        private void assignToIntegrations() {
            if (isAssigned) {
                return;
            }
            assignBasedOnAddress(CaseAssignmentService.QUEUE_NAME_INTEGRATIONS);
            return;
        }

        private void assignBasedOnAddress(String queueName) {
            if (this.em == null) {
                return;
            }
            for (String emailAddress : CaseAssignmentService.getQueueEmailAddresses(queueName)) {
                if ((String.isBlank(this.em.ToAddress)
                        || !this.em.ToAddress.containsIgnoreCase(emailAddress))
                    && (String.isBlank(this.em.CcAddress)
                        || !this.em.CcAddress.containsIgnoreCase(emailAddress))
                ) {
                    continue;
                }

                assignAccountAndTechContactForIntegrationIfNeeded(queueName);

                this.c.OwnerId = CaseAssignmentService.getQueueId(queueName);
                isAssigned = true;
                break;
            }
        }

        private void assignToProductSpecialists() {
            if (isAssigned) {
                return;
            }
            assignBasedOnAddress(CaseAssignmentService.QUEUE_NAME_PRODUCT_SPECIALISTS);
            return;
        }

        private void assignToAcquiredSupport() {
            if (isAssigned) {
                return;
            }
            assignBasedOnAddress(CaseAssignmentService.QUEUE_NAME_ACQUIRED_SUPPORT);
        }

        private void assignToFraudSupport() {
            if (isAssigned) {
                return;
            }
            assignBasedOnAddress(CaseAssignmentService.QUEUE_NAME_FRAUD_SUPPORT);
        }

        private void assignToSupport(Account specifiedAcc) {
            if (isAssigned) {
                return;
            }

            String supportRegionName;
            if(specifiedAcc != null){
                if(specifiedAcc.SupportRegionPicklist__c != null){
                    supportRegionName = specifiedAcc.SupportRegionPicklist__c;
                } else if(specifiedAcc.Case_Assignment_Region__c != null){
                    supportRegionName = specifiedAcc.Case_Assignment_Region__c;
                }
            }

            String queueName = specifiedAcc != null && !specifiedAcc.IgnoreSalesRegionInCaseAssignment__c
                ? CaseAssignmentService.getSupportQueueName(supportRegionName)
                : null;

            if (queueName == null) {
                Time createdTimeGmt = this.c.CreatedDate.timeGmt();
                if (createdTimeGmt >= GMT_START_TIME_EMEA && createdTimeGmt < GMT_START_TIME_US) {
                    queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_EMEA;
                } else if (createdTimeGmt >= GMT_START_TIME_US && createdTimeGmt < GMT_START_TIME_APAC) {
                    queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_US;
                } else {
                    queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_JAPAN;
                }
            }
            this.c.OwnerId = CaseAssignmentService.getQueueId(queueName);
            this.isAssigned = true;
        }
        
        @TestVisible
        private void reassign(User user) {
            this.isReassignment = true;
            reassignToManager(this.reassignAccount);
            assignToTeamMembers(user);
            assignToSupport(this.reassignAccount);
            c.SystemAssigned__c = isAssigned;
            c.IsReassignedAutomatically__c = true;
        }

        private void reassignToManager(Account acc) {
            if (acc == null || (acc.HolidayAccountManager__c == null && acc.Account_Manager__c == null)) {
                return;
            }
            if (acc.HolidayAccountManager__c == null && !isUserAvailable(acc.Account_Manager__r)){
                return;
            }
            Id currentOwnerId = this.c.OwnerId;
            this.c.OwnerId = isHolidayManagerActive(acc) ? acc.HolidayAccountManager__c : acc.Account_Manager__c;
            this.isAssigned = currentOwnerId != this.c.OwnerId;
        }

        private void setTechContactMap(Map<Id, Contact> accountIdToContactForIntegration) {
            this.accountIdToContactForIntegration = accountIdToContactForIntegration;
        }

        private void assignAccountAndTechContactForIntegrationIfNeeded(String queueName) {
            if(queueName == CaseAssignmentService.QUEUE_NAME_INTEGRATIONS && 
                this.em.TextBody.contains(CaseAssignmentService.ACOUNT_LINE_FOR_NEW_PARTNER_INTEGRATION) &&
                this.em.FromAddress.contains(CaseAssignmentService.FROM_ADRESS_DOMAIN_FOR_NEW_PARTNER_INTEGRATION)
            ){
                assignAccountAndTechContactForIntegration(
                    CaseAssignmentService.getAccountIdFromEmailBody(this.em.TextBody)
                );
            }
        }

        private void assignAccountAndTechContactForIntegration(String accId) {
            try { 
                this.c.AccountId = Id.valueOf(accId);
                this.c.ContactId = accountIdToContactForIntegration.containsKey(this.c.AccountId) ? 
                    accountIdToContactForIntegration.get(this.c.AccountId).Id: 
                    null;
            } catch (StringException e) { 
                this.c.AccountId = null;
                this.c.ContactId = null;
            }
        }
        
        public Boolean isNeedToReassign(User owner) {
            return !this.isUserAvailable(owner);
        }
    }

   private class CaseTeamMember implements Comparable {
    private Id userId;
    private Decimal totalScore;

    CaseTeamMember(Id userId, Decimal totalScore) {
        this.userId = userId;
        this.totalScore = totalScore;
    }

       public Integer compareTo(Object obj) {
           CaseTeamMember compareMember = (CaseTeamMember)obj;
           
           // Compare based on totalScore
           if (this.totalScore > compareMember.totalScore) {
               return 1;
           } else if (this.totalScore < compareMember.totalScore) {
               return -1;
           } else {
               return 0;
           }
       }
}

}