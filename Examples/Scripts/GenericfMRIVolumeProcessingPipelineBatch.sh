#!/bin/bash 

# TO-DO:
# - Give the option to run it on all functional runs (tasks and rest)
# - Handle the case of FIELDMAP B0 correction
# - Check the "intended for" field for the SE distortion map images

get_batch_options() {
    local arguments=($@)

    unset command_line_specified_BIDS_study_folder
    unset command_line_specified_output_study_folder
    unset command_line_specified_subj_list
    unset command_line_task_list
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
            --Tasklist=*)
                command_line_specified_task_list=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --runlocal)
                command_line_specified_run_local="TRUE"
                index=$(( index + 1 ))
                ;;
	    *)
		echo ""
		echo "ERROR: Unrecognized Option: ${argument}"
		echo ""
		exit 1
		;;
        esac
    done
}

#####     #####     Main     #####     #####

get_batch_options $@

# Default options:
BIDSStudyFolder="${HOME}/projects/Pipelines_ExampleData" #Location of Subject folders (named by sub-subjectID)
Subjlist="100307" #Comma-separated list of subject IDs
Tasklist="face"   #Comma-separated list of tasks

#EnvironmentScript="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script
EnvironmentScript="${HCPPIPEDIR}/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_BIDS_study_folder}" ]; then
    BIDSStudyFolder="${command_line_specified_BIDS_study_folder}"
fi
# Default option for Output folder:
OutputStudyFolder=$BIDSStudyFolder/derivatives/Processed
if [ -n "${command_line_specified_output_study_folder}" ]; then
    OutputStudyFolder="${command_line_specified_output_study_folder}"
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
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP) , gradunwarp (HCP version 1.0.1)
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

#Scripts called by this script do NOT assume anything about the form of the input names or paths.
#This batch script assumes BIDS data organization and naming convention, e.g.:

#	${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/func/sub-${Subject}[_ses-${session}]_task-*[_run-<index>]_bold.nii[.gz]

#       ${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/fmap/sub-${Subject}[_ses-${session}]_acq-fMRI_dir-AP_[run-<index>]_epi.nii[.gz]
#       ${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/fmap/sub-${Subject}[_ses-${session}]_acq-fMRI_dir-PA_[run-<index>]_epi.nii[.gz]


#It reads the scan settings from the *.json files: Dwelltime, FieldMap Delta TE (if using), and $PhaseEncodinglist

#If using gradient distortion correction, use the coefficents from your scanner
#The HCP gradient distortion coefficents are only available through Siemens
#Gradient distortion in standard scanners like the Trio/Prisma is much less than for the HCP Skyra.

#To get accurate EPI distortion correction with TOPUP, the flags in PhaseEncodinglist must match the phase encoding
#direction of the EPI scan, and you must have used the correct images in SpinEchoPhaseEncodeNegative and Positive
#variables.  If the distortion is twice as bad as in the original images, flip either the order of the spin echo
#images or reverse the phase encoding list flag.  The pipeline expects you to have used the same phase encoding
#axis in the fMRI data as in the spin echo field map data (x/-x or y/-y).  

######################################### DO WORK ##########################################


# Configuration common to all subjects, tasks and run numbers:

DistortionCorrection="TOPUP" #FIELDMAP or TOPUP, distortion correction is required for accurate processing
echo "user chose Topup B0 correction"

MagnitudeInputName="NONE" #Expects 4D Magnitude volume with two 3D timepoints, set to NONE if using TOPUP
PhaseInputName="NONE" #Expects a 3D Phase volume, set to NONE if using TOPUP
DeltaTE="NONE" #2.46ms for 3T, 1.02ms for 7T, set to NONE if using TOPUP
GradientDistortionCoeffs="${HCPPIPEDIR_Config}/coeff.grad"   # Default location of Coeffs file
# if it doesn't exist, skip it:
if [ ! -f ${GradientDistortionCoeffs} ]; then
  GradientDistortionCoeffs="NONE" # Set to NONE to skip gradient distortion correction
fi
TopUpConfig="${HCPPIPEDIR_Config}/b02b0.cnf" #Topup config if using TOPUP, set to NONE if using regular FIELDMAP

