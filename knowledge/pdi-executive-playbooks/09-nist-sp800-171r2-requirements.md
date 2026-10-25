---
kb: "PDI • Executive Playbooks"
doc: "NIST SP 800-171 Rev 2 Requirements (all 110)"
authority: "AUTHORITATIVE. Generated verbatim from NIST CPRT export SP_800_171_2_0_0, retrieved 2026-10-22. US Government work (public domain). Do not hand-edit; regenerate from NIST."
owner: CISO
---

# NIST SP 800-171 Revision 2: Security Requirements (all 110)

NIST SP 800-171 Rev 2, "Protecting Controlled Unclassified Information in Nonfederal Systems and Organizations." CMMC Level 2 is built on these 110 requirements. Quote requirement numbers and text **only** from this document. Scoring weights (DoD Assessment Methodology / SPRS) are not included here.

## Quick reference: most-asked requirements

| Topic | Requirement | NIST text |
|---|---|---|
| Limit system access to authorized users | **3.1.1** | Limit system access to authorized users, processes acting on behalf of authorized users, and devices (including other systems). |
| Least privilege | **3.1.5** | Employ the principle of least privilege, including for specific security functions and privileged accounts. |
| Unsuccessful logon attempts | **3.1.8** | Limit unsuccessful logon attempts. |
| Session lock | **3.1.10** | Use session lock with pattern-hiding displays to prevent access and viewing of data after a period of inactivity. |
| Remote access monitoring/control | **3.1.12** | Monitor and control remote access sessions. |
| Security awareness | **3.2.1** | Ensure that managers, systems administrators, and users of organizational systems are made aware of the security risks associated with their activities and of the applicable policies, standards, and procedures related to the security of those systems. |
| Audit logs and records | **3.3.1** | Create and retain system audit logs and records to the extent needed to enable the monitoring, analysis, investigation, and reporting of unlawful or unauthorized system activity. |
| Baseline configurations and inventories | **3.4.1** | Establish and maintain baseline configurations and inventories of organizational systems (including hardware, software, firmware, and documentation) throughout the respective system development life cycles. |
| Least functionality | **3.4.6** | Employ the principle of least functionality by configuring organizational systems to provide only essential capabilities. |
| Identify users, processes, devices | **3.5.1** | Identify system users, processes acting on behalf of users, and devices. |
| Multifactor authentication (MFA) | **3.5.3** | Use multifactor authentication for local and network access to privileged accounts and for network access to non-privileged accounts. |
| Password complexity | **3.5.7** | Enforce a minimum password complexity and change of characters when new passwords are created. |
| Incident-handling capability | **3.6.1** | Establish an operational incident-handling capability for organizational systems that includes preparation, detection, analysis, containment, recovery, and user response activities. |
| Incident tracking and reporting | **3.6.2** | Track, document, and report incidents to designated officials and/or authorities both internal and external to the organization. |
| Media sanitization | **3.8.3** | Sanitize or destroy system media containing CUI before disposal or release for reuse. |
| Encrypt CUI on digital media in transport | **3.8.6** | Implement cryptographic mechanisms to protect the confidentiality of CUI stored on digital media during transport unless otherwise protected by alternative physical safeguards. |
| Backup CUI confidentiality | **3.8.9** | Protect the confidentiality of backup CUI at storage locations. |
| Personnel screening | **3.9.1** | Screen individuals prior to authorizing access to organizational systems containing CUI. |
| Physical access limits | **3.10.1** | Limit physical access to organizational systems, equipment, and the respective operating environments to authorized individuals. |
| Risk assessment | **3.11.1** | Periodically assess the risk to organizational operations (including mission, functions, image, or reputation), organizational assets, and individuals, resulting from the operation of organizational systems and the associated processing, storage, or transmission of CUI. |
| Vulnerability scanning | **3.11.2** | Scan for vulnerabilities in organizational systems and applications periodically and when new vulnerabilities affecting those systems and applications are identified. |
| Plans of action (POA&M) | **3.12.2** | Develop and implement plans of action designed to correct deficiencies and reduce or eliminate vulnerabilities in organizational systems. |
| System security plan (SSP) | **3.12.4** | Develop, document, and periodically update system security plans that describe system boundaries, system environments of operation, how security requirements are implemented, and the relationships with or connections to other systems. |
| Boundary protection | **3.13.1** | Monitor, control, and protect communications (i.e., information transmitted or received by organizational systems) at the external boundaries and key internal boundaries of organizational systems. |
| Deny by default / allow by exception | **3.13.6** | Deny network communications traffic by default and allow network communications traffic by exception (i.e., deny all, permit by exception). |
| Encrypt CUI in transit | **3.13.8** | Implement cryptographic mechanisms to prevent unauthorized disclosure of CUI during transmission unless otherwise protected by alternative physical safeguards. |
| FIPS-validated cryptography | **3.13.11** | Employ FIPS-validated cryptography when used to protect the confidentiality of CUI. |
| Protect CUI at rest | **3.13.16** | Protect the confidentiality of CUI at rest. |
| Flaw remediation (patching) | **3.14.1** | Identify, report, and correct system flaws in a timely manner. |
| Malicious code protection | **3.14.2** | Provide protection from malicious code at designated locations within organizational systems. |
| Security alerts and advisories | **3.14.3** | Monitor system security alerts and advisories and take action in response. |

