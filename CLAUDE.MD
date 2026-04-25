# Salesforce Unmanaged Package Build Guidelines for Claude Code

## Overview
This document provides comprehensive guidelines for using Claude Code and the Salesforce DX MCP server to build a secure, production-ready unmanaged Salesforce package for internal use.

---

## Table of Contents
1. [Project Setup & Structure](#project-setup--structure)
2. [Security Best Practices](#security-best-practices)
3. [Development Workflow](#development-workflow)
4. [Package Creation & Versioning](#package-creation--versioning)
5. [Deployment Strategy](#deployment-strategy)
6. [Testing & Validation](#testing--validation)
7. [MCP Server Integration](#mcp-server-integration)
8. [Common Commands & Patterns](#common-commands--patterns)
9. [Troubleshooting](#troubleshooting)

---

## Project Setup & Structure

### Directory Organization
```
salesforce-package/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/           # Apex classes & tests
│           ├── triggers/          # Apex triggers
│           ├── objects/           # Custom objects & fields
│           ├── flows/             # Flow definitions
│           ├── permissionsets/    # Permission sets
│           ├── profiles/          # Profiles (use sparingly)
│           ├── pages/             # Visualforce pages
│           ├── components/        # Visualforce components
│           ├── staticresources/   # Static resources
│           ├── lwc/               # Lightning Web Components
│           ├── aura/              # Aura components
│           ├── custommetadata/    # Custom metadata types
│           └── contentassets/     # Content Assets
├── .sfdx/                          # SFDX config
├── .gitignore                      # Git ignore rules
├── sfdx-project.json              # SFDX project config
├── package.xml                     # Package manifest
├── README.md                       # Project documentation
└── scripts/                        # Deployment scripts
```

### sfdx-project.json Template
```json
{
  "sfdcLoginUrl": "https://login.salesforce.com",
  "packageDirectories": [
    {
      "path": "force-app",
      "package": "YourPackageName",
      "versionNumber": "1.0.0.0",
      "default": true
    }
  ],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "61.0"
}
```

### Initial Setup Steps
1. **Initialize project**: `sfdx project generate --name YourPackageName`
2. **Authenticate org**: `sfdx auth web login --instance-url https://login.salesforce.com --alias YourOrgAlias`
3. **Set default org**: `sfdx config set defaultusername=YourOrgAlias`
4. **Create .gitignore**: Exclude `.sfdx`, `node_modules`, `.DS_Store`, sensitive files

---

## Security Best Practices

### Code Security

#### Apex Code
- **Input Validation**: Always validate and sanitize user input to prevent injection attacks
  ```apex
  // Good: Validate and escape
  String sanitized = String.escapeSingleQuotes(userInput);
  
  // Bad: Direct concatenation
  String query = 'SELECT Id FROM Account WHERE Name = ' + userInput;
  ```

- **SOQL Injection Prevention**: Use bind variables, never string concatenation
  ```apex
  // Good
  List<Account> accounts = [SELECT Id FROM Account WHERE Name = :searchTerm];
  
  // Bad - Vulnerable
  List<Account> accounts = Database.query('SELECT Id FROM Account WHERE Name = ' + searchTerm);
  ```

- **DML Exception Handling**: Always handle DML exceptions
  ```apex
  try {
    insert newRecords;
  } catch (DmlException e) {
    System.debug('DML Error: ' + e.getMessage());
    // Log and handle appropriately
  }
  ```

- **Avoid Hard-Coded Values**: Use custom metadata, custom settings, or environment variables
  ```apex
  // Good
  Map<String, MyCustomSetting__c> settings = MyCustomSetting__c.getAll();
  
  // Bad
  String apiKey = 'hardcodedkey123';
  ```

#### Governor Limits Awareness
- Respect Salesforce governor limits (100 SOQL queries, 150 DML statements per transaction)
- Use batch processing for large data volumes
- Implement query result limits: `LIMIT 10000`

#### API & External Communications
- **Authentication**: Use OAuth 2.0, never basic auth with passwords
- **HTTPS Only**: All external calls must use HTTPS
- **Timeout Handling**: Set appropriate timeouts on HTTP callouts
  ```apex
  Http http = new Http();
  HttpRequest request = new HttpRequest();
  request.setTimeout(30000); // 30 seconds
  ```
- **Rate Limiting**: Implement backoff strategies for API calls

### Data Security

#### Field-Level Security (FLS)
- Use `Schema.DescribeSObjectResult` to check FLS
  ```apex
  if (Schema.SObjectType.Account.fields.Phone.isAccessible()) {
    // Safe to query/display
  }
  ```

#### Object-Level Security (OLS)
- Check create/read/update/delete permissions
  ```apex
  if (Schema.SObjectType.Account.isCreateable()) {
    insert newAccount;
  }
  ```

#### Permission-Based Access
- Create specific permission sets for package features
- Document which permission set grants access to which features
- Use least privilege principle

#### Sensitive Data Handling
- Never log sensitive data (passwords, tokens, SSNs, credit cards)
- Use encrypted custom fields for sensitive information
- Implement field-level masking where needed

### Configuration Security

#### Package Metadata
- **No Hardcoded Credentials**: Use Named Credentials or environment variables
- **Minimal Permissions**: Permission sets should grant only necessary permissions
- **No System Administrator Profile**: Never modify System Administrator profile in package
- **Restrict Custom Metadata**: Use permission sets to control access

#### Salesforce CLI & Authentication
- Use `sfdx auth web login` (never store credentials in code)
- Regularly rotate authentication tokens
- Store org aliases in `.sfdx/sfdx-config.json` (never in version control)
- Use `--secure-string-input` flag for sensitive data

### Testing Security

#### Apex Test Coverage
- Achieve minimum 75% code coverage (aim for 90%+)
- Test security boundaries and edge cases
  ```apex
  @isTest
  private class SecurityTest {
    @isTest
    static void testFLSEnforcement() {
      // Verify FLS is respected
      // Verify OLS is respected
      // Verify permission set requirements
    }
  }
  ```

#### Negative Test Cases
- Test with restricted users
- Test with minimal permissions
- Test with invalid/malicious input

---

## Development Workflow

### 1. Feature Branch Strategy
```
main (production-ready)
├── develop (integration branch)
├── feature/feature-name
├── bugfix/bug-name
└── security/security-patch
```

### 2. Local Development Cycle
1. Create feature branch: `git checkout -b feature/feature-name`
2. Retrieve metadata: `sfdx force:source:pull`
3. Create/modify code in `force-app/main/default/`
4. Run tests locally: `sfdx force:apex:test:run`
5. Push changes: `sfdx force:source:push`
6. Commit and push to git

### 3. Code Organization Standards

#### Naming Conventions
| Type | Convention | Example |
|------|-----------|---------|
| Classes | PascalCase, descriptive | `AccountManager`, `InvoiceProcessor` |
| Triggers | ObjectName + Trigger | `AccountTrigger`, `OpportunityTrigger` |
| Methods | camelCase, action-verb | `processAccount()`, `validateEmail()` |
| Variables | camelCase | `accountList`, `isProcessing` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_TIMEOUT` |
| Custom Objects | PascalCase + `__c` | `Invoice__c`, `ProjectTask__c` |
| Custom Fields | snake_case + `__c` | `total_amount__c`, `is_active__c` |

#### File Organization
- One public class per file
- Inner classes for helpers are acceptable
- Triggers should be thin (delegate to handler classes)
- Organize methods: public → protected → private

---

## Package Creation & Versioning

### Version Numbering Scheme
Follow semantic versioning: `MAJOR.MINOR.PATCH.BUILD`
- **MAJOR**: Breaking changes, significant features
- **MINOR**: New features, non-breaking enhancements
- **PATCH**: Bug fixes
- **BUILD**: Build number (auto-incremented)

Example: `1.2.3.0`

### Package Manifest (package.xml)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>AccountManager</members>
        <members>AccountTrigger</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Account.Phone</members>
        <members>Account.Custom_Field__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>Custom_Permission_Set</members>
        <name>PermissionSet</name>
    </types>
    <version>61.0</version>
</Package>
```

### Creating Package Versions
1. **Update sfdx-project.json** with new version number
2. **Generate package.xml**: `sfdx force:source:manifest:create --outputdir ./manifest`
3. **Tag release**: `git tag -a v1.0.0 -m "Release version 1.0.0"`
4. **Push to repository**: `git push origin --tags`

---

## Deployment Strategy

### Deployment Environments
- **Dev Org**: Individual developer workspaces
- **Staging/QA Org**: Integration and UAT testing
- **Production Org**: Live environment

### Deployment Process

#### Step 1: Pre-Deployment Validation
```bash
# Validate code without deploying
sfdx force:mdapi:deploy \
  --deploydir ./force-app \
  --testlevel RunLocalTests \
  --validateonly \
  --wait 30
```

#### Step 2: Deployment with Tests
```bash
# Deploy with all tests running
sfdx force:mdapi:deploy \
  --deploydir ./force-app \
  --testlevel RunLocalTests \
  --targetusername YourProdAlias \
  --wait 30 \
  --rollbackonerror
```

#### Step 3: Post-Deployment Verification
- Verify apex test results: 100% pass rate
- Check for warnings/errors
- Validate data integrity
- Test core functionality in target org

### Rollback Procedure
If deployment fails or issues are discovered:
1. Identify the problematic version
2. Revert to previous stable version tag
3. Deploy previous version to restore functionality
4. Investigate and fix issues in feature branch
5. Test thoroughly before re-deploying

---

## Testing & Validation

### Unit Test Requirements

#### Test Class Structure
```apex
@isTest
private class AccountManagerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }
    
    @isTest
    static void testPositiveScenario() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        // Act
        AccountManager.processAccount(testAccount.Id);
        
        // Assert
        Account result = [SELECT Id, ProcessedDate__c FROM Account WHERE Id = :testAccount.Id];
        System.assertNotEquals(null, result.ProcessedDate__c);
    }
    
    @isTest
    static void testNegativeScenario() {
        // Test error handling
        try {
            AccountManager.processAccount(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Account ID cannot be null'));
        }
    }
    
    @isTest
    static void testSecurityBoundary() {
        // Test FLS/OLS enforcement
        System.assert(Schema.SObjectType.Account.fields.Phone.isAccessible());
    }
}
```

#### Test Execution
```bash
# Run all tests
sfdx force:apex:test:run --testlevel RunLocalTests --wait 30

# Run specific test class
sfdx force:apex:test:run --classnames AccountManagerTest --wait 30

# Generate code coverage report
sfdx force:apex:test:run --codecoverage --outputdir ./test-results
```

### Integration Testing
- Test custom object relationships
- Validate trigger interactions
- Test permission set enforcement
- Verify flow execution

### Security Testing Checklist
- [ ] SOQL injection attempts blocked
- [ ] CSRF protection validated
- [ ] FLS/OLS properly enforced
- [ ] Sensitive data not logged
- [ ] External API calls secure (HTTPS, auth)
- [ ] Batch operations handle governor limits
- [ ] Error messages don't expose sensitive info

---

## MCP Server Integration

### Salesforce DX MCP Server Setup
The Salesforce DX MCP server provides programmatic access to SFDX commands and Salesforce APIs.

### Using MCP for Package Building
Claude Code can leverage the MCP server for:

#### Retrieving Org Metadata
```
Use MCP to pull latest metadata from org to verify changes
Retrieve specific metadata types for inspection
List all custom objects, fields, and permissions
```

#### Executing SFDX Commands
```
Create and manage org connections
Deploy code and run validations
Execute test suites and retrieve results
Generate package manifests
```

#### Creating Artifacts
```
Generate metadata XML files programmatically
Create Apex classes with proper structure
Build custom object definitions
Generate permission sets and configurations
```

### MCP Command Patterns for Package Building
- **List Orgs**: Get available authenticated orgs
- **Query Metadata**: Inspect custom objects, fields, classes
- **Deploy**: Push changes with validation
- **Execute Tests**: Run Apex tests and retrieve coverage
- **Generate Packages**: Create versioned packages

### Authentication
- MCP server uses existing SFDX authentication
- Set default org: `sfdx config set defaultusername=YourOrgAlias`
- Multiple orgs can be managed through org aliases

---

## Common Commands & Patterns

### Authentication & Configuration
```bash
# Web login (recommended)
sfdx auth web login --instance-url https://login.salesforce.com --alias MyOrg

# List authenticated orgs
sfdx auth list

# Set default org
sfdx config set defaultusername=MyOrg

# Display config
sfdx config get defaultusername
```

### Source Control
```bash
# Retrieve from org (pull latest changes)
sfdx force:source:pull

# Push to org (deploy local changes)
sfdx force:source:push

# View local changes not pushed
sfdx force:source:status

# Retrieve specific metadata
sfdx force:mdapi:retrieve --retrievetargetdir ./retrieved --unpackaged ./manifest/package.xml
```

### Testing
```bash
# Run all local tests
sfdx force:apex:test:run --testlevel RunLocalTests

# Run specific test with debug log
sfdx force:apex:test:run --classnames MyTestClass --debug

# Generate code coverage
sfdx force:apex:test:run --codecoverage --outputdir ./coverage
```

### Deployment
```bash
# Validate only (no deployment)
sfdx force:mdapi:deploy --deploydir ./force-app --validateonly

# Deploy with all tests
sfdx force:mdapi:deploy --deploydir ./force-app --testlevel RunAllTests

# Deploy to specific org
sfdx force:mdapi:deploy --deploydir ./force-app --targetusername ProdOrg
```

### Package Management
```bash
# Create new package version
sfdx force:package:version:create --package "PackageName" --versionname "v1.0"

# Promote package version
sfdx force:package:version:promote --package "PackageName@1.0.0-0"

# Install package in org
sfdx force:package:install --package "04t..." --targetusername TargetOrg
```

### Metadata Retrieval
```bash
# Retrieve all custom objects
sfdx force:mdapi:retrieve --unpackaged ./manifest/objects.xml

# List custom fields on object
sfdx force:schema:sobject:describe --sobjectype Account

# Export data
sfdx force:data:bulk:export --sobjectype Account --csvfile ./accounts.csv
```

---

## Troubleshooting

### Common Issues & Solutions

#### 1. Authentication Failures
**Problem**: `ENOTFOUND` or authentication timeout
**Solution**:
```bash
# Clear cached auth
sfdx auth logout --all

# Re-authenticate
sfdx auth web login --instance-url https://login.salesforce.com --alias MyOrg
```

#### 2. Deployment Failures
**Problem**: Metadata deployment fails with cryptic errors
**Solution**:
```bash
# Validate first
sfdx force:mdapi:deploy --deploydir ./force-app --validateonly

# Check detailed logs
sfdx force:mdapi:deploy --help

# Deploy with verbose output
sfdx force:mdapi:deploy --deploydir ./force-app --verbose
```

#### 3. Test Failures
**Problem**: Unit tests fail in org but pass locally
**Solution**:
- Check org data (test data may differ)
- Verify user permissions and FLS settings
- Check for existing records interfering with tests
- Review org-specific customizations

#### 4. Governor Limit Exceptions
**Problem**: `SOQL limit exceeded` or DML exceptions
**Solution**:
- Refactor to use batch processing
- Move logic to future methods or queueable jobs
- Consolidate SOQL queries using maps
- Implement query result limits

#### 5. FLS/OLS Failures
**Problem**: Code works in dev but fails in production
**Solution**:
```apex
// Always check accessibility
if (Schema.SObjectType.Account.fields.Phone.isAccessible()) {
    // Safe to access
}
```

#### 6. MCP Server Connection Issues
**Problem**: MCP tools not responding
**Solution**:
- Verify default org is set: `sfdx config get defaultusername`
- Ensure authentication is fresh: `sfdx auth list`
- Re-authenticate if token expired
- Check network connectivity

---

## Checklist for Package Completion

### Pre-Release
- [ ] All code passes unit tests (90%+ coverage)
- [ ] Security review completed
- [ ] Input validation implemented
- [ ] SOQL/DML injection prevention verified
- [ ] FLS/OLS enforced where appropriate
- [ ] No hardcoded credentials or sensitive data
- [ ] All external APIs use HTTPS and proper auth
- [ ] Governor limits respected
- [ ] Error handling comprehensive
- [ ] Documentation complete
- [ ] Permission sets configured and documented
- [ ] Package manifest (package.xml) up to date
- [ ] Version number bumped in sfdx-project.json

### Deployment
- [ ] Validation deployment successful
- [ ] All tests pass in target org
- [ ] No post-deployment errors
- [ ] Core functionality verified
- [ ] Data integrity confirmed
- [ ] Deployment time acceptable
- [ ] Release notes created
- [ ] Team notified of deployment

### Post-Release
- [ ] Monitor logs for errors
- [ ] Verify user permissions work as expected
- [ ] Document any issues found
- [ ] Plan for patches/enhancements

---

## Additional Resources

### Salesforce Documentation
- [Salesforce DX Guide](https://developer.salesforce.com/tools/sfdxcli)
- [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
- [Metadata API Guide](https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/)
- [Security Best Practices](https://developer.salesforce.com/docs/atlas.en-us.securityGuide.meta/securityGuide/)

### Code Quality & Security
- [Salesforce Certified Platform Developer I Study Guide](https://trailhead.salesforce.com/en/content/learn/modules/platform_dev_basics)
- [Apex Code Best Practices](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_best_practices.htm)
- [Governor Limits](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm)

### Tools & Scripts
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli)
- [VSCode Salesforce Extensions](https://marketplace.visualstudio.com/items?itemName=Salesforce.salesforcedx-vscode)
- [Salesforce Scanner](https://github.com/salesforce/sfdx-scanner)

---

## Document Version History
| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024 | Initial creation - Comprehensive guidelines for secure unmanaged package development |

---

## When using Salesforce Agents
## You are the orchestrator — never the implementer

Delegate ALL Salesforce implementation work. Never write `.cls`, `.trigger`, `.xml`, `.html`, `.js` files yourself.

---

## Workflow

```
Design (creates branch) → Admin (commits metadata) → Developer (commits code)
    → Unit Testing (commits tests) → Code Review → Documentation (commits docs + pushes)
                                                              ↓
                                              DevOps (scratch org validation
                                              → optional sandbox deploy
                                              → creates PR to dev branch)
                                                              ↓
                                                User merges PR into dev
```

| Step | Agent | Model | Role |
|------|-------|-------|------|
| 1 | `salesforce-design` | opus | Analyzes request, creates feature branch |
| 2 | `salesforce-admin` | sonnet | Creates metadata, commits to branch |
| 3 | `salesforce-developer` | sonnet | Writes Apex/LWC, commits to branch |
| 4 | `salesforce-unit-testing` | sonnet | Writes tests, commits to branch |
| 5 | `salesforce-code-review` | sonnet | Reviews branch — read only, no commits |
| 6 | `salesforce-documentation` | sonnet | Writes docs, commits + pushes final branch |
| 7 | `salesforce-devops` | sonnet | Scratch org validation → optional sandbox deploy → creates PR to dev |

---

## Branch flow

- `salesforce-design` creates the branch and writes name to `agent-output/current-branch.md`
- Every agent reads `agent-output/current-branch.md` to know which branch to use
- All agents except devops commit to the feature branch — never to main
- `salesforce-devops` runs after code review passes — it validates, deploys, and creates the PR
- All PRs target `dev`, never `main` — the CI/CD pipeline picks up from dev

---

## Confirmation gates

- **Gate 1** — After design outputs plan: ask yes / no / changes — branch created after yes
- **Gate 2** — After code review: show verdict, offer fix / skip / cancel
- **Gate 3** — Inside devops (multi-step):
  1. Confirm ready to run pipeline → A / C
  2. Show component list, confirm scratch org validation → A / C
  3. After scratch org passes → offer sandbox deploy → Y / N
  4. After sandbox deploy → offer PR to dev branch → Y / N

---

## Skip rules

User must explicitly say "skip [agent name]". Default is always full workflow.

---

## Project conventions

```
API Version:      66.0
Field prefix:     
Package dir:      force-app/main/default
Trigger pattern:  one trigger per object → handler class
Deployment:       Salesforce MCP only (no sf/sfdx CLI for deploys)
Docs location:    docs/
Agent output:     agent-output/
Branch file:      agent-output/current-branch.md
```

---

## Code review gate logic

```
APPROVED or APPROVED WITH WARNINGS → proceed to documentation
CHANGES REQUIRED → ask user:
  [F] Fix — send back to salesforce-developer, re-commit, re-review
  [S] Skip — proceed with warning
  [C] Cancel
```