for Subject in ${Subjlist[*]} ; do
  echo ""
  echo ""
  echo "########################      $Subject      ########################"

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

  for fMRIName in ${Tasklist[*]} ; do
    echo ""
    echo "###     ${fMRIName}     ###"

    # Loop through all functional runs corresponding to this task:
    for fMRITimeSeries in `ls ${BIDSStudyFolder}/sub-${Subject}/${sesString#_}/func/sub-${Subject}${sesString}_task-${fMRIName}*_bold.nii*`; do
	echo ""
	echo "       ${fMRITimeSeries}"
	## to distinguish between different runs and acquisitions:
	#acqRun=${fMRITimeSeries##*_task-${fMRIName}_}
	#acqRun=${acqRun%_bold.nii*}

	# Final fMRI Resolution:
	#Target final resolution of fMRI data. 2mm is recommended for 3T HCP data, 1.6mm for 7T HCP data (i.e. should match acquired resolution).  Use 2.0 or 1.0 to avoid standard FSL templates
	#FinalFMRIResolution="2"
	FinalFMRIResolution=`${FSLDIR}/bin/fslval ${fMRITimeSeries} pixdim1`
	FinalFMRIResolution=`echo "scale=2; ${FinalFMRIResolution}/1" | bc -l | sed 's!\.0*$!!'`

	##   Get the Phase Encoding direction from the json file:   ##
	#UnwarpDir=`echo $PhaseEncodinglist | cut -d " " -f $i`
	PEDir=`read_header_param PhaseEncodingDirection ${fMRITimeSeries%.nii*}.json`
	PEDir="${PEDir%\"}"   # remove trailing quote (")
	PEDir="${PEDir#\"}"   # remove leading quote (")
	# The HCP Pipelines want x/y/z, rather than i/j/k:
	if   [ $PEDir = "i"  ]; then UnwarpDir="x";
	elif [ $PEDir = "i-" ]; then UnwarpDir="x-";
	elif [ $PEDir = "j"  ]; then UnwarpDir="y";
	elif [ $PEDir = "j-" ]; then UnwarpDir="y-";
	elif [ $PEDir = "k"  ]; then UnwarpDir="z";
	elif [ $PEDir = "k-" ]; then UnwarpDir="z-";
	fi

	#A single band reference image (SBRef) is recommended if using multiband, set to NONE if you want to use the first volume of the timeseries for motion correction:
	fMRISBRef="${fMRITimeSeries%_bold.nii*}_sbref.nii*"
	if [ ! -f $fMRISBRef ]; then
	    fMRISBRef="NONE"
	else
	    fMRISBRef=`ls $fMRISBRef`
	fi

	##   Settings for the B0 disortion correction   ##

	DwellTime=`get_DwellTime ${fMRITimeSeries%.nii*}.json` # Effective Echo Spacing or Dwelltime of fMRI image, set to NONE if not used.

	# For the spin-echo distortion maps, make sure you only look for them in the same session.
	# To do that, get the portion of the "fMRITimeSeries" up to "/func/":
	SpinEchoPhaseEncodeNegative=`ls ${fMRITimeSeries%/func/*}/fmap/sub-${Subject}${sesString}_acq-fMRI_*dir-AP*.nii*`
	SpinEchoPhaseEncodePositive=`ls ${fMRITimeSeries%/func/*}/fmap/sub-${Subject}${sesString}_acq-fMRI_*dir-PA*.nii*`

	# TO-DO: if there is more than one, pick which one (maybe the one closest in time?)
	# For now, just keep the first one:
	SpinEchoPhaseEncodeNegative=`ls ${SpinEchoPhaseEncodeNegative%%.nii*}.nii*`
	SpinEchoPhaseEncodePositive=`ls ${SpinEchoPhaseEncodePositive%%.nii*}.nii*`
	SE_RO_Time=`read_header_param TotalReadoutTime ${SpinEchoPhaseEncodeNegative%.nii*}.json`

	if [ $fMRISBRef = "NONE" ] ; then
	    SBRef_RO_Time=`read_header_param TotalReadoutTime ${fMRITimeSeries%.nii*}.json`
	else
	    SBRef_RO_Time=`read_header_param TotalReadoutTime ${fMRISBRef%.nii*}.json`
	fi

	if [ -n "${command_line_specified_run_local}" ] ; then
            echo "About to run ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh"
            queuing_command=""
	else
            echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh"
            queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
	fi

	${queuing_command} ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh \
			   --path="$OutputStudyFolder" \
			   --subject=$Subject \
			   --fmriname=$fMRIName \
			   --fmritcs=$fMRITimeSeries \
			   --fmriscout=$fMRISBRef \
			   --SEPhaseNeg=$SpinEchoPhaseEncodeNegative \
			   --SEPhasePos=$SpinEchoPhaseEncodePositive \
			   --SE_TotalReadoutTime=${SE_RO_Time} \
			   --SBRef_TotalReadoutTime=${SBRef_RO_Time} \
			   --fmapmag=$MagnitudeInputName \
			   --fmapphase=$PhaseInputName \
			   --echospacing=$DwellTime \
			   --echodiff=$DeltaTE \
			   --unwarpdir=$UnwarpDir \
			   --fmrires=$FinalFMRIResolution \
			   --dcmethod=$DistortionCorrection \
			   --gdcoeffs=$GradientDistortionCoeffs \
			   --topupconfig=$TopUpConfig \
			   --printcom=$PRINTCOM

	# The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

	echo "set -- --path=${OutputStudyFolder} \
      --subject=$Subject \
      --fmriname=$fMRIName \
      --fmritcs=$fMRITimeSeries \
      --fmriscout=$fMRISBRef \
      --SEPhaseNeg=$SpinEchoPhaseEncodeNegative \
      --SEPhasePos=$SpinEchoPhaseEncodePositive \
      --fmapmag=$MagnitudeInputName \
      --fmapphase=$PhaseInputName \
      --echospacing=$DwellTime \
      --echodiff=$DeltaTE \
      --unwarpdir=$UnwarpDir \
      --fmrires=$FinalFMRIResolution \
      --dcmethod=$DistortionCorrection \
      --gdcoeffs=$GradientDistortionCoeffs \
      --topupconfig=$TopUpConfig \
      --printcom=$PRINTCOM"

	echo ". ${EnvironmentScript}"

	echo ""
	echo "----------------------------------------------"
	echo ""
    done     # loop through run number
	
    echo ""
  done       # loop through task name
  echo ""
done         # loop through subjects