## 3.1 Access Control (AC): 22 requirements

- **3.1.1** · Access Control (AC) · Basic requirement: Limit system access to authorized users, processes acting on behalf of authorized users, and devices (including other systems).
- **3.1.2** · Access Control (AC) · Basic requirement: Limit system access to the types of transactions and functions that authorized users are permitted to execute.
- **3.1.3** · Access Control (AC) · Derived requirement: Control the flow of CUI in accordance with approved authorizations.
- **3.1.4** · Access Control (AC) · Derived requirement: Separate the duties of individuals to reduce the risk of malevolent activity without collusion.
- **3.1.5** · Access Control (AC) · Derived requirement: Employ the principle of least privilege, including for specific security functions and privileged accounts.
- **3.1.6** · Access Control (AC) · Derived requirement: Use non-privileged accounts or roles when accessing nonsecurity functions.
- **3.1.7** · Access Control (AC) · Derived requirement: Prevent non-privileged users from executing privileged functions and capture the execution of such functions in audit logs.
- **3.1.8** · Access Control (AC) · Derived requirement: Limit unsuccessful logon attempts.
- **3.1.9** · Access Control (AC) · Derived requirement: Provide privacy and security notices consistent with applicable CUI rules.
- **3.1.10** · Access Control (AC) · Derived requirement: Use session lock with pattern-hiding displays to prevent access and viewing of data after a period of inactivity.
- **3.1.11** · Access Control (AC) · Derived requirement: Terminate (automatically) a user session after a defined condition.
- **3.1.12** · Access Control (AC) · Derived requirement: Monitor and control remote access sessions.
- **3.1.13** · Access Control (AC) · Derived requirement: Employ cryptographic mechanisms to protect the confidentiality of remote access sessions.
- **3.1.14** · Access Control (AC) · Derived requirement: Route remote access via managed access control points.
- **3.1.15** · Access Control (AC) · Derived requirement: Authorize remote execution of privileged commands and remote access to security-relevant information.
- **3.1.16** · Access Control (AC) · Derived requirement: Authorize wireless access prior to allowing such connections.
- **3.1.17** · Access Control (AC) · Derived requirement: Protect wireless access using authentication and encryption.
- **3.1.18** · Access Control (AC) · Derived requirement: Control connection of mobile devices.
- **3.1.19** · Access Control (AC) · Derived requirement: Encrypt CUI on mobile devices and mobile computing platforms.
- **3.1.20** · Access Control (AC) · Derived requirement: Verify and control/limit connections to and use of external systems.
- **3.1.21** · Access Control (AC) · Derived requirement: Limit use of portable storage devices on external systems.
- **3.1.22** · Access Control (AC) · Derived requirement: Control CUI posted or processed on publicly accessible systems.

## 3.2 Awareness and Training (AT): 3 requirements

- **3.2.1** · Awareness and Training (AT) · Basic requirement: Ensure that managers, systems administrators, and users of organizational systems are made aware of the security risks associated with their activities and of the applicable policies, standards, and procedures related to the security of those systems.
- **3.2.2** · Awareness and Training (AT) · Basic requirement: Ensure that personnel are trained to carry out their assigned information security-related duties and responsibilities.
- **3.2.3** · Awareness and Training (AT) · Derived requirement: Provide security awareness training on recognizing and reporting potential indicators of insider threat.

## 3.3 Audit and Accountability (AU): 9 requirements

