# PKS Autoscaler

**NOT FOR PRODUCTION USE**

This project implements a workflow, within the OpsManager enviornment, to autoscale K8s clusters that have been deployed using Pivotal COntainer Services (PKS). The workflow relies on the BOSH's abvility to capture compute level statistics of the worker VMs, that constitue the worker nodes for the K8s clusters. 

## Features

* Runs within the OpsManager enviornment, leveraging the ability to consume BOSH and PKS APIs seamlessly. 
* Ability to run both as interactivly or as a scheduled job. 
* Can resize clusters based on both the CPU and memory parameters. 
* Ability to exclude clusters from auto-scaling, on the fly(WIP) to honor ongoing cluster maintainance. 
* Ability to exclude memory stats during auto-scaling (WIP).
* Ability to stop entire script execution on the fly, to honor enviornment maintainance.
* Honors the PKS plan's min and max node sizing and operates within those boundaries. 
* No external stats (e.g. Prometheus) required to achive auto-scaling.
* No requirements to store/expose enviornment credentials. All credentials are requested and consumed using those stored in CredHub. 
* Ability to control high watermarks for memory and CPU on the fly. 
* Shrinks down unused compute, based on low CPU usage watermark.

## Requirements

* SSH Access to Opsmanager VM.
* OM CLI (can be setup with the prerequisite script)
* JQ, Python YQ package, BC (can be setup with the the prerequisite script) 
* PKS CLI (may need to be setup **manually** on the Opsmanager server at the following location `/usr/local/bin/pks`)
* Configuration file `pks-autoscaler.config`. Sample provided. Modify as per your requirements.
 
 ## Setup

* Clone this repo.
* Modify the `pks-autoscaler.config` file.
* Modify the values of following entries in the script 
`OM_USERNAME="om_user"` and `OM_PASSWORD="om_password"`. The value should corrospond to the info of the login id execuiting the script. 
* Run the `pks-autoscaler-preq.sh` script to setup required binaries. 
* Make sure `pks` cli is installed.
* Schedule the `pks-autoscaler-schduler.sh` or execute the `pks-autoscaler.sh` and enjoy!!!