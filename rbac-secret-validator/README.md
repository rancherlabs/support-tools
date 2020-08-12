### Script to evaluate existing RBAC rules against 'Secret' access to find violating rules
#### TODO: Add logic to support namespacedSecrets

You may ask the customer to provide the 'custom_role.json' file using below steps.
 - View the cluster role in API and copy the json data from 'Show Reuqest' after clicking 'Edit' and save the file as 'dummy_role.json'

Pre-requisites:
- Create a user with only login access.
- Create a dummy Cluster role with no rules.
- View the dummy role in API and copy the json data from 'Show Reuqest' after clicking 'Edit' and save the file as 'dummy_role.json'
- Copy 'custom_role.json' and 'dummy_role.json' to the directory where this script is stored.
- Create API key using admin user and replace 'adminToken' with that value
- Create API key using readonly user and replace 'userToken' with that value 

Note: This script can be used as a framework to validate other object access as well 