- **3.3.1** · Audit and Accountability (AU) · Basic requirement: Create and retain system audit logs and records to the extent needed to enable the monitoring, analysis, investigation, and reporting of unlawful or unauthorized system activity.
- **3.3.2** · Audit and Accountability (AU) · Basic requirement: Ensure that the actions of individual system users can be uniquely traced to those users, so they can be held accountable for their actions.
- **3.3.3** · Audit and Accountability (AU) · Derived requirement: Review and update logged events.
- **3.3.4** · Audit and Accountability (AU) · Derived requirement: Alert in the event of an audit logging process failure.
- **3.3.5** · Audit and Accountability (AU) · Derived requirement: Correlate audit record review, analysis, and reporting processes for investigation and response to indications of unlawful, unauthorized, suspicious, or unusual activity.
- **3.3.6** · Audit and Accountability (AU) · Derived requirement: Provide audit record reduction and report generation to support on-demand analysis and reporting.
- **3.3.7** · Audit and Accountability (AU) · Derived requirement: Provide a system capability that compares and synchronizes internal system clocks with an authoritative source to generate time stamps for audit records.
- **3.3.8** · Audit and Accountability (AU) · Derived requirement: Protect audit information and audit logging tools from unauthorized access, modification, and deletion.
- **3.3.9** · Audit and Accountability (AU) · Derived requirement: Limit management of audit logging functionality to a subset of privileged users.

## 3.4 Configuration Management (CM): 9 requirements

- **3.4.1** · Configuration Management (CM) · Basic requirement: Establish and maintain baseline configurations and inventories of organizational systems (including hardware, software, firmware, and documentation) throughout the respective system development life cycles.
- **3.4.2** · Configuration Management (CM) · Basic requirement: Establish and enforce security configuration settings for information technology products employed in organizational systems.
- **3.4.3** · Configuration Management (CM) · Derived requirement: Track, review, approve or disapprove, and log changes to organizational systems.
- **3.4.4** · Configuration Management (CM) · Derived requirement: Analyze the security impact of changes prior to implementation.
- **3.4.5** · Configuration Management (CM) · Derived requirement: Define, document, approve, and enforce physical and logical access restrictions associated with changes to organizational systems.
- **3.4.6** · Configuration Management (CM) · Derived requirement: Employ the principle of least functionality by configuring organizational systems to provide only essential capabilities.
- **3.4.7** · Configuration Management (CM) · Derived requirement: Restrict, disable, or prevent the use of nonessential programs, functions, ports, protocols, and services.
- **3.4.8** · Configuration Management (CM) · Derived requirement: Apply deny-by-exception (blacklisting) policy to prevent the use of unauthorized software or deny-all, permit-by-exception (whitelisting) policy to allow the execution of authorized software.
- **3.4.9** · Configuration Management (CM) · Derived requirement: Control and monitor user-installed software.

## 3.5 Identification and Authentication (IA): 11 requirements

- **3.5.1** · Identification and Authentication (IA) · Basic requirement: Identify system users, processes acting on behalf of users, and devices.
- **3.5.2** · Identification and Authentication (IA) · Basic requirement: Authenticate (or verify) the identities of users, processes, or devices, as a prerequisite to allowing access to organizational systems.
- **3.5.3** · Identification and Authentication (IA) · Derived requirement: Use multifactor authentication for local and network access to privileged accounts and for network access to non-privileged accounts.
- **3.5.4** · Identification and Authentication (IA) · Derived requirement: Employ replay-resistant authentication mechanisms for network access to privileged and nonprivileged accounts.
- **3.5.5** · Identification and Authentication (IA) · Derived requirement: Prevent reuse of identifiers for a defined period.
- **3.5.6** · Identification and Authentication (IA) · Derived requirement: Disable identifiers after a defined period of inactivity.
- **3.5.7** · Identification and Authentication (IA) · Derived requirement: Enforce a minimum password complexity and change of characters when new passwords are created.
- **3.5.8** · Identification and Authentication (IA) · Derived requirement: Prohibit password reuse for a specified number of generations.
- **3.5.9** · Identification and Authentication (IA) · Derived requirement: Allow temporary password use for system logons with an immediate change to a permanent password.
- **3.5.10** · Identification and Authentication (IA) · Derived requirement: Store and transmit only cryptographically-protected passwords.
- **3.5.11** · Identification and Authentication (IA) · Derived requirement: Obscure feedback of authentication information.

## 3.6 Incident Response (IR): 3 requirements

