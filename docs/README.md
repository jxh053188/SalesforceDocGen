# DocGen Documentation

Welcome to the DocGen documentation hub. This directory contains guides, integration references, and release notes for the Salesforce Document Generation Platform.

---

## What's New

### Release: DocuSign Envelope Configuration Integration (v0.3.0)

**Date:** 2026-04-26  
**Branch:** `feature/2026-04-26-docusign-admin-runner-integration`

This release introduces admin-configured DocuSign envelope configurations, multi-recipient sending, and a simplified document runner experience.

#### New Features

- **Admin-configured DocuSign envelope configurations** — Link a `dfsle__EnvelopeConfiguration__c` record to any DocGen template. Only configurations whose source object matches the template's base object are shown.
- **Auto-populated signer count** — When an envelope configuration is selected, the signer count is read from the managed package metadata and stored on the template. Admins can override it (1–10 signers).
- **Simplified runner** — `docGenRunner` now shows only a template selector and **Preview Document** button. Output mode selection and standalone generation have been removed.
- **Preview modal actions** — After previewing, users can **Download**, **Save to Record**, or **Send with DocuSign** directly from the modal.
- **Multi-recipient DocuSign sending** — The preview modal dynamically renders one contact picker per signer. The document is regenerated with anchor tags and sent to all selected recipients via `dfsle.EnvelopeService.sendEnvelope()`.
- **Flow action multi-recipient support** — The **Generate Document (Native)** invocable action now accepts a comma-separated list of recipient Contact IDs (`recipientContactIds`).

#### Modified Components

| Component | Change |
|-----------|--------|
| `DocGen_Template__c` | Added `DocuSign_Envelope_Configuration__c` (Lookup) and `DocuSign_Signer_Count__c` (Number) |
| `DocGenController` | Added `getDocuSignEnvelopeConfigs()`; updated queries and `saveTemplate` |
| `DocGenDocuSignService` | Added `RecipientInfo` inner class and multi-recipient `sendDocumentForSignature()` overload |
| `DocGenDocuSignController` | Added `generateAndSendWithRecipients()` |
| `DocGenFlowAction` | Added `recipientContactIds` input variable |
| `docGenAdmin` | Added envelope configuration picker and signer count input |
| `docGenRunner` | Removed output mode and Generate button; passes DocuSign config to preview modal |
| `docGenPreviewModal` | Added Save to Record, Send with DocuSign, email subject, and multi-recipient pickers |
| Permission Sets | Added FLS for new fields on `DocGen_Admin` and `DocGen_User` |

---

## Documentation Index

| Document | Audience | Purpose |
|----------|----------|---------|
| [Setup Guide](SETUP_GUIDE.md) | Admins | Initial installation, permission sets, and post-setup verification |
| [Admin Guide](ADMIN_GUIDE.md) | Admins | Creating templates, linking DocuSign envelope configurations, and managing versions |
| [User Guide](USER_GUIDE.md) | End users | Generating documents, previewing, downloading, saving, and sending via DocuSign |
| [DocuSign Integration](DOCUSIGN_INTEGRATION.md) | Admins / Developers | Architecture, anchor tag injection, multi-recipient sending, and Flow action reference |
| [Client-Side Generation](CLIENT_SIDE_GENERATION.md) | Developers | How PDF generation works in the browser, limitations, and supported browsers |
| [Migration Guide](MIGRATION_GUIDE.md) | Admins | Upgrading from older versions, breaking changes, and deprecated features |
| [Security Remediation](security-p0-critical-remediation.md) | Admins / Developers | Post-security-review fixes and hardening recommendations |

---

## Feature List

### Core Document Generation
- **Template Manager** (`docGenAdmin`) — Create, edit, version, and share Word, PowerPoint, and HTML templates.
- **Query Builder** — Point-and-click SOQL configuration with parent and child relationship support.
- **Client-Side Rendering** — Generate DOCX, PPTX, and PDF directly in the browser without server-side callouts.
- **Template Versioning** — Snapshot template configuration with every save; restore any version instantly.
- **Template Sharing** — Share templates with individual users or groups via manual sharing.

### DocuSign eSignature Integration
- **Anchor Tag Injection** — Automatically inject DocuSign anchor tags into Word documents at merge-field positions.
- **Admin-Configured Envelope Configurations** — Link DocuSign envelope configurations to templates for consistent routing, reminders, and expiration settings.
- **Multi-Recipient Sending** — Send documents to up to 10 signers with per-signer contact selection and routing order.
- **Flow Action** — Trigger document generation and DocuSign sending from any Salesforce Flow.
- **Record-Page Component** — Generate and send documents directly from Account, Opportunity, Contract, or any supported object record page.

### Native E-Signature (Experience Cloud)
- **Zero-Cost Signing** — Native electronic signature engine with no third-party dependencies.
- **Experience Cloud Integration** — Public signing portal via Screen Flows with tamper-evident SHA-256 hashing.
- **Audit Trail** — Immutable `DocGen_Signature_Audit__c` records for every signature event.

---

## Quick Links

- **GitHub Repository:** [SalesforceDocGen](https://github.com/jarredharkness/SalesforceDocGen)
- **Package Install (Production/Developer):** `04tdL000000Ny3VQAS`
- **Package Install (Sandbox):** [Sandbox Link](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tdL000000Ny3VQAS)
- **Demo Video:** [YouTube Quick Overview](https://www.youtube.com/watch?v=TAdNItmu2jw)

---

## Change History

| Date | Version | Change |
|------|---------|--------|
| 2026-04-26 | v0.3.0 | DocuSign envelope configuration linking, multi-recipient sending, runner simplification, preview modal expansion |
| 2026-04-25 | v0.2.0 | Initial DocuSign eSignature integration with anchor tag injection and single-recipient sending |
| 2026-04-25 | v0.1.0 | Initial open-source release with client-side generation, template manager, and native e-signature |
