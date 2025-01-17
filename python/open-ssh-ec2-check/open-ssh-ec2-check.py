# import modules
import boto3
import json

# connect to the aws ec2 client 
client = boto3.client("ec2")

# list of all the security group rules in the region and store the response in a variable 
# called "describe_security_group_rules_response"
describe_security_group_rules_response = client.describe_security_group_rules()

# get the value of the dictionary key "SecurityGroupRules", from the response 
# and store it in a variable called "get_security_group_rules"
get_security_group_rules = describe_security_group_rules_response.get("SecurityGroupRules")

# create an empty list and store it in a variable called "get_sg_id_with_ssh_rule_open_to_world"
get_sg_id_with_ssh_rule_open_to_world = []

# use for_loop to loop through the list "get_security_group_rules" and store the value of the 
# dictionary key "GroupId", in a variable called "security_group_id"
for item in get_security_group_rules:
    security_group_id = item.get("GroupId")

    # while looping through items in the "get_security_group_rules" list, if we find an item
    # that has FromPort = 22 and CidrIpv4 = 0.0.0.0/0, we will store the value of the dictionary 
    # key "GroupId" for that item in the list "get_sg_id_with_ssh_rule_open_to_world" 
    if item.get("FromPort") == 22 and item.get("CidrIpv4") == "0.0.0.0/0":
        get_sg_id_with_ssh_rule_open_to_world.append(security_group_id)

# list all ec2 instances and store the response in a variable called "describe_instances_response"
describe_instances_response = client.describe_instances()

# get the value of the dictionary key "Reservations", from the response and store 
# it in a variable called "get_reservations"
get_reservations = describe_instances_response.get("Reservations")

# create an empty list and store it in a variable called "get_instances"
get_instances = []

# use for_loop to loop through the list "get_reservations" and store the value 
# of the dictionary key "Instances", in a variable called "instances"
for item in get_reservations:
    instances = item.get("Instances")

    # while looping through the items in the "get_reservations" list, add the value 
    # of every "instances" found to the list "get_instances"
    get_instances.append(instances)

# get the value of instances that are running or stopped and exclude any instance that has been terminated
# create an empty list and store it in a variable called "get_only_running_and_stopped_instances"
get_only_running_and_stopped_instances = []

# use for_loop to loop through items in the first list "get_instences" 
for item in get_instances:
    # once in the first list, use another for_loop to loop through items in the second list "item"
    for item2 in item:
        # if value of the dictionary key "State", "Name", is "terminated" skip that item, else 
        # add the item to the list "get_only_running_and_stopped_instances"
        if item2.get("State").get("Name") == "terminated":
            pass
        else:
            get_only_running_and_stopped_instances.append(item2)  

# get the instance id of each ec2 instance and their associated security groups
# create an empty list and store it in a variable called "instance_info"
instance_info = []

# loop through items in the list "get_only_running_and_stopped_instances"
# get the value of the dictionary key "InstanceId" and store is in a variable 
# called "instance_id"
for item in get_only_running_and_stopped_instances:
    instance_id = item.get("InstanceId")

    # while is the for_loop, create an empty list and store it in a variable 
    # called "security_groups"
    security_groups = []
    
    # use another for_loop to loop through the value of dictionary key "SecurityGroups",
    # get the value for dictionary key "GroupId" and store it in a variable called "sg_group_id"
    for sg_group in item.get("SecurityGroups"):
        sg_group_id = sg_group.get("GroupId")

        # add all "sg_group_id" to the list "security_groups"
        security_groups.append(sg_group_id)

    # add the "instance_id" and "sg_group_id" of each items to the list "instance_info"
    instance_info.append([instance_id, security_groups])

# next we will check if any ec2 instance has a security group with ssh rule open to the world
# and we will add any instance that has security group with ssh rule open to the world to a new 
# list called "ec2_with_ssh_rule_open_to_world"
ec2_with_ssh_rule_open_to_world = []

for item in instance_info:
    instance_id = item[0]
    sg_group_id = item[1]

    for items in sg_group_id:
        if items in get_sg_id_with_ssh_rule_open_to_world:
            ec2_with_ssh_rule_open_to_world.append(instance_id)

try:
    terminate_instances_response = client.terminate_instances(InstanceIds=ec2_with_ssh_rule_open_to_world)
except:
    print("No instance has a security group rule with ssh open to the world")