- **3.6.1** · Incident Response (IR) · Basic requirement: Establish an operational incident-handling capability for organizational systems that includes preparation, detection, analysis, containment, recovery, and user response activities.
- **3.6.2** · Incident Response (IR) · Basic requirement: Track, document, and report incidents to designated officials and/or authorities both internal and external to the organization.
- **3.6.3** · Incident Response (IR) · Derived requirement: Test the organizational incident response capability.

## 3.7 Maintenance (MA): 6 requirements

- **3.7.1** · Maintenance (MA) · Basic requirement: Perform maintenance on organizational systems.
- **3.7.2** · Maintenance (MA) · Basic requirement: Provide controls on the tools, techniques, mechanisms, and personnel used to conduct system maintenance.
- **3.7.3** · Maintenance (MA) · Derived requirement: Ensure equipment removed for off-site maintenance is sanitized of any CUI.
- **3.7.4** · Maintenance (MA) · Derived requirement: Check media containing diagnostic and test programs for malicious code before the media are used in organizational systems.
- **3.7.5** · Maintenance (MA) · Derived requirement: Require multifactor authentication to establish nonlocal maintenance sessions via external network connections and terminate such connections when nonlocal maintenance is complete.
- **3.7.6** · Maintenance (MA) · Derived requirement: Supervise the maintenance activities of maintenance personnel without required access authorization.

## 3.8 Media Protection (MP): 9 requirements

- **3.8.1** · Media Protection (MP) · Basic requirement: Protect (i.e., physically control and securely store) system media containing CUI, both paper and digital.
- **3.8.2** · Media Protection (MP) · Basic requirement: Limit access to CUI on system media to authorized users.
- **3.8.3** · Media Protection (MP) · Basic requirement: Sanitize or destroy system media containing CUI before disposal or release for reuse.
- **3.8.4** · Media Protection (MP) · Derived requirement: Mark media with necessary CUI markings and distribution limitations.
- **3.8.5** · Media Protection (MP) · Derived requirement: Control access to media containing CUI and maintain accountability for media during transport outside of controlled areas.
- **3.8.6** · Media Protection (MP) · Derived requirement: Implement cryptographic mechanisms to protect the confidentiality of CUI stored on digital media during transport unless otherwise protected by alternative physical safeguards.
- **3.8.7** · Media Protection (MP) · Derived requirement: Control the use of removable media on system components.
- **3.8.8** · Media Protection (MP) · Derived requirement: Prohibit the use of portable storage devices when such devices have no identifiable owner.
- **3.8.9** · Media Protection (MP) · Derived requirement: Protect the confidentiality of backup CUI at storage locations.

## 3.9 Personnel Security (PS): 2 requirements

- **3.9.1** · Personnel Security (PS) · Basic requirement: Screen individuals prior to authorizing access to organizational systems containing CUI.
- **3.9.2** · Personnel Security (PS) · Basic requirement: Ensure that organizational systems containing CUI are protected during and after personnel actions such as terminations and transfers.

## 3.10 Physical Protection (PE): 6 requirements

- **3.10.1** · Physical Protection (PE) · Basic requirement: Limit physical access to organizational systems, equipment, and the respective operating environments to authorized individuals.
- **3.10.2** · Physical Protection (PE) · Basic requirement: Protect and monitor the physical facility and support infrastructure for organizational systems.
- **3.10.3** · Physical Protection (PE) · Derived requirement: Escort visitors and monitor visitor activity.
- **3.10.4** · Physical Protection (PE) · Derived requirement: Maintain audit logs of physical access.
- **3.10.5** · Physical Protection (PE) · Derived requirement: Control and manage physical access devices.
- **3.10.6** · Physical Protection (PE) · Derived requirement: Enforce safeguarding measures for CUI at alternate work sites.

## 3.11 Risk Assessment (RA): 3 requirements

- **3.11.1** · Risk Assessment (RA) · Basic requirement: Periodically assess the risk to organizational operations (including mission, functions, image, or reputation), organizational assets, and individuals, resulting from the operation of organizational systems and the associated processing, storage, or transmission of CUI.
- **3.11.2** · Risk Assessment (RA) · Derived requirement: Scan for vulnerabilities in organizational systems and applications periodically and when new vulnerabilities affecting those systems and applications are identified.
- **3.11.3** · Risk Assessment (RA) · Derived requirement: Remediate vulnerabilities in accordance with risk assessments.

## 3.12 Security Assessment (CA): 4 requirements

