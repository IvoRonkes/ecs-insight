#!/bin/bash

blue=$(tput setaf 4)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 6)

has_logs_flag="false"
single_container="false"

if [[ $* == *--logs* ]]; then
    has_logs_flag="true"
fi

if [[ $* == *--single* ]]; then
    single_container="true"
fi

cluster=""
search_service=""

# set cluster and service search term
arg_count=1
echo -n "$blue";
for arg do
    if [[ $arg == *--logs* ]] || [[ $arg == *--single* ]]; then
        continue
    fi

    if [[ $arg_count -eq 1 ]]; then
        cluster=$arg
        printf "Checking ECS cluster: '%s'\n" "$arg"
    fi

    if [[ $arg_count -eq 2 ]]; then
        search_service=$arg
        printf "Checking for service '%s'\n" "$arg"
    fi
    arg_count=$((arg_count+1))
done
echo -n "$normal";

if [[ $cluster == "" ]]; then
    echo "Provide cluster name, service and optional flags '--logs' to output container logs for service and '--single' to display logs for only the 'main' process"
    exit 1
fi

if [[ $search_service == "" ]]; then
    echo -n "$yellow";
    echo "Warning, only 1 argument provided, listing services for cluster '$cluster'"
    echo -n "$normal";
fi

# Display found settings
echo -n "$blue";
printf "Logs flag for tailing logs is set: %s\n" "$has_logs_flag" 
printf "Display only single container logs (if service name can be matched to a single container, omitting x-ray and envoy containers): %s\n" "$single_container" 
echo -n "$normal";

# all containers
ps_out=$(ecs-cli ps --cluster "$cluster" --desired-status RUNNING)

# all or matched services
services=$(aws ecs list-services --cluster "$cluster"|jq '.serviceArns|.[]' -r |grep "$search_service")
lines=$(wc -l <<<"$services")

if [[ $lines -eq 0 ]]; then
    printf "No services found!"
    exit 1
fi

if [[ $lines -gt 1 ]]; then
    #echo "More than 1 service found"
    if [[ "$search_service" != "" ]]; then
        echo -n "$yellow";
        printf "Warning, service provided but multiple services found for service %s\n" "$search_service"
        echo -n "$normal";
    fi

    # containers header
    echo -n "$blue";
    printf "Services found:\n"
    echo -n "$cyan"
    printf "%s\n" "$services"

    # show all containers
    echo -n "$blue";
    printf "\nAll containers in cluster %s:\n" "$cluster"
    printf "%s\n" "$ps_out"
    echo -n "$normal";
    exit 1
fi

# single line found so $services should be a single service

# show service arn
echo -n "$blue";
printf "Service %s arn: \n" "$2" 
echo -n "$normal";
printf "%s\n" "$services"

# get task_definition
task_definition=$(aws ecs describe-services --services "$services" --cluster "$cluster"|jq '.services|.[]|.taskDefinition' -r)
echo -n "$blue";
printf "\nTask definition for service %s:\n" "$2"
echo -n "$normal";
printf "%s\n" "$task_definition"
echo -n "$normal";

# extract task definition name
task_def_name=$(echo "$task_definition"|sed "s/.*\///")

if [[ $task_def_name == "" ]]; then
    printf "Unable to parse task definition arn, exiting"
    exit 1
fi

# list containers for service
echo -n "$blue";
printf "\nContainers for task definition:\n" 
echo -n "$normal";

# containers header
printf "%s\n" "$(echo "$ps_out"|head -n1)"

# print only service relevant containers by filtering greedy on the service name, assuming the task defintion name resembles the service name
IFS=$'\n'       # make newlines the only separator

container_match=0
for process in $ps_out
do
    # filter only container name
    ct=$(echo "$process"|grep "$task_def_name"|grep "$search_service"|head -n1|cut -d' ' -f1)
    if [[ "$ct" == "" ]];then
        continue
    fi

    # ignore envoy and x-ray when '--single' is set
    if [[ $single_container == "true" ]]; then
        if [[ "$ct" == *envoy* ]] || [[ "$ct" == *xray* ]] || [[ "$ct" == *x-ray* ]]; then
            #printf "Skipping envoy/x-ray: %s\n" "$ct"
            continue
        fi
    fi

    echo -n "$cyan"
    printf "%s\n" "$(echo "$process"|grep "$task_def_name")"
    echo -n "$normal";

    # split cluster/container_id/container_name
    ct_id=$(echo "$ct"|cut -d '/' -f2)
    ct_name=$(echo "$ct"|cut -d '/' -f3)
    if [[ $ct_name == *${search_service}* ]]; then
        container_match=1
        break
    fi
done

task_description=$(aws ecs describe-tasks --cluster "$cluster" --tasks "$ct_id"|jq)

# if failures are present, show
if [[ $(jq '.failures|length' <<<"$task_description") -gt 0 ]]; then
    echo "Found failures:"
    jq '.failures' <<<"$task_description"
fi

# hint show task definition
echo -n "$blue"
printf "\nTo see the task definition, do:\n"
echo -n "$cyan"
echo "'aws ecs describe-task-definition --task-definition $task_def_name|jq'"
echo -n "$normal"

# extract name with runtimeId for every container
b64=$(jq '.tasks[0].containers|.[]|{name: .name, runtimeId: .runtimeId}|@base64' -r <<<"$task_description")

# hint task definition and ssm start-session commands
for row in $b64; do
    _jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
    }
   cname=$(_jq '.name')
   rtID=$(_jq '.runtimeId')
   #printf "Container %s with runtimeId %s\n" "$cname" "$rtID"
   echo -n "$blue"
   printf "\nTo ssm into the container %s, do:\n" "$cname"
   echo -n "$cyan"
   printf "'aws ssm start-session --target ecs:%s_%s_%s'\n" "$cluster" "$(cut -d '-' -f1 <<<"$rtID")" "$rtID"
done
echo -n "$normal"

# tail container logs
if  [[ $container_match -eq 0 ]]; then
    echo -n "$yellow"
    printf "WARNING, no container match found for service %s\n" "$search_service"
    echo -n "$normal"
else
    echo -n "$blue"
    printf "Using container with ID: %s, name: %s to tail logs\n" "$ct_id" "$ct_name"
    echo -n "$normal"
fi

# hint tail container logs
echo -n "$blue"
printf "\nTo see container logs, do:\n"
echo -n "$cyan"
echo "ecs-cli logs --cluster $cluster --follow --task-id $ct_id| sed '/^[[:space:]]*$/d'"
echo -n "$blue"
printf "\nOr for single container:\n"
echo -n "$cyan"
echo "ecs-cli logs --cluster $cluster --container-name=$ct_name --follow --task-id $ct_id| sed '/^[[:space:]]*$/d'"
echo -n "$normal"

# tail logs when '--logs' flag is set
if [[ $single_container == "true" ]] && [[ $ct_name != "" ]]; then
    ecs-cli logs --cluster "$cluster" --container-name="$ct_name" --follow --task-id "$ct_id"| sed '/^[[:space:]]*$/d'
elif [[ $has_logs_flag == "true" ]]; then
    ecs-cli logs --cluster "$cluster" --follow --task-id "$ct_id"| sed '/^[[:space:]]*$/d'
fi
