#!/usr/bin/python3

#------------------------------------------------------------------------------------------#
# Script to evaluate existing RBAC rules against 'Secret' access to find violating rules
# TODO: Add logic to support namespacedSecrets
#
# You may ask the customer to provide the 'custom_role.json' file using below steps.
# - View the cluster role in API and copy the json data from 'Show Reuqest' after clicking 'Edit' and save the file as 'dummy_role.json'
#
# Pre-requisites:
# - Create a user with only login access.
# - Create a dummy Cluster role with no rules.
# - View the dummy role in API and copy the json data from 'Show Reuqest' after clicking 'Edit' and save the file as 'dummy_role.json'
# - Copy 'custom_role.json' and 'dummy_role.json' to the directory where this script is stored.
# - Create API key using admin user and replace 'adminToken' with that value
# - Create API key using readonly user and replace 'userToken' with that value 
#------------------------------------------------------------------------------------------#
# Note: This script can be used as a framework to validate other object access as well 
# Author: Ansil H
#------------------------------------------------------------------------------------------#

from http.client import HTTPSConnection
from base64 import b64encode
import json
import ssl
import time

user_create = {"type":"clusterRoleTemplateBinding","clusterId":"DUMMY","userPrincipalId":"local://DUMMY","roleTemplateId":"DUMMY"}

#--- START - Change below values ---#
adminToken="token-99q8t:mtkh6hq8vvr9494rl26j8fn59xsxzxzhmdq9d8qkvqc5bxrpkcnmzs"
userToken="token-4d4x9:lcwpjwl9qlw8njbbntndrb66rfh5djhb2vn5d6vphv9tw2kpth9zmm"
userId = "u-s86th"
clusterID = "c-jjcdx"
roleTemplateId = "rt-blnx7"
projectID = "p-wbvcz"
secretName = "testsecret"
rancher = "rancher236.labs.internal"
debug = True
#--- END ---#

MESSAGE = '\033[93m'
GREEN = '\033[92m'
RED = '\033[91m'
END = '\033[0m'
user_create["userPrincipalId"] = "local://" + userId
user_create["clusterId"] = clusterID
user_create["roleTemplateId"] = roleTemplateId

# dummy_role.json contains the json data of an existing role with no rules
with open('dummy_role.json') as f:
  data = json.load(f)
json_data = json.dumps(data)

# custom_role.json is the json data collected from customr system
with open("custom_role.json") as fp:
    data_rbac = json.load(fp)
numberOfRules = len(data_rbac["rules"])
ruleIndex=0
for rbac in data_rbac["rules"]:
    ruleIndex += 1
    if debug:
        print(f"{MESSAGE}Chcking rule..{ruleIndex} of {numberOfRules}{END}",)
        print(rbac)
    data["rules"]=[rbac]
    ### data["rules"].append(rbac) # comment above line and uncomment below to append rules , instead of replacing existing one
    data_rbac_json = json.dumps(data)
    #-----
    # Add rule to the existing role
    #----
    adminPass = b64encode(bytes(adminToken,"utf-8")).decode("utf-8")
    url = "/v3/roleTemplates/" +roleTemplateId
    headers = { 'Authorization' : 'Basic %s' %  adminPass ,'Accept': 'application/json', 'Content-Type': 'application/json' }
    c = HTTPSConnection(rancher,context = ssl._create_unverified_context())
    c.request('PUT', url, data_rbac_json, headers=headers)
    res = c.getresponse()
    data_resp = res.read()
    time.sleep(1)
    #-----
    # Add user to the cluster - role binding
    #-----
    url = "/v3/clusterroletemplatebinding"
    user_create_json = json.dumps(user_create)
    c.request('POST', url, user_create_json, headers=headers)
    res = c.getresponse()
    user_data_resp = json.loads(res.read().decode('utf-8'))
    time.sleep(1)
    #-----
    # Check secret access
    #----
    userPass = b64encode(bytes(userToken,"utf-8")).decode("utf-8")
    url = "/v3/project/"+clusterID+":"+projectID+"/secrets/"+projectID +":"+secretName
    headers = { 'Authorization' : 'Basic %s' %  userPass ,'Accept': 'application/json', 'Content-Type': 'application/json' }
    c.request('GET', url, headers=headers)
    res = c.getresponse()
    data_rbac = json.loads(res.read().decode("utf-8"))
    #print(type(data_rbac))
    #print(data_rbac)
    if "data" in data_rbac:
        print(f"{RED}ERROR{END}:Access violation in rule")
        if not debug:
            print(rbac)
    elif debug:
        print(f"{GREEN}OK{END}:No access violation in rule")
    time.sleep(1)
    #-----
    # Remove role binding
    #----
    role_binding = user_data_resp["id"]
    url = "/v3/clusterRoleTemplateBindings/" + role_binding
    headers = { 'Authorization' : 'Basic %s' %  adminPass ,'Accept': 'application/json', 'Content-Type': 'application/json' }
    c.request('DELETE', url, user_create_json, headers=headers)
    #print(c.getresponse().read())
    time.sleep(1)
