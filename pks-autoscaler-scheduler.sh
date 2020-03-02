#!/bin/bash
export PATH=/usr/local/bin/:$PATH
cd "$(dirname "$0")";

OM_USERNAME="om_user"
OM_PASSWORD="om_password"
OM_TARGET="localhost"
PKS_USERNAME="admin"

PKS_API_EP=""
BOSH_PKS_DEPLOYMENT=""
BOSH_PKS_CLUSTERS=""
TEMPFILE=`mktemp`

calcavg()
{
	count="0"
	sum="0"
	for i in $1
	do
		sum+="+${i}"
		count+="+1"
	done
	avg=`echo "scale=2; ($sum)/($count)" |bc`
	echo $avg
}

if [[ -f pks-autoscaler.config ]]
then
	source pks-autoscaler.config
else
	exit 1
fi

if [[ ${ENABLE_SCRIPT} -eq 1 ]]
then
    om -k -t ${OM_TARGET} -u ${OM_USERNAME} -p ${OM_PASSWORD} bosh-env > $TEMPFILE
   	source $TEMPFILE
   	om -k -t localhost -u ${OM_USERNAME} -p ${OM_PASSWORD} deployed-manifest -p pivotal-container-service |yq . > /tmp/pks_manifest.yaml
   	PKS_API=`cat /tmp/pks_manifest.yaml |jq -r '.instance_groups[].properties.service_catalog.global_properties.pks_api_fqdn'`
   	PKS_PASSWORD=`om  -k -t localhost -u ${OM_USERNAME} -p ${OM_PASSWORD} credentials --product-name pivotal-container-service -c .properties.uaa_admin_password -t json|jq -r '.secret'`

   	if [ -z ${PKS_API} ]
 	then
   		echo "Could not find a valid PKS installation. Exiting..." | tee -a /tmp/pksresize.log
   	 	exit 1
   	else
	    echo "Found a valid PKS install. Using EP ${PKS_API}..."| tee -a /tmp/pksresize.log
   	fi
   	pks login -a ${PKS_API} -u ${PKS_USERNAME} -p ${PKS_PASSWORD} -k

   	BOSH_PKS_DEPLOYMENT=`bosh deployments --json |jq -r '.Tables[].Rows[] | select( .name | contains("pivotal-container-service")).name'`
   	if [ -z ${BOSH_PKS_DEPLOYMENT} ]
   	then
   		echo "Could not find a valid BOSH PKS deployment. Exiting..."| tee -a /tmp/pksresize.log
   		exit 1
   	else
   		echo "Found a valid BOSH PKS deployment. Using deployment ${BOSH_PKS_DEPLOYMENT}..."| tee -a /tmp/pksresize.log
   	fi

   	BOSH_PKS_CLUSTERS=`bosh deployments --json |jq -r --arg BOSH_PKS_DEPLOYMENT "$BOSH_PKS_DEPLOYMENT" '.Tables[].Rows[] | select( .team_s | contains($BOSH_PKS_DEPLOYMENT)).name'`
   	for BOSH_PKS_CLUSTER in ${BOSH_PKS_CLUSTERS}
   	do
   		echo "============================================================================================="| tee -a /tmp/pksresize.log
   		echo "Calculating avg. stats for PKS Cluster ${BOSH_PKS_CLUSTER}..."| tee -a /tmp/pksresize.log
   		WORKER_STATS=`bosh vms --vitals -d ${BOSH_PKS_CLUSTER} --json |jq -r '.Tables[].Rows[] | select( .instance | contains("worker"))'`
   		cpu_sys=`echo ${WORKER_STATS}|jq -r '.cpu_sys|rtrimstr("%")'`
   		cpu_user=`echo ${WORKER_STATS}|jq -r '.cpu_user|rtrimstr("%")'`
   		cpu_wait=`echo ${WORKER_STATS}|jq -r '.cpu_wait|rtrimstr("%")'`
   		memory_usage=`echo ${WORKER_STATS}|jq -r '.memory_usage|split("%")[0]'`
   		avg_cpu_sys=`calcavg "${cpu_sys[@]}"`
   		avg_cpu_user=`calcavg "${cpu_user[@]}"`
   		avg_cpu_wait=`calcavg "${cpu_wait[@]}"`
   		avg_memory_usage=`calcavg "${memory_usage[@]}"`
   		avg_total_cpu=`echo "($avg_cpu_sys+$avg_cpu_user+$avg_cpu_wait)/1"|bc`
   		avg_mem_usage=`echo "($avg_memory_usage)/1"|bc`

   		echo "Gathering PKS Cluster details..."| tee -a /tmp/pksresize.log
   		PKS_CLUSTER_UUID=`echo ${BOSH_PKS_CLUSTER}|cut -d_ -f2`
   		pks_cluster=`pks clusters --json |jq -r --arg PKS_CLUSTER_UUID "$PKS_CLUSTER_UUID" '.[] | select( .uuid == $PKS_CLUSTER_UUID)'`
   		cluster_name=`echo ${pks_cluster}| jq -r '.name'`
   		cluster_status=`echo ${pks_cluster}| jq -r '.last_action_state'`
   		cluster_node_count=`echo ${pks_cluster}|jq -r '.parameters.kubernetes_worker_instances'`
   		cluster_plan=`echo ${pks_cluster}| jq -r '.plan_name'`
   		max_worker_count=`cat /tmp/pks_manifest.yaml |jq -r --arg cluster_plan "$cluster_plan" '.instance_groups[].properties.service_catalog.plans[]| select (.name == $cluster_plan)|.metadata.max_worker_instances'`
   		min_worker_count=`cat /tmp/pks_manifest.yaml |jq -r --arg cluster_plan "$cluster_plan" '.instance_groups[].properties.service_catalog.plans[]| select (.name == $cluster_plan)|.metadata.worker_instances'`

   		echo "${cluster_name}:- [ PLAN: ${cluster_plan}, MAX_WORKERS: ${max_worker_count}, MIN_WORKERS: ${min_worker_count}, CURRENT_WORKERS: ${cluster_node_count}, AVG_TOTAL_CPU: ${avg_total_cpu}%, AVG_MEMORY: ${avg_mem_usage}%. ]"| tee -a /tmp/pksresize.log

   		if [[ ${avg_total_cpu} -lt ${MIN_TOTAL_CPU} ]] && [[ ${avg_mem_usage} -lt ${MAX_TOTAL_MEM} ]]
   		then
   			echo "${cluster_name} a candidate for node reduction. Avg total cpu usage ${avg_total_cpu}% < MIN ${MIN_TOTAL_CPU}%..."| tee -a /tmp/pksresize.log
   			if [[ ${cluster_status} == "succeeded" ]]
   			then
   				if [ ${cluster_node_count} -le ${min_worker_count} ]
   				then
   					echo "${cluster_name} already has minimum node count. Cannot shrink further..."| tee -a /tmp/pksresize.log
   				else
   					echo "${cluster_name} node count ready to be reduced by one..."| tee -a /tmp/pksresize.log
    				newnodecount=`echo "${cluster_node_count}-1"|bc`
    	 			pks resize ${cluster_name} --non-interactive --num-nodes ${newnodecount}
   				fi
   			else
   				echo "${cluster_name} last action not in successful state. Will wait before taking further action..."| tee -a /tmp/pksresize.log
   			fi
   		fi

   		if [[ ${avg_total_cpu} -gt ${MAX_TOTAL_CPU} ]] || [[ ${avg_mem_usage} -gt ${MAX_TOTAL_MEM} ]]
   		then
   			echo "${cluster_name} a candidate for node addition. Avg total CPU usage: ${avg_total_cpu}% / Avg. Mem usage: ${avg_mem_usage}%..."| tee -a /tmp/pksresize.log
   			if [[ ${cluster_status} == "succeeded" ]]
   			then
   				if [ ${cluster_node_count} -ge ${max_worker_count} ]
   				then
   					echo "${cluster_name} already has maximum node count. Cannot grow further..."| tee -a /tmp/pksresize.log
   				else
   					echo "${cluster_name} node count ready to be increased by one..."| tee -a /tmp/pksresize.log
   					newnodecount=`echo "(${cluster_node_count}+1)/1"|bc`
   					pks resize ${cluster_name} --non-interactive --num-nodes ${newnodecount}
   				fi
   			else
   				echo "${cluster_name} last action not in successful state. Will wait before taking further action..."| tee -a /tmp/pksresize.log
   			fi
   		fi
   		echo
   	done

   rm -f $TEMPFILE
   rm -f /tmp/pks_manifest.yaml
fi
#  echo "Sleeping for ${SCRIPT_FREQ_MIN} minutes..."| tee -a /tmp/pksresize.log
#  sleep ${SCRIPT_FREQ_MIN}m