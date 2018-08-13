#!/bin/bash 

# Changes w.r.t. the official HCP Pipelines v.3.4.0:
# - It assumes data organization and file names follow BIDS convention
# - Separated folder for input (BIDS) and output (processed) images
# - It reads the Echo Spacing and PE direction from the .json files

get_batch_options() {
    local arguments=($@)

    unset command_line_specified_BIDS_study_folder
    unset command_line_specified_output_study_folder
    unset command_line_specified_subj_list
    unset command_line_specified_run_local

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --BIDSStudyFolder=*)
                command_line_specified_BIDS_study_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --OutputStudyFolder=*)
                command_line_specified_output_study_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --Subjlist=*)
                command_line_specified_subj_list=${argument/*=/""}
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

# Default options:
BIDSStudyFolder="${HOME}/projects/Pipelines_ExampleData" #Location of Subject folders (named by sub-subjectID)
Subjlist="100307" #Space delimited list of subject IDs
#EnvironmentScript="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script
EnvironmentScript="${HCPPIPEDIR}/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_BIDS_study_folder}" ]; then
    BIDSStudyFolder="${command_line_specified_BIDS_study_folder}"
fi
# Default option for Output folder:
OutputStudyFolder=$BIDSStudyFolder/Processed
if [ -n "${command_line_specified_output_study_folder}" ]; then
    OutputStudyFolder="${command_line_specified_output_study_folder}"
fi

if [ -n "${command_line_specified_subj_list}" ]; then
    Subjlist="${command_line_specified_subj_list}"
fi

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP) , gradunwarp (HCP version 1.0.2)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

#Set up pipeline environment variables and software
. ${EnvironmentScript}
source ${HCPPIPEDIR_Global}/get_params_from_json.shlib   #Get parameters from json file.


# Log the originating call
echo "$@"

#Assume that submission nodes have OPENMP enabled (needed for eddy - at least 8 cores suggested for HCP data)
#if [ X$SGE_ROOT != X ] ; then
    QUEUE="-q verylong.q"
#fi

PRINTCOM=""


########################################## INPUTS ########################################## 

#Scripts called by this script do assume they run on the outputs of the PreFreeSurfer Pipeline,
#which is a prerequisite for this pipeline

#Scripts called by this script do NOT assume anything about the form of the input names or paths.
#This batch script assumes BIDS data organization and naming convention, e.g.:

#	${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/dwi/sub-${Subject}[_ses-${session}]_acq-*[_run-<index>]_dwi.nii[.gz]

#It reads the scan settings from the *.json files: Dwelltime, FieldMap Delta TE (if using), and $PhaseEncodinglist

#You have the option of using either gradient echo field maps or spin echo field maps to 
#correct your structural images for readout distortion, or not to do this correction at all
#

#If using gradient distortion correction, use the coefficents from your scanner
#The HCP gradient distortion coefficents are only available through Siemens
#Gradient distortion in standard scanners like the Trio is much less than for the HCP Skyra.

######################################### DO WORK ##########################################

# Configuration common to all subjects, tasks and run numbers:
GradientDistortionCoeffs="${HCPPIPEDIR_Config}/coeff.grad"   # Default location of Coeffs file
# if it doesn't exist, skip it:
if [ ! -f ${GradientDistortionCoeffs} ]; then
  GradientDistortionCoeffs="NONE" # Set to NONE to skip gradient distortion correction
fi

for Subject in ${Subjlist[*]} ; do
  echo ""
  echo ""
  echo "########################      $Subject      ########################"

  # Build the list of diffusion images:
  PosData="";  PosCount=0;
  NegData="";  NEgCount=0;
  
  # Check if the data for this subject is organized in sessions:
  sesList=( $(ls ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
  # if session folders are found, add a "session string" to the directory structure
  #   and file names:
  if [ $? -eq 0 ]; then
      sesString="_ses-*"
  else
      # the "session string" will be empty:
      sesString=""
  fi

  # Get all diffusion-weighted runs, getting the b-value=0 first (this is important, because otherwise
  #    the script doesn't send both b-value=0 for topup processing)
  DWISeries="$(ls ${BIDSStudyFolder}/sub-${Subject}/${sesString#_}/dwi/sub-${Subject}${sesString}_acq-b0*_dwi.nii*) \
  	     $(ls ${BIDSStudyFolder}/sub-${Subject}/${sesString#_}/dwi/sub-${Subject}${sesString}_acq-*vols*_dwi.nii*)"
  for dwiSeries in ${DWISeries}; do
      echo ""
      echo "       ${dwiSeries}"

      ##   Get the Phase Encoding direction from the json file:   ##
      #UnwarpDir=`echo $PhaseEncodinglist | cut -d " " -f $i`
      PEDirIJK=`read_header_param PhaseEncodingDirection ${dwiSeries%.nii*}.json`
      PEDirIJK="${PEDirIJK%\"}"   # remove trailing quote (")
      PEDirIJK="${PEDirIJK#\"}"   # remove leading quote (")
      # The HCP Pipelines want 1 for R-L and 2 for A-P, rather than i/j/k:
      if   [ ${PEDirIJK%-} = "i"  ]; then PEdir=1;
      elif [ ${PEDirIJK%-} = "j"  ]; then PEdir=2;
      else echo "Incompatible PE direction"; exit;
      fi

      # Check whether positive or negative and append to the corresponding list:
      if   [ ${PEDirIJK%-} = ${PEDirIJK} ]; then
	  PosData="${PosData}@${dwiSeries}"
	  PosCount=$(( $PosCount + 1 ))
      else
	  NegData="${NegData}@${dwiSeries}"
	  NegCount=$(( $NegCount + 1 ))
      fi
  done

  # If corresponding series is missing (e.g. 2 RL series and 1 LR) use EMPTY:
  while [ $PosCount -lt $NegCount ]; do
      PosData="${PosData}@EMPTY"
      PosCount=$(( $PosCount + 1 ))
  done
  while [ $NegCount -lt $PosCount ]; do
      NegData="${NegData}@EMPTY"
      NegCount=$(( $NegCount + 1 ))
  done
  
  # remove the leading "@"
  PosData=${PosData#@}
  NegData=${NegData#@}

  #Scan Setings
  EchoSpacingSec=`read_header_param EffectiveEchoSpacing ${dwiSeries%.nii*}.json`    # It'd better be the same for _all_ dwiSeries...
  EchoSpacing=`echo "scale=6; ${EchoSpacingSec}*1000" | bc -l`      # "DiffPreprocPipeline" wants the echo spacing in ms.

  if [ -n "${command_line_specified_run_local}" ] ; then
      echo "About to run ${HCPPIPEDIR}/DiffusionPreprocessing/DiffPreprocPipeline.sh"
      queuing_command=""
  else
      echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/DiffusionPreprocessing/DiffPreprocPipeline.sh"
      queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
  fi

  ${queuing_command} ${HCPPIPEDIR}/DiffusionPreprocessing/DiffPreprocPipeline.sh \
      --posData="${PosData}" --negData="${NegData}" \
      --path="${OutputStudyFolder}" --subject="${Subject}" \
      --echospacing="${EchoSpacing}" --PEdir=${PEdir} \
      --gdcoeffs="${GradientDistortionCoeffs}" \
      --printcom=$PRINTCOM

done

