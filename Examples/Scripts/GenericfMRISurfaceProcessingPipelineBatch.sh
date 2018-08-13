#!/bin/bash 

# TO-DO:
# - Give the option to run it on all functional runs (tasks and rest)

get_batch_options() {
    local arguments=($@)

    unset command_line_specified_study_folder
    unset command_line_specified_subj_list
    unset command_line_task_list
    unset command_line_specified_run_local

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --StudyFolder=*)
                command_line_specified_study_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --Subjlist=*)
                command_line_specified_subj_list=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --Tasklist=*)
                command_line_specified_task_list=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --runlocal)
                command_line_specified_run_local="TRUE"
                index=$(( index + 1 ))
                ;;
        esac
    done
}

#####     #####     Main     #####     #####

get_batch_options $@

StudyFolder="${HOME}/projects/Pipelines_ExampleData" #Location of Subject folders (named by subjectID)
Subjlist="100307" #Space delimited list of subject IDs
Tasklist="face"   #Comma-separated list of tasks

#EnvironmentScript="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script
EnvironmentScript="${HCPPIPEDIR}/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_study_folder}" ]; then
    StudyFolder="${command_line_specified_study_folder}"
fi
if [ -n "${command_line_specified_subj_list}" ]; then
    # Split the different comma-separated subjects:
    Subjlist=(${command_line_specified_subj_list//,/ })
fi
if [ -n "${command_line_specified_subj_list}" ]; then
    # Split the different comma-separated subjects:
    Subjlist=(${command_line_specified_subj_list//,/ })
fi
if [ -n "${command_line_specified_task_list}" ]; then
    # Split the different comma-separated tasks:
    Tasklist=(${command_line_specified_task_list//,/ })
fi

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP) , gradunwarp (HCP version 1.0.2)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

#Set up pipeline environment variables and software
. ${EnvironmentScript}
source ${HCPPIPEDIR_Global}/get_params_from_json.shlib   #Get parameters from json file.

# Log the originating call
echo "$@"

#if [ X$SGE_ROOT != X ] ; then
    QUEUE="-q long.q"
#fi

PRINTCOM=""
#PRINTCOM="echo"
#QUEUE="-q veryshort.q"

########################################## INPUTS ########################################## 

#Scripts called by this script do assume they run on the outputs of the FreeSurfer Pipeline

######################################### DO WORK ##########################################


# Configuration common to all subjects, tasks and run numbers:

# TO-DO: Try to read this from the corresponding PostFreeSurfer folder:
LowResMesh="32" #Needs to match what is in PostFreeSurfer, 32 is on average 2mm spacing between the vertices on the midthickness
SmoothingFWHM="2" #Recommended to be roughly the grayordinates spacing, i.e 2mm on HCP data
# TO-DO: Try to read this from the corresponding PostFreeSurfer folder:
GrayordinatesResolution="2" #Needs to match what is in PostFreeSurfer. 2mm gives the HCP standard grayordinates space with 91282 grayordinates.  Can be different from the FinalfMRIResolution (e.g. in the case of HCP 7T data at 1.6mm)
# RegName="MSMSulc" #MSMSulc is recommended, if binary is not available use FS (FreeSurfer)
RegName="FS"


for Subject in ${Subjlist[*]} ; do
  echo ""
  echo ""
  echo "########################      $Subject      ########################"

  for fMRIName in ${Tasklist[*]} ; do
    echo ""
    echo "###     ${fMRIName}     ###"

    # TO-DO: handle the multi-session subjects
    for acqRun in `ls ${StudyFolder}/sub-${Subject}/${fMRIName}/`; do
	if [ -n "${command_line_specified_run_local}" ] ; then
            echo "About to run ${HCPPIPEDIR}/fMRISurface/GenericfMRISurfaceProcessingPipeline.sh"
            queuing_command=""
	else
            echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/fMRISurface/GenericfMRISurfaceProcessingPipeline.sh"
            queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
	fi

	${queuing_command} ${HCPPIPEDIR}/fMRISurface/GenericfMRISurfaceProcessingPipeline.sh \
	  --path=$StudyFolder \
	  --subject=$Subject \
	  --fmriname=$fMRIName \
	  --acqRun=$acqRun \
	  --lowresmesh=$LowResMesh \
	  --smoothingFWHM=$SmoothingFWHM \
	  --grayordinatesres=$GrayordinatesResolution \
	  --regname=$RegName

    # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

        echo "set -- --path=$StudyFolder \
          --subject=$Subject \
          --fmriname=$fMRIName \
          --acqRun=$acqRun \
          --lowresmesh=$LowResMesh \
          --smoothingFWHM=$SmoothingFWHM \
          --grayordinatesres=$GrayordinatesResolution \
          --regname=$RegName"

        echo ". ${EnvironmentScript}"

	echo ""
	echo "----------------------------------------------"
	echo ""
    done     # loop through run number
	
    echo ""
  done       # loop through task name
  echo ""
done         # loop through subjects


