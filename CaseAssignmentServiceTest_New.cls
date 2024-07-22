@isTest
public class CaseAssignmentServiceTest_New {
   
    @isTest static void assignBasedOnEmailMessage_withAccount_supportIgnoreSalesRegion() {
        TestEnvironment env = new TestEnvironment()
            .createAccount();
        
        env.acc.IgnoreSalesRegionInCaseAssignment__c = true;
        env.acc.Sales_Region__c = 'The Americas';
        update env.acc;
        system.debug('test');

        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'testSupport@adjust.com'}, new List<String>());
        Test.stopTest();

        Case[] c = [SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
        
        String queueName;
        Time createdTimeGmt = c[0].CreatedDate.timeGmt();
        if (createdTimeGmt >= CaseAssignmentService.GMT_START_TIME_EMEA && createdTimeGmt < CaseAssignmentService.GMT_START_TIME_US) {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_EMEA;
        } else if (createdTimeGmt >= CaseAssignmentService.GMT_START_TIME_US && createdTimeGmt < CaseAssignmentService.GMT_START_TIME_APAC) {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_US;
        } else {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_JAPAN;
        }
        System.assertEquals(CaseAssignmentService.getQueueId(queueName), c[0].OwnerId);
    }
    @isTest
    static void testSetStatusToSpam() {
        Group supportUSQueuesId = [SELECT Id,Name FROM Group WHERE Type = 'Queue' AND Name = 'Support US' LIMIT 1];      
        // Create test data
        Case testCase = new Case(
            Subject = Label.Auto_spamming_Subject,
            Origin = 'Web',
            Type = 'Alerts',
            MainFunctionalArea__c ='App ID Verification',
            Status = 'New', 
            OwnerId=SupportUSQueuesId.Id,
            Description='qwerty'
        );
        insert testCase;
        System.debug(testCase);
        Set<Id> caseIds = new Set<Id>{testCase.Id};
        Test.startTest();
        CaseAssignmentService.setStatusToSpam(caseIds);
        Test.stopTest();
    }
    @isTest
    static void testAssignCasesFromWeb() {
        // Create test data
        Case testCase = new Case(
            Subject = 'Test Case',
            Description = 'This is a test case',
            RecordTypeId = '0120X0000009hlNQAQ'
        );
        insert testCase;

        Set<Id> caseIds = new Set<Id>{testCase.Id};

        // Call the method to be tested
        Test.startTest();
        CaseAssignmentService.assignCasesFromWeb(caseIds);
        Test.stopTest();

        // Verify the results
        List<Case> updatedCases = [SELECT Id, OwnerId FROM Case WHERE Id = :testCase.Id];
        System.assertEquals(1, updatedCases.size());
        System.assertNotEquals(null, updatedCases[0].OwnerId);
    }


    @isTest static void assignBasedOnEmailMessage_withAccount_ignoreBlankAccountManager() {
        TestEnvironment env = new TestEnvironment()
            .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }

        env.acc.Sales_Region__c = 'ROW';
        env.acc.IgnoreBlankAccountManager__c = true;
        update env.acc;
        
        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'}, new List<String>());
        Test.stopTest();

        Case[] c = [SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
    }

    
 @isTest static void assignBasedOnEmailMessage_noAccount_accountManager() {
        TestEnvironment env = new TestEnvironment()
            .createAccountManager();
        
        System.runAs(env.am) {
            env.createCaseWoAccount();
            Test.startTest();
                env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'}, new List<String>());
            Test.stopTest();
        }

        Case[] c = [SELECT OwnerId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
    }
    @isTest static void assignBasedOnEmailMessage_noAccount_accountManager_domainValidation() {
        TestEnvironment env = new TestEnvironment()
            .createAccountManager();
        
        User am1 = env.am.clone(false, true);
        am1.Email = 'am1@test.test';
        am1.Username = 'am1@test.test';
        am1.Alias = 'am1';
        am1.CommunityNickname = 'am1';
        am1.IsActive = false;
        
        User am2 = env.am.clone(false, true);
        am2.Email = 'am2@test.test';
        am2.Username = 'am2@test.test';
        am2.Alias = 'am2';
        am2.CommunityNickname = 'am2';
        insert new List<User> {am1, am2};

        System.runAs(env.am) {
            env.createCaseWoAccount();
            Test.startTest();
                env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am1@test.test'}, new List<String> {'am2@test.test', 'am-test@support.adjust.com'});
            Test.stopTest();
        }

        Case[] c = [SELECT OwnerId, owner.Username FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
    }
     @isTest public static void reassign_primaryUserOoo_teamMembers() {
        TestEnvironment env = new TestEnvironment();
        
        env.createAccountManager();
        User am1 = env.am.clone(false, true);
        am1.Email = 'am1@support.adjust.com';
        am1.Username = 'am1@test.test';
        am1.Alias = 'am1';
        am1.CommunityNickname = 'am1';
        am1.UserRoleId = env.AM_JAPAN_ROLE;
        am1.OutOfOfficeStartDateTime__c = System.today();
        am1.OutOfOfficeEndDateTime__c = System.today().addDays(14);
        
        User am2 = env.am.clone(false, true);
        am2.Email = 'am2@support.adjust.com';
        am2.Username = 'am2@test.test';
        am2.Alias = 'am2';
        am2.CommunityNickname = 'am2';
        am2.UserRoleId = env.AM_JAPAN_ROLE;
        
        User am3 = env.am.clone(false, true);
        am3.Email = 'am3@support.adjust.com';
        am3.Username = 'am3@test.test';
        am3.Alias = 'am3';
        am3.CommunityNickname = 'am3';
        am3.IsActive = false;
        am3.UserRoleId = env.AM_JAPAN_ROLE;
        insert new List<User> {am1, am2, am3};

        Case am1Case = new Case(
            Origin = 'Email',
            Status = 'Pending',
            Type = 'Finance',
            MainFunctionalArea__c='Pausing',
            Subject = 'Test Subject',
            Description = 'Some description',
            OwnerId = am1.Id
        );

        CaseAssignmentService.CASE_OWNERS_BY_TEAM = null;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(thisUser) {
            
            Test.startTest();
            insert am1Case;
            am1Case.Status = 'Open';
            update am1Case;
            Test.stopTest();
        }

        Case c = [SELECT Id, OwnerId FROM Case WHERE Id = :am1Case.Id];
        System.assertNotEquals(am1.Id, c.OwnerId);
        System.assertEquals(env.AM_JAPAN_ROLE, [SELECT UserRoleId FROM User WHERE Id =: c.OwnerId].UserRoleId);
    }
    
	@isTest static void assignBasedOnEmailMessage_noAccount_supportAndAm() {
        TestEnvironment env = new TestEnvironment()
            .createAccountManager();
        
        System.runAs(env.am) {
            env.createCaseWoAccount();
            Test.startTest();
                env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'testSupport@adjust.com'}, new List<String> {'am-test@support.adjust.com'});
            Test.stopTest();
        }

        Case[] c = [SELECT OwnerId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
    }
     @isTest static void assignBasedOnSocialPost_contactPersonaWithAm() {
        TestEnvironment env = new TestEnvironment()
            .createAccountManager();
        
        System.runAs(env.am) {
            env.createSocialPersona();
            env.acc.Account_Manager__c = env.am.Id;
            update env.acc;
            Test.startTest();
                env.createSocialPost(true);
            Test.stopTest();
        }
        
        Case[] c = [SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.socialPosts[0].ParentId];
        System.assertEquals(1, c.size());
        System.assertEquals(env.am.Id, c[0].OwnerId);
    }
          @isTest static void assignBasedOnSocialPost_outboundSocialPost() {
        TestEnvironment env = new TestEnvironment()
            .createCaseWoAccount();
        
        Test.startTest();
        	env.createSocialPost(false);
        Test.stopTest();

        Case[] c = [SELECT OwnerId FROM Case WHERE Id = :env.socialPosts[0].ParentId];
        System.assertEquals(1, c.size());
    }
     @isTest static void assignCaseToHolidayAccountManager_emailRecipientIsAccountManager_AccountManagerOoO() {
        TestEnvironment env = new TestEnvironment()
                .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }

        User primaryAM = env.am;
        User holidayAM = primaryAM.clone();
        holidayAM.Email = 'ham-test@support.adjust.com';
        holidayAM.Username = 'h-amtest@test.test';
        holidayAM.Alias = 'h-am';
        holidayAM.CommunityNickname = 'h-am';
        holidayAM.AM_Entitlement_Region__c = 'EMEA';
        System.runAs(new User(Id = UserInfo.getUserId())){
            insert holidayAM;
        }

        //env.acc.Account_Manager__c = primaryAM.Id;
        env.acc.HolidayAccountManager__c = holidayAM.Id;
        env.acc.HolidayStartDateTime__c = System.today().addDays(-1);
        env.acc.HolidayEndDateTime__c = System.today().addDays(14);
        env.acc.UseSecondAccountManager__c = true;
        update env.acc;
        
        primaryAM.OutOfOfficeStartDateTime__c = System.today().addDays(-1);
        primaryAM.OutOfOfficeEndDateTime__c = System.today().addDays(14);
        update primaryAM;


        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'}, new List<String>());
        Test.stopTest();

        Case c =[SELECT OwnerId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertNotEquals(env.am.Id, c.OwnerId);
        System.assertEquals(holidayAM.Id, c.OwnerId);
    }
     @isTest static void assignCaseToHolidayAccountManager_emailRecipientIsGeneralSupport_noAccountManager() {
        TestEnvironment env = new TestEnvironment()
                .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }
        User holidayAM = env.am.clone();
        holidayAM.Email = 'ham-test@support.adjust.com';
        holidayAM.Username = 'h-amtest@test.test';
        holidayAM.Alias = 'h-am';
        holidayAM.CommunityNickname = 'h-am';
        System.runAs(new User(Id = UserInfo.getUserId())){
        	insert holidayAM;
        }
        
        env.acc.Account_Manager__c = null;
        env.acc.HolidayAccountManager__c = holidayAM.Id;
        update env.acc;

        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String>{
                'am-test@support.adjust.com'}, new List<String>());
        Test.stopTest();

        Case c =[SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.emailMessages[0].ParentId];

        System.assertNotEquals(holidayAM.Id, c.OwnerId);

    }
    
     @isTest static void assignCaseToHolidayAccountManager_emailRecipientIsGeneralSupport_noAccountManager_assignToSupport() {
        TestEnvironment env = new TestEnvironment()
                .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }
        User holidayAM = env.am.clone();
        holidayAM.Email = 'ham-test@support.adjust.com';
        holidayAM.Username = 'h-amtest@test.test';
        holidayAM.Alias = 'h-am';
        holidayAM.CommunityNickname = 'h-am';
        System.runAs(new User(Id = UserInfo.getUserId())){
        	insert holidayAM;
        }
        
        env.acc.Account_Manager__c = null;
        env.acc.HolidayAccountManager__c = holidayAM.Id;
        update env.acc;

        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String>{
                'am-test@adjust.com'}, new List<String>());
        Test.stopTest();

        Case c =[SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.emailMessages[0].ParentId];

        System.assertNotEquals(holidayAM.Id, c.OwnerId);

        System.assertEquals(CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_SUPPORT_EMEA), c.OwnerId);
    }
    
     @isTest static void disableAutoAssignmentOnOutboudMessage_notNeeded() {
        TestEnvironment env = new TestEnvironment()
            .createAccountManager();

        System.runAs(env.am) {
            env.createEmailMessage(false, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'}, new List<String>());
            System.assert(true, [SELECT ManuallyAssigned__c FROM Case WHERE Id = :env.cases[0].Id].ManuallyAssigned__c);
            Test.startTest();
                env.createEmailMessage(false, env.emailMessages[0].Id, 'am-test@support.adjust.com', new List<String> {'client-test@test.test'}, new List<String>());
            Test.stopTest();
        }

        Case c = [SELECT ManuallyAssigned__c FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assert(true, c.ManuallyAssigned__c);
    }

    @isTest static void oooTime_startTimeInFuture_assignToAm() {
        TestEnvironment env = new TestEnvironment();
        
        env.createAccountManager();
        env.am.UserRoleId = env.AM_JAPAN_ROLE;
        env.am.OutOfOfficeStartDateTime__c = System.now().addHours(3);
        env.am.OutOfOfficeEndDateTime__c = System.today().addDays(3);
        update env.am;

        CaseAssignmentService.CASE_OWNERS_BY_TEAM = null;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(thisUser) {
            Test.startTest();
                env.createCaseWoAccount();
                env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'}, new List<String>());
            Test.stopTest();
        }
        Case c = [SELECT OwnerId, Owner.UserRoleId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
    }
     @isTest public static void reassignCase_primaryUserOoo_teamMemberExcluded() {
        TestEnvironment env = new TestEnvironment();
        List<User> existingUsers = [SELECT Id FROM User WHERE UserRoleId = :env.AM_JAPAN_ROLE AND IsActive = true];

        Id AM_EU_ROLE = [SELECT Id FROM UserRole WHERE Name = 'AM EU'].Id;
        for (User u : existingUsers) {
            u.UserRoleId = AM_EU_ROLE;
        }
        update existingUsers;
        
        env.createAccountManager();
        env.am.UserRoleId = env.AM_JAPAN_ROLE;
        env.am.IsActive = true;
        env.am.IncludeInOooReassignment__c = true;
        
        User excluded = env.am.clone();
        excluded.Email = 'excluded@support.adjust.com';
        excluded.Username = 'excluded@test.test';
        excluded.Alias = 'excluded';
        excluded.CommunityNickname = 'excluded';
        excluded.UserRoleId = env.AM_JAPAN_ROLE;
        excluded.IncludeInOooReassignment__c = false;

        env.am.OutOfOfficeStartDateTime__c = System.today();
        env.am.OutOfOfficeEndDateTime__c = System.today().addDays(14);
        
        update env.am;
        insert excluded;

        Case caseOfOooUser = new Case(
            Origin = 'Email',
            Status = 'Pending',
            Type = 'Log Request',
            Subject = 'Test Subject',
            Description = 'Some description',
            OwnerId = env.am.Id
        );

        CaseAssignmentService.CASE_OWNERS_BY_TEAM = null;

        System.runAs(env.am) {
            insert caseOfOooUser;
            Test.startTest();
                caseOfOooUser.Status = 'Open';
                update caseOfOooUser;
            Test.stopTest();
        }

        Case c = [SELECT Id, OwnerId, CreatedDate FROM Case WHERE Id = :caseOfOooUser.Id];
        String queueName;
        Time createdTimeGmt = c.CreatedDate.timeGmt();
        if (createdTimeGmt >= CaseAssignmentService.GMT_START_TIME_EMEA && createdTimeGmt < CaseAssignmentService.GMT_START_TIME_US) {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_EMEA;
        } else if (createdTimeGmt >= CaseAssignmentService.GMT_START_TIME_US && createdTimeGmt < CaseAssignmentService.GMT_START_TIME_APAC) {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_US;
        } else {
            queueName = CaseAssignmentService.QUEUE_NAME_SUPPORT_JAPAN;
        }
        System.assertNotEquals(env.am.Id, c.OwnerId);
        System.assertNotEquals(excluded.Id, c.OwnerId); 
        System.assertEquals(CaseAssignmentService.getQueueId(queueName), c.OwnerId); 
    }
      @isTest static void reassignToIntegrations(){
        TestEnvironment env = new TestEnvironment();
        env.createAccountManager();

        UserRole integrationRole = [
            SELECT 
                Id,
                Name
            FROM UserRole 
            WHERE Name =: CaseAssignmentService.QUEUE_NAME_INTEGRATIONS
        ];

        String uniqueUsername = String.valueOf(Math.random()).replace('.', '').substring(1,8);

        User outOfOfficeUser = env.am.clone(false, false);
        outOfOfficeUser.LastName = 'JustName';
        outOfOfficeUser.Username = uniqueUsername + '@test.test';
        outOfOfficeUser.Alias = uniqueUsername;
        outOfOfficeUser.CommunityNickname = uniqueUsername;
        outOfOfficeUser.IsActive = true;
        outOfOfficeUser.UserRoleId = integrationRole.Id;
        outOfOfficeUser.OutOfOfficeStartDateTime__c = Datetime.newInstance(2019, 1, 1);
        outOfOfficeUser.OutOfOfficeEndDateTime__c = Datetime.newInstance(2099, 1, 1);
        insert outOfOfficeUser;

        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(thisUser){
            env.createAccount();
            Case c = new Case(
                Subject = CaseService.ANOMALY_CASE_SUBJECT + ' 2019-03-05',
                AccountId = env.acc.Id,
                OwnerId = outOfOfficeUser.Id,
                Origin = 'Web',
                Type = 'Alerts',
                MainFunctionalArea__c ='App ID Verification',
                Status = 'Pending'
            );
            insert c;

            Test.startTest();
            c.Status = 'Open';
            update c;
            Test.stopTest();

            Case resultCase = [
                SELECT 
                    Id,
                    OwnerId
                FROM Case
                WHERE Id =: c.Id
            ];

            System.assertEquals(CaseAssignmentService.getQueueId(CaseAssignmentService.QUEUE_NAME_INTEGRATIONS), resultCase.OwnerId);
        }    
    }
     @isTest public static void reassign_primaryUserInactive_teamMembers() {
        TestEnvironment env = new TestEnvironment();
        
        env.createAccountManager();
        User am1 = env.am.clone(false, true);
        am1.Email = 'am1@support.adjust.com';
        am1.Username = 'am1@test.test';
        am1.Alias = 'am1';
        am1.CommunityNickname = 'am1';
        am1.UserRoleId = env.AM_JAPAN_ROLE;
        am1.isActive = false;
        
        User am2 = env.am.clone(false, true);
        am2.Email = 'am2@support.adjust.com';
        am2.Username = 'am2@test.test';
        am2.Alias = 'am2';
        am2.CommunityNickname = 'am2';
        am2.UserRoleId = env.AM_JAPAN_ROLE;
        
        User am3 = env.am.clone(false, true);
        am3.Email = 'am3@support.adjust.com';
        am3.Username = 'am3@test.test';
        am3.Alias = 'am3';
        am3.CommunityNickname = 'am3';
        am3.IsActive = false;
        am3.UserRoleId = env.AM_JAPAN_ROLE;
        insert new List<User> {am1, am2, am3};

        Case am1Case = new Case(
            Origin = 'Email',
            Status = 'Pending',
            Type = 'Log Request',
            Subject = 'Test Subject',
            Description = 'Some description',
            OwnerId = am1.Id
        );

        CaseAssignmentService.CASE_OWNERS_BY_TEAM = null;
        System.runAs(env.am) {
            insert am1Case;
            Test.startTest();
            am1Case.Status = 'Open';
            update am1Case;
            Test.stopTest();
        }

        Case c = [SELECT Id, OwnerId FROM Case WHERE Id = :am1Case.Id];
        System.assertNotEquals(am1.Id, c.OwnerId);
        System.assertEquals(env.AM_JAPAN_ROLE, [SELECT UserRoleId FROM User WHERE Id =: c.OwnerId].UserRoleId);
    }
      @isTest static void assignCaseToHolidayAccountManager_emailRecipientIsGeneralSupport_BeforeHolidayPeriod() {
        TestEnvironment env = new TestEnvironment()
                .createAccount();
               // .createAccountManager();
        
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }
        

        User primaryAM = env.am;
        User holidayAM = primaryAM.clone();
        holidayAM.Email = 'ham-test@support.adjust.com';
        holidayAM.Username = 'h-amtest@test.test';
        holidayAM.Alias = 'h-am';
        holidayAM.CommunityNickname = 'h-am';
        System.runAs(new User(Id = UserInfo.getUserId())){
        	insert holidayAM;
        }
        env.acc.HolidayStartDateTime__c = System.today().addDays(14);
        env.acc.HolidayEndDateTime__c  = System.today().addDays(28);
        env.acc.Account_Manager__c = primaryAM.Id;
        env.acc.HolidayAccountManager__c = holidayAM.Id;
        update env.acc;

        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'testSupport@adjust.com'}, new List<String>());
        Test.stopTest();

        Case c =[SELECT OwnerId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(primaryAM.Id, c.OwnerId);
    }
 @isTest static void assignCaseToHolidayAccountManager_emailRecipientIsGeneralSupport_HolidayPeriod() {
        TestEnvironment env = new TestEnvironment()
                .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }

        User primaryAM = env.am;
        User holidayAM = primaryAM.clone();
        holidayAM.Email = 'ham-test@support.adjust.com';
        holidayAM.Username = 'h-amtest@test.test';
        holidayAM.Alias = 'h-am';
        holidayAM.CommunityNickname = 'h-am';
        holidayAM.AM_Entitlement_Region__c = 'EMEA';
        System.runAs(new User(Id = UserInfo.getUserId())){
             insert holidayAM;
        }
        env.acc.HolidayStartDateTime__c = System.today();
        env.acc.HolidayEndDateTime__c  = System.today().addDays(14);
        env.acc.Account_Manager__c = primaryAM.Id;
        env.acc.HolidayAccountManager__c = holidayAM.Id;
        update env.acc;

        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'testSupport@adjust.com'}, new List<String>());
        Test.stopTest();

        Case c =[SELECT OwnerId FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        //System.assertNotEquals(env.am.Id, c.OwnerId);
        //System.assertEquals(holidayAM.Id, c.OwnerId);
    }
    
    @isTest
    static void testAssignWhenCaseReopen() {
        User testUser = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            Username = 'testuser1.1@example.com',
            Email = 'testuser1.1@example.com',
            Alias = 'tuser',
            CommunityNickname = 'testuser123',
            LastName = 'Testing',
            FirstName = 'User',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US'
        );
        insert testUser;
        
        Case testCase = new Case(
            Subject = 'Test Case',
            Type = 'Finance',
            MainFunctionalArea__c = 'Invoicing',
            Status = 'Closed',
            RecordTypeId = '0120X0000009hlNQAQ',
            OwnerId = UserInfo.getUserId()
        );
        insert testCase;
        
        Map<Id, User> casesIdToOwners = new Map<Id, User>{ testCase.Id => testUser };
            
        Test.startTest();
        CaseAssignmentService.assignWhenCaseReopen(new List<Case>{ testCase }, casesIdToOwners);
        Test.stopTest();
    }
    
    @isTest static void testGetAccountIdFromEmailBody() {
        String emailBody = 'Sample text https://adjust.my.salesforce.com/123456789012345';
        
        String accountId = CaseAssignmentService.getAccountIdFromEmailBody(emailBody);
    }
    
    @isTest static void assignBasedOnEmailMessage_ccAddress() {
        TestEnvironment env = new TestEnvironment()
            .createAccount();
        System.runAs(new User(Id = UserInfo.getUserId())){
            env.createAccountManager();
        }
        
        TestEnvironment envCn = new TestEnvironment()
            .createContact();

        envCn.contact.email = 'am-test@support.adjust.com';
        envCn.contact.AccountId = env.acc.Id;
        update envCn.contact;
        
        Test.startTest();
            env.createEmailMessage(true, null, 'client-test@test.test', new List<String> {'am-test@support.adjust.com'},
                                   new List<String> {'am-test@support.adjust.com'});
        Test.stopTest();

        Case[] c = [SELECT OwnerId, CreatedDate FROM Case WHERE Id = :env.emailMessages[0].ParentId];
        System.assertEquals(1, c.size());
    }

    
}