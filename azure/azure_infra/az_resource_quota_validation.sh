#!/bin/bash
#
## Code starts here

#
# Resource quota validation for the Azure subscription
#
# The script requires the below variables values to be set prior to the execution


## Read the values from the user input.

read -p "Enter the client ID of the service principal created ie., appId  : " az_client_id
read -p "Enter the client secret of the service principal created ie., password  : " az_client_secret
read -p "Enter the tenantId  : " az_tenant_id
read -p "Enter the subscriptionId  : " az_subscription_id
read -p "Please enter the location for which the resource quota information is required (eg., eastus) : " az_location_name

echo -e "\n**************************************************"
echo " List of values entered"
echo -e "**************************************************\n"

echo -e "The client_id entered is : $az_client_id"
echo -e "The client secret entered is : $az_client_secret"
echo -e "The TENANT_ID value entered is: $az_tenant_id"
echo -e "The subscriptionId value entered is : $az_subscription_id"
echo -e "The location which has been selected is : $az_location_name"


### Getting the access_token using the curl command with the input values entered like client_id, client_secret and tenant_id

export az_access_token=$(curl -X POST -d "grant_type=client_credentials&client_id=${az_client_id}&client_secret=${az_client_secret}&resource=https%3A%2F%2Fmanagement.azure.com%2F" https://login.microsoftonline.com/$az_tenant_id/oauth2/token 2>/dev/null | python -c "import json,sys;obj=json.load(sys.stdin);print (obj['access_token']);")

echo -e "\n**************************************************"
echo " Executing curl command to get the usage data"
echo -e "**************************************************"

export vcpu_limit_output_file=az_vcpu_limit_$az_location_name_$(date -u +"%Y%m%d-%H%M%S").json

curl -X GET -H "Authorization: Bearer $az_access_token" -H "Content-Type:application/json" -H "Accept:application/json" https://management.azure.com/subscriptions/$az_subscription_id/providers/Microsoft.Compute/locations/$az_location_name/usages?api-version=2019-12-01 2>/dev/null >> $vcpu_limit_output_file

echo -e "\nThe vCPU usage limit is written into the file : $vcpu_limit_output_file "

echo -e "\n**************************************************"
echo " Executing curl command to get the Network data"
echo -e "**************************************************"

export network_limit_output_file=az_network_limit_$az_location_name_$(date -u +"%Y%m%d-%H%M%S").json

curl -X GET -H "Authorization: Bearer $az_access_token" -H "Content-Type:application/json" -H "Accept:application/json" https://management.azure.com/subscriptions/$az_subscription_id/providers/Microsoft.Network/locations/$az_location_name/usages?api-version=2020-05-01 2>/dev/null >> $network_limit_output_file

echo -e "\nThe Network usage limit is written into the file : $network_limit_output_file "

echo -e "\n****************************************************************************************************"
echo -e " Please find the default resource quota's required"
echo -e " As per the OCP4.5 documentation for azure, the minimum quota required are as follows:
****************************************************************************************************

Component                     Number of components required by default(minimum)
-----------------             ---------------------------------------------------
vCPU                          40
vNet                          1
Network Interfaces            6
Network security groups       2
Network load balancers        3
Public IP addresses           3
Private IP addresses          7

****************************************************************************************************\n"

## Setting up the variable for default limit of the resource.

az_vcpu_quota_required=40
az_vnet_quota_required=1
az_network_interface_quota_required=6
az_network_security_groups_quota_required=2
az_network_loadbalancer_quota_required=3
az_public_ip_address_quota_required=3

## Creating a function to find the available quota:

function calculate_available_resource_quota()
(
    quota_name=$1
    quota_string_pattern=$2
    quota_usage_output_json=$3
    quota_required=$4

    az_quota_limit_temp=$(grep -B6 -A2  "$quota_string_pattern" $quota_usage_output_json)
    az_limit=$(echo "$az_quota_limit_temp" | grep limit | awk '{gsub(/\"|\,/,"",$2)}1' | awk '{print $2}')
    az_current_value=$(echo "$az_quota_limit_temp" | grep currentValue | awk '{gsub(/\"|\,/,"",$2)}1' | awk '{print $2}')
    az_available_quota=$(echo $az_limit $az_current_value | awk '{ print $1 - $2 }')


    # az_available_$quota_name_quota=$az_available_quota
    if [ $az_available_quota -ge $quota_required  ]
    then
        condition_met="PASSED"
    else
         condition_met="FAILED"
    fi

    #echo -e "Resource name:$quota_name Required:$quota_required Available:$az_available_quota Conditional_check:$condition_met" | column -t -s' '
   printf  "%-40s |  %-40s |  %-40s |  %-40s" "$quota_name" "$quota_required" "$az_available_quota" "$condition_met"
   printf "\n"
)

## Calculating the available resource quota.:

### Function calling starts here:
echo -e " Summary of the resource quota details for the subscriptionId : $az_subscription_id "

echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

printf  "%-40s |  %-40s |  %-40s |  %-40s" "Resource_name" "Required" "Available" "Validation_check"

printf "\n"

printf "%-40s |  %-40s |  %-40s |  %-40s" "---------------------------" "---------------------------" "---------------------------" "---------------------------"

printf "\n"

calculate_available_resource_quota vCPU '"localizedValue": "Total Regional vCPUs"' $vcpu_limit_output_file $az_vcpu_quota_required

calculate_available_resource_quota vNet '"localizedValue": "Virtual Networks"' $network_limit_output_file $az_vnet_quota_required

calculate_available_resource_quota networkInterface '"localizedValue": "Network Interfaces"' $network_limit_output_file $az_network_interface_quota_required

calculate_available_resource_quota networkSecurityGroups '"localizedValue": "Network Security Groups"' $network_limit_output_file $az_network_security_groups_quota_required

calculate_available_resource_quota loadBalancers '"localizedValue": "Load Balancers"' $network_limit_output_file $az_network_loadbalancer_quota_required

calculate_available_resource_quota publicIpAddresses '"localizedValue": "Public IP Addresses"' $network_limit_output_file $az_public_ip_address_quota_required

echo -e "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"

## End of Script