- **3.12.1** · Security Assessment (CA) · Basic requirement: Periodically assess the security controls in organizational systems to determine if the controls are effective in their application.
- **3.12.2** · Security Assessment (CA) · Basic requirement: Develop and implement plans of action designed to correct deficiencies and reduce or eliminate vulnerabilities in organizational systems.
- **3.12.3** · Security Assessment (CA) · Basic requirement: Monitor security controls on an ongoing basis to ensure the continued effectiveness of the controls.
- **3.12.4** · Security Assessment (CA) · Basic requirement: Develop, document, and periodically update system security plans that describe system boundaries, system environments of operation, how security requirements are implemented, and the relationships with or connections to other systems.

## 3.13 System and Communications Protection (SC): 16 requirements

- **3.13.1** · System and Communications Protection (SC) · Basic requirement: Monitor, control, and protect communications (i.e., information transmitted or received by organizational systems) at the external boundaries and key internal boundaries of organizational systems.
- **3.13.2** · System and Communications Protection (SC) · Basic requirement: Employ architectural designs, software development techniques, and systems engineering principles that promote effective information security within organizational systems.
- **3.13.3** · System and Communications Protection (SC) · Derived requirement: Separate user functionality from system management functionality.
- **3.13.4** · System and Communications Protection (SC) · Derived requirement: Prevent unauthorized and unintended information transfer via shared system resources.
- **3.13.5** · System and Communications Protection (SC) · Derived requirement: Implement subnetworks for publicly accessible system components that are physically or logically separated from internal networks.
- **3.13.6** · System and Communications Protection (SC) · Derived requirement: Deny network communications traffic by default and allow network communications traffic by exception (i.e., deny all, permit by exception).
- **3.13.7** · System and Communications Protection (SC) · Derived requirement: Prevent remote devices from simultaneously establishing non-remote connections with organizational systems and communicating via some other connection to resources in external networks (i.e., split tunneling).
- **3.13.8** · System and Communications Protection (SC) · Derived requirement: Implement cryptographic mechanisms to prevent unauthorized disclosure of CUI during transmission unless otherwise protected by alternative physical safeguards.
- **3.13.9** · System and Communications Protection (SC) · Derived requirement: Terminate network connections associated with communications sessions at the end of the sessions or after a defined period of inactivity.
- **3.13.10** · System and Communications Protection (SC) · Derived requirement: Establish and manage cryptographic keys for cryptography employed in organizational systems.
- **3.13.11** · System and Communications Protection (SC) · Derived requirement: Employ FIPS-validated cryptography when used to protect the confidentiality of CUI.
- **3.13.12** · System and Communications Protection (SC) · Derived requirement: Prohibit remote activation of collaborative computing devices and provide indication of devices in use to users present at the device.
- **3.13.13** · System and Communications Protection (SC) · Derived requirement: Control and monitor the use of mobile code.
- **3.13.14** · System and Communications Protection (SC) · Derived requirement: Control and monitor the use of Voice over Internet Protocol (VoIP) technologies.
- **3.13.15** · System and Communications Protection (SC) · Derived requirement: Protect the authenticity of communications sessions.
- **3.13.16** · System and Communications Protection (SC) · Derived requirement: Protect the confidentiality of CUI at rest.

## 3.14 System and Information Integrity (SI): 7 requirements

- **3.14.1** · System and Information Integrity (SI) · Basic requirement: Identify, report, and correct system flaws in a timely manner.
- **3.14.2** · System and Information Integrity (SI) · Basic requirement: Provide protection from malicious code at designated locations within organizational systems.
- **3.14.3** · System and Information Integrity (SI) · Basic requirement: Monitor system security alerts and advisories and take action in response.
- **3.14.4** · System and Information Integrity (SI) · Derived requirement: Update malicious code protection mechanisms when new releases are available.
- **3.14.5** · System and Information Integrity (SI) · Derived requirement: Perform periodic scans of organizational systems and real-time scans of files from external sources as files are downloaded, opened, or executed.
- **3.14.6** · System and Information Integrity (SI) · Derived requirement: Monitor organizational systems, including inbound and outbound communications traffic, to detect attacks and indicators of potential attacks.
- **3.14.7** · System and Information Integrity (SI) · Derived requirement: Identify unauthorized use of organizational systems.

Source: NIST Cybersecurity and Privacy Reference Tool (CPRT), SP 800-171 Rev. 2 export: https://csrc.nist.gov/extensions/nudp/services/json/nudp/framework/version/sp_800_171_2_0_0/export/json?element=all
