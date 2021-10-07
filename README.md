# ecs-insight
Simple bash script to provide info about an ECS cluster, services, task definitions and containers

The plan is to implement the functionality/features into the existing tool [cloudman](https://github.com/dutchcoders/cloudman) to support both EC2 and ECS.

# Requirements
This tool cannot function without the aws-cli version 2 and the ecs-cli.  
To install the aws-cli, checkout the [AWS aws-cli install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html).  
To install the ecs-cli, checkout the [AWS ecs-cli install guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_CLI_installation.html).  

The shell's current AWS profile will be used to perform all `aws` and `ecs-cli`. If you need to change profile, checkout the [AWS aws-cli configure profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) page.

# How to use


## List all services for a cluster
```bash
bash ecs-insight.sh {cluster-name}
```
Will output all service arns for the provided cluster as well as all containers inside the cluster with a `--desired-status RUNNING`.

## List service specific info and hints in a cluster
```bash
bash ecs-insight.sh {cluster-name} {service-search-name}
```
Will output the service arn, task definition arn, the containers related to the service and command line hint to:
* show the task definition
* start a ssm session in the container (equivalent of the `docker exec` command)

If any failures occured that cause the task to fail, will also be displayed.  

## Tail logs all containers in a service 
```bash
bash ecs-insight.sh {cluster-name} {service-search-name} --logs
```
Will output all of the items of the previous command, and adds:
* tailing logs for all the containers defined in the task definition for the service

## Tail logs of a single container in a service
```bash
bash ecs-insight.sh {cluster-name} {service-search-name} --single
```
Same output of the previous command, except will show logs of a single container considered as the 'main' app for the service
