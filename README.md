# Azure Subscriptionator

Setup a pipeline that will make it possible to source control and deploy everything that is needed to create a subscription and securely roll it out to a dev team.

Definitions:
- Management Group
- AAD Group
- Subscription
- Resource Provider Registration
- Role Definition
- Policy Definition
- Policy Set Definition
- Azure Blueprint Definition

Assignments:
- Assign Subscription to Management Group 
- Role Assignment (to AAD group, AAD User, AAD application)
- Policy Assignment (to subscription and management group)
- Policy Set Assignment (to subscription and management group)
- Azure Blueprint Assignment (to subscription). This requires the `Microsoft.Blueprint` resource provider to be registered with each subscription that has a Blueprint assigned to it.

# Status
Alpha. Code is still being implemented. 

# LICENSE
MIT - see LICENSE.txt

# Best practices

- Definitions should be stored as high up the hierachy as possible
- Assignments should be applied as low down the hierachy as possible
- Policy set assignments should be used in favour of policy assignments
- Role assignments should be applied to AAD Groups and not directly to users or applications
- Role definition will be formated as a single json file called "role name.json"
- Policy definition will be formated following the microsoft convention https://github.com/Azure/azure-policy/tree/master/samples/Authorization/allowed-role-definitions
- Policy set definition will be formated following the microsoft convention https://github.com/Azure/azure-policy/tree/master/samples/PolicyInitiatives/multiple-billing-tags
- The last management group in the hiearchy should be reserved for usage by the dev team of the subscription. This will allow them to store their own definitions so that they can apply their own assignments to resource groups in the subscription

# Framework limitations

- Role assignment: only supports assignment against management group and subscription, so can't be applied directly against other providers. Possible work around is to abstracted this by using RoleDefinition that is applied at management group or subscription
- Auto publish of Azure Blueprint will generate a release version name based on current date time.
- Subscription: Azure api only allows EA Azure customers to create subscriptions programmatically. One day the framework might provide browser automation or direct api usage equivalent to do so. https://docs.microsoft.com/en-us/azure/azure-resource-manager/programmatically-create-subscription?tabs=rest

# Framework features

- AAD Group: topologically sort AAD groups so that they get created and deleted in the correct order
- Management Group: topologically sort management groups so that they get created and deleted in the correct order
- Resource Provider registration: AssignmentScope currently cannot be set to the root scope ("/") or a management group scope so we provide this functionality by expanding root scope or management group scope into multiple subscription scopes. This does mean if you add a new subscription or change a subscriptions management group hiearchy the ci/cd process will need to be re-run to fix it. 
- Role definition: AssignmentScope currently cannot be set to the root scope ("/") or a management group scope https://feedback.azure.com/forums/911473-azure-management-groups/suggestions/34391878-allow-custom-rbac-definitions-at-the-management-gr so we provide this functionality by expanding root scope or management group scope into multiple subscription scopes. This does mean if you add a new subscription or change a subscriptions management group hiearchy the ci/cd process will need to be re-run to fix it.
- Blueprint assignment: Assignments currently cannot be set to the root scope ("/") or a management group scope https://feedback.azure.com/forums/915958-azure-governance/suggestions/35803750-azure-blueprints-assignment-to-management-group so we provide this functionality by expanding root scope or management group scope into multiple subscription scopes. This does mean if you add a new subscription or change a subscriptions management group hiearchy the ci/cd process will need to be re-run to fix it.
