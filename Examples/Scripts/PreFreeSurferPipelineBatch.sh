#!/bin/bash

# Changes w.r.t. the official HCP Pipelines v.3.4.0:
# - It assumes data organization and file names follow BIDS convention
# - Separated folder for input (BIDS) and output (processed) images
# - It reads the DwellTime, PE direction, etc. from the .json files
# - Added "B0distortionCorrectionMode" as an option
# - Checks if the shim settings for the high-res images are the same as
#   for the SE-distortion-maps.  If not, it doesn't use TOPUP correction
# - If more than one anatomical image is present, it checks to see if there are
#   duplicates (e.g. normalized + original images) and if there are duplicates,
#   it uses the original images.

get_batch_options() {
    local arguments=($@)

    unset command_line_specified_BIDS_study_folder
    unset command_line_specified_output_study_folder
    unset command_line_specified_subj_list
    unset command_line_specified_B0_distortion_correction_mode
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
            --B0distortionCorrectionMode=*)
		command_line_specified_B0_distortion_correction_mode=${argument/*=/""}
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

get_Input_TXw_Images() {
  # Function to select the TXw (T1w or T2w) images to use as input to the PreFreeSurferPipeline
  # given a list of runs.  It checks if some of these runs have the same acquisition times and,
  # if there are some that do, picks the (first) non-normalized one.

  # Transform argument list into an array, for easier element access:
  local TXwImages=($@)

  # Get the acquisition time for all TXw runs:
  local unset acqTimes
  local i=0;
  while [ $i -lt ${#TXwImages[@]} ]; do
      acqTimes[$i]=`read_header_param "AcquisitionTime" ${TXwImages[$i]%.nii*}.json`
      i=$(($i+1)) 
  done

  local unset TXwInputImages

  # Loop through the unique acquisition times:
  sorted_unique_acqTimes=($(echo "${acqTimes[@]}" | tr ' ' '\n' | sort -u ));
  local j=0;
  while [ $j -lt ${#sorted_unique_acqTimes[@]} ]; do
      # get indices of all runs with this acquisition time:
      unset inds
      local k=0
      local i=0
      while [ $i -lt ${#acqTimes[@]} ]; do
	  if [ ${acqTimes[$i]} == ${sorted_unique_acqTimes[$j]} ]; then    # (acquisition times are strings)
	      inds[$k]=$i
	      k=$(($k+1))
	  fi
	  i=$(($i+1)) 
      done

      #echo "Unique acquisition times: ${sorted_unique_acqTimes[@]}, indices: ${inds[@]}" >> dummy.log

      # Check how many runs have this acquisition time:
      if [ ${#inds[@]} -gt 1 ]; then
	  # If there is more than one run with this acquisition time
	  # Loop through all these runs:
          local k=0
	  while [ $k -lt ${#inds[@]} ]; do
	      # grab the "ImageType" entries in the corresponding .json:
	      # we know it's going to be less than 20 lines for sure:
	      local myImageType=`read_multiline_header_param "ImageType" ${TXwImages[${inds[$k]}]%.nii*}.json`

	      # Check to see if the image type is Normalized:
  	      # Discard the "Normalized" ones, and pick the first non-normalized:
	      if ! [[ $myImageType == *\"NORM\"* ]]; then
  		  # If it is NOT normalized:
		  T1wInputImages[$j]=${TXwImages[${inds[$k]}]}
		  break
	      fi
	      k=$(($k+1))
	  done
	  if [ -z ${TXwInputImages[$j]} ]; then
	      # if all of them were "normalized" runs, just grab the first one:
	      TXwInputImages[$j]=${TXwImages[${inds[0]}]}
	  fi
      else
	  # If there is only one, keep as input to the FreeSurferPipeline:
	  TXwInputImages[$j]=${TXwImages[${inds[0]}]}
      fi

      j=$(($j+1))
  done

  # The output:
  echo "${TXwInputImages[@]}"
  return 0
}

get_T1s() {

  local T1wImages     # list with all high-res T1 images
  doWeHaveSessions=( $(ls -d ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
  if [ $? -eq 0 ]; then
    # if there are sessions:
    T1wImages=`ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/anat/sub-${Subject}_ses-*_acq-highres*_T1w.nii*`
  else
    T1wImages=`ls ${BIDSStudyFolder}/sub-${Subject}/anat/sub-${Subject}*_acq-highres*_T1w.nii*`
  fi
  #echo "T1wImages: ${T1wImages[@]}"

  # Get the unique ones (e.g.: normalized and unnormalized):
  T1wInputImages=`get_Input_TXw_Images ${T1wImages[@]}`
 
  echo "Found ${#T1wInputImages[@]} T1w Images for subject ${Subject}"
  #echo "T1wInputImages: ${T1wInputImages[@]}"

  return  
}

get_T2s() {

  local T2wImages     # list with all high-res T2 images
  doWeHaveSessions=( $(ls -d ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
  if [ $? -eq 0 ]; then
    # if there are sessions, try/catch:
    T2wImages=`ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/anat/sub-${Subject}_ses-*_acq-highres*_T2w.nii*` || T2wImages="NONE"
  else
    # try/catch:
    T2wImages=`ls ${BIDSStudyFolder}/sub-${Subject}/anat/sub-${Subject}*_acq-highres*_T2w.nii*` || T2wImages="NONE"
  fi
  #echo "T2wImages: ${T2wImages[@]}"

  if [ ! ${T2wImages%%.nii*} = "NONE" ] ; then
    # Get the unique ones (e.g.: normalized and unnormalized):
    T2wInputImages=`get_Input_TXw_Images ${T2wImages[@]}`
    echo "Found ${#T2wInputImages[@]} T2w Images for subject ${Subject}"
  else
    T2wInputImages="NONE"
    echo "No T2w Images were found for subject ${Subject}"
  fi

  #echo "T2wInputImages: ${T2wInputImages[@]}"

  return  
}

#####     #####     Main     #####     #####

get_batch_options $@

# Default options:
BIDSStudyFolder="${HOME}/projects/Pipelines_ExampleData" #Location of Subject folders (named by sub-subjectID)
Subjlist="100307" #Space delimited list of subject IDs
B0distortionCorrectionMode="NONE"
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
if [ -n "${command_line_specified_B0_distortion_correction_mode}" ]; then

    # check to make sure it is one of the allowed modes:
    case ${command_line_specified_B0_distortion_correction_mode} in

	"NONE"|"FIELDMAP"|"TOPUP")
	    B0distortionCorrectionMode="${command_line_specified_B0_distortion_correction_mode}"
	    ;;
	*)
	    echo "Valid B0distortionCorrectionMode are \"NONE\", \"FIELDMAP\" or \"TOPUP\"."
	    echo "    \"${command_line_specified_B0_distortion_correction_mode}\" is not valid."
	    echo "    Using \"NONE\"."
	    B0distortionCorrectionMode="NONE"
	    ;;
    esac
fi

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP), gradunwarp (HCP version 1.0.2) if doing gradient distortion correction
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

#	${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/anat/sub-${Subject}[_ses-${session}]_*[run-<index>]_T1w.nii[.gz]
#       ${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/anat/sub-${Subject}[_ses-${session}]_*[run-<index>]_T2w.nii[.gz]

#       ${BIDSStudyFolder}/sub-${Subject}[/ses-${session}]/fmap/sub-${Subject}[_ses-${session}]_*_dir-AP_[run-<index>]_epi.nii[.gz]


#Scan Settings (Sample Spacings, and $UnwarpDir) are read from *.json sidecar files

#You have the option of using either gradient echo field maps or spin echo field maps to 
#correct your structural images for readout distortion, or not to do this correction at all
#

#If using gradient distortion correction, use the coefficents from your scanner
#The HCP gradient distortion coefficents are only available through Siemens
#Gradient distortion in standard scanners like the Trio is much less than for the HCP Skyra.


######################################### DO WORK ##########################################


#echo ${BIDSStudyFolder}
for Subject in $Subjlist ; do
  echo sub-$Subject
  
  ###   Input Images   ###
  # Check to see if there are session subfolders:
  sesFolders=( $(ls -d ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
  # if we didn't find any, assign it to the subject level:
  if [ $? -gt 0 ]; then
    sesFolders=${BIDSStudyFolder}/sub-${Subject}
  fi

  # Get T1 images (they will be stored in the variable "T1wInputImages")
  get_T1s $Subject
  
  # Get T2 images (they will be stored in the variable "T2wInputImages")
  get_T2s $Subject
  
  
  ###    B0 Distortion Correction    ###

  # AvgrdcSTRING: Averaging and readout distortion correction methods:
  #   - "NONE" = average any repeats with no readout correction
  #   - "FIELDMAP" = average any repeats and use field map for readout correction
  #   - "TOPUP" = use spin echo field map
  # For now, we are going to use a pair of spin-echo distortion scan (Topup method):
  AvgrdcSTRING=$B0distortionCorrectionMode

  case $AvgrdcSTRING in

      "NONE")
	  echo "user chose no B0 correction"
	  MagnitudeInputName="NONE"
	  PhaseInputName="NONE"
	  TE="NONE"
	  SpinEchoPhaseEncodeNegative="NONE"
	  SpinEchoPhaseEncodePositive="NONE"
	  SE_RO_Time="NONE"
	  SEUnwarpDir="NONE"
	  TopupConfig="NONE"
	  ;;

      "FIELDMAP")
	  #Using Regular Gradient Echo Field Maps:
	  echo "user chose Fieldmap B0 correction"

	  doWeHaveSessions=( $(ls -d ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
	  if [ $? -eq 0 ]; then
	    # if there are sessions:
	    MagnitudeInputName=`ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/fmap/sub-${Subject}_ses-*_acq-GRE*_magnitude*.nii*` #Expects 3D or 4D (two 3D timepoints) magitude volume
	    PhaseInputName=`ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/fmap/sub-${Subject}_ses-*_acq-GRE*_phasediff*.nii*` #Expects 3D phase difference volume
	  else
	    MagnitudeInputName=`ls ${BIDSStudyFolder}/sub-${Subject}/fmap/sub-${Subject}_acq-GRE*_magnitude*.nii*` #Expects 4D magitude volume with two 3D timepoints
	    PhaseInputName=`ls ${BIDSStudyFolder}/sub-${Subject}/fmap/sub-${Subject}_acq-GRE*_phasediff*.nii*` #Expects 3D phase difference volume
	  fi
	  # TO-DO: if there is more than one, pick which one (maybe the one closest in time?)
	  # For now, just keep the first one:
	  MagnitudeInputName=`ls ${MagnitudeInputName%%.nii*}.nii*`
	  PhaseInputName=`ls ${PhaseInputName%%.nii*}.nii*`

	  ##   Check shims consistency   ##
	  
	  # Before applying blindly, check that the "ShimSetting" for the fmap images was
	  #   identical to that of the T1 high-res images (check just the first one):
	  shimGRE=`read_multiline_header_param "ShimSetting" ${MagnitudeInputName%.nii*}.json`
	  shimT1w=`read_multiline_header_param "ShimSetting" ${T1wInputImages[0]%.nii*}.json`
	  #echo "$shimGRE == $shimT1w?"
	  if [ ! "$shimGRE" == "$shimT1w" ]; then
	    # If the shims are different:
	    echo "WARNING: Shims settings for anatomical images and GRE Fieldmaps are not the same."
	    echo "WARNING: We're not doing B0 correction for Subject $Subject"
	    AvgrdcSTRING="NONE"
	    MagnitudeInputName="NONE"
	    PhaseInputName="NONE"
	    TE="NONE"
	  else
	    # Do the correction (even though the shims for the T2w might be different I still want
	    #   the correction done):
	    TE=`get_DeltaTE ${PhaseInputName%.nii*}.json`
	  fi
	  
	  SpinEchoPhaseEncodeNegative="NONE"
	  SpinEchoPhaseEncodePositive="NONE"
	  SE_RO_Time="NONE"
	  SEUnwarpDir="NONE"
	  TopupConfig="NONE"
	  ;;

      "TOPUP")
	  #Using Spin Echo Field Maps (same as for fMRIVolume pipeline)
	  echo "user chose Topup B0 correction"

	  doWeHaveSessions=( $(ls -d ${BIDSStudyFolder}/sub-${Subject}/ses-* 2> /dev/null) )
	  if [ $? -eq 0 ]; then
	    # if there are sessions:
            #volume with a negative/positive phase encoding direction:
	    SpinEchoPhaseEncodeNegative=( $(ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/fmap/sub-${Subject}_ses-*_dir-AP*.nii* 2> /dev/null) )
	    if [ $? -gt 0 ]; then
	      # if we didn't find any, skip the field correction:
	      echo "WARNING: No distortion-map runs were found."
	      echo "WARNING: We're not doing B0 correction for Subject $Subject"
	      AvgrdcSTRING="NONE"
	      MagnitudeInputName="NONE"
	      PhaseInputName="NONE"
	      TE="NONE"
	      SpinEchoPhaseEncodeNegative="NONE"
	      SpinEchoPhaseEncodePositive="NONE"
	      SE_RO_Time="NONE"
	      SEUnwarpDir="NONE"
	      TopupConfig="NONE"
	    else
	      SpinEchoPhaseEncodePositive=`ls ${BIDSStudyFolder}/sub-${Subject}/ses-*/fmap/sub-${Subject}_ses-*_dir-PA*.nii*`
	    fi
	  else
	    # no sessions:
	    SpinEchoPhaseEncodeNegative=( $(ls ${BIDSStudyFolder}/sub-${Subject}/fmap/sub-${Subject}_ses-*_dir-AP*.nii* 2> /dev/null) )
	    if [ $? -gt 0 ]; then
	      # if we didn't find any, skip the field correction:
	      echo "WARNING: No distortion-map runs were found."
	      echo "WARNING: We're not doing B0 correction for Subject $Subject"
	      AvgrdcSTRING="NONE"
	      MagnitudeInputName="NONE"
	      PhaseInputName="NONE"
	      TE="NONE"
	      SpinEchoPhaseEncodeNegative="NONE"
	      SpinEchoPhaseEncodePositive="NONE"
	      SE_RO_Time="NONE"
	      SEUnwarpDir="NONE"
	      TopupConfig="NONE"
	    else
	      SpinEchoPhaseEncodePositive=`ls ${BIDSStudyFolder}/sub-${Subject}/fmap/sub-${Subject}*_dir-PA*.nii*`
	    fi
	  fi

	  # if we found distortion map files, continue:
	  if [ $SpinEchoPhaseEncodeNegative != "NONE" ]; then
	    # TO-DO: if there is more than one, pick which one (maybe the one closest in time?)
	    # For now, just keep the first one:
	    SpinEchoPhaseEncodeNegative=`ls ${SpinEchoPhaseEncodeNegative%%.nii*}.nii*`
	    SpinEchoPhaseEncodePositive=`ls ${SpinEchoPhaseEncodePositive%%.nii*}.nii*`

	    ##   Check shims consistency   ##
	  
	    # Before applying blindly, check that the "ShimSetting" for the fmap images was
	    #   identical to that of the T1 high-res images (check just the first one):
	    shimSENeg=`read_multiline_header_param "ShimSetting" ${SpinEchoPhaseEncodeNegative%.nii*}.json`
	    shimT1w=`read_multiline_header_param "ShimSetting" ${T1wInputImages[0]%.nii*}.json`
	    #echo "$shimSENeg == $shimT1w?"
	    if [ ! "$shimSENeg" == "$shimT1w" ]; then
	      # If the shims are different:
	      echo "WARNING: Shims settings for anatomical images and SE Distortion Maps are not the same."
	      echo "WARNING: We're not doing B0 correction for Subject $Subject"
	      AvgrdcSTRING="NONE"
	      MagnitudeInputName="NONE"
	      PhaseInputName="NONE"
	      TE="NONE"
	      SpinEchoPhaseEncodeNegative="NONE"
	      SpinEchoPhaseEncodePositive="NONE"
	      SE_RO_Time="NONE"
	      SEUnwarpDir="NONE"
	      TopupConfig="NONE"
	    else
	      # Do the correction (even though the shims for the T2w might be different I still want
	      #   the correction done):
	      SE_RO_Time=`read_header_param TotalReadoutTime ${SpinEchoPhaseEncodeNegative%.nii*}.json`

	      # SEUnwarpDir: x or y (minus or not does not matter) "NONE" if not used
	      myTmp=`read_header_param "PhaseEncodingDirection" ${SpinEchoPhaseEncodeNegative%.nii*}.json`
	      if [ ${myTmp%,} == \"i\" ] || [ ${myTmp%,} == \"i-\" ]; then
		  SEUnwarpDir="x"
	      elif [ ${myTmp%,} == \"j\" ] || [ ${myTmp%,} == \"j-\" ]; then
		  SEUnwarpDir="y"
	      fi
	      
	      TopupConfig="b02b0.cnf" #Config for topup or "NONE" if not used
	    fi
	  fi
	  ;;
  esac


  ###   Templates   ###
  T1wTemplate="${HCPPIPEDIR_Templates}/MNI152_T1_0.7mm.nii.gz" #Hires T1w MNI template
  T1wTemplateBrain="${HCPPIPEDIR_Templates}/MNI152_T1_0.7mm_brain.nii.gz" #Hires brain extracted MNI template
  T1wTemplate2mm="${HCPPIPEDIR_Templates}/MNI152_T1_2mm.nii.gz" #Lowres T1w MNI template
  T2wTemplate="${HCPPIPEDIR_Templates}/MNI152_T2_0.7mm.nii.gz" #Hires T2w MNI Template
  T2wTemplateBrain="${HCPPIPEDIR_Templates}/MNI152_T2_0.7mm_brain.nii.gz" #Hires T2w brain extracted MNI Template
  T2wTemplate2mm="${HCPPIPEDIR_Templates}/MNI152_T2_2mm.nii.gz" #Lowres T2w MNI Template
  TemplateMask="${HCPPIPEDIR_Templates}/MNI152_T1_0.7mm_brain_mask.nii.gz" #Hires MNI brain mask template
  Template2mmMask="${HCPPIPEDIR_Templates}/MNI152_T1_2mm_brain_mask_dil.nii.gz" #Lowres MNI brain mask template


  ###   Structural Scan Settings   ###
  # (set all to NONE if not doing readout distortion correction)
  # We get it from the corresponding .json file:

  T1wSampleSpacing=`read_header_param "DwellTime" ${T1wInputImages[0]%.nii*}.json`
  printf -v T1wSampleSpacing "%.9f" "${T1wSampleSpacing}"    # convert from scientific to float notation
  #T1wSampleSpacing=`echo ${T1wSampleSpacing} | awk '{ print sprintf("%.9f", $1); }'`

  if [ ! $T2wInputImages = "NONE" ] ; then
      T2wSampleSpacing=`read_header_param "DwellTime" ${T2wInputImages[0]%.nii*}.json`
      printf -v T2wSampleSpacing "%.9f" "${T2wSampleSpacing}"    # convert from scientific to float notation
      #T2wSampleSpacing=`echo ${T2wSampleSpacing} | awk '{ print sprintf("%.9f", $1); }'`
  fi
  
  UnwarpDir="z" #z appears to be best or "NONE" if not used  -> this in only true for sagittal slices, for which the readout is along H>F (=z)
  # TO-DO: get the readout direction (as x, y or z)

  #Other Config Settings
  BrainSize="150" #BrainSize in mm, 150 for humans
  FNIRTConfig="${HCPPIPEDIR_Config}/T1_2_MNI152_2mm.cnf" #FNIRT 2mm T1w Config
  GradientDistortionCoeffs="${HCPPIPEDIR_Config}/coeff.grad"   # Default location of Coeffs file
  # if it doesn't exist, skip it:
  if [ ! -f ${GradientDistortionCoeffs} ]; then
    GradientDistortionCoeffs="NONE" # Set to NONE to skip gradient distortion correction
  fi

  if [ -n "${command_line_specified_run_local}" ] ; then
      echo "About to run ${HCPPIPEDIR}/PreFreeSurfer/PreFreeSurferPipeline.sh"
      queuing_command=""
  else
      echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/PreFreeSurfer/PreFreeSurferPipeline.sh"
      queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
  fi

  ${queuing_command} ${HCPPIPEDIR}/PreFreeSurfer/PreFreeSurferPipeline.sh \
      --path="$OutputStudyFolder" \
      --subject="$Subject" \
      --t1="$T1wInputImages" \
      --t2="$T2wInputImages" \
      --t1template="$T1wTemplate" \
      --t1templatebrain="$T1wTemplateBrain" \
      --t1template2mm="$T1wTemplate2mm" \
      --t2template="$T2wTemplate" \
      --t2templatebrain="$T2wTemplateBrain" \
      --t2template2mm="$T2wTemplate2mm" \
      --templatemask="$TemplateMask" \
      --template2mmmask="$Template2mmMask" \
      --brainsize="$BrainSize" \
      --fnirtconfig="$FNIRTConfig" \
      --fmapmag="$MagnitudeInputName" \
      --fmapphase="$PhaseInputName" \
      --echodiff="$TE" \
      --SEPhaseNeg="$SpinEchoPhaseEncodeNegative" \
      --SEPhasePos="$SpinEchoPhaseEncodePositive" \
      --SE_TotalReadoutTime="$SE_RO_Time" \
      --seunwarpdir="$SEUnwarpDir" \
      --t1samplespacing="$T1wSampleSpacing" \
      --t2samplespacing="$T2wSampleSpacing" \
      --unwarpdir="$UnwarpDir" \
      --gdcoeffs="$GradientDistortionCoeffs" \
      --avgrdcmethod="$AvgrdcSTRING" \
      --topupconfig="$TopupConfig" \
      --printcom=$PRINTCOM
      
  # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

  echo "set -- --path=${OutputStudyFolder} \
      --subject=${Subject} \
      --t1=${T1wInputImages} \
      --t2=${T2wInputImages} \
      --t1template=${T1wTemplate} \
      --t1templatebrain=${T1wTemplateBrain} \
      --t1template2mm=${T1wTemplate2mm} \
      --t2template=${T2wTemplate} \
      --t2templatebrain=${T2wTemplateBrain} \
      --t2template2mm=${T2wTemplate2mm} \
      --templatemask=${TemplateMask} \
      --template2mmmask=${Template2mmMask} \
      --brainsize=${BrainSize} \
      --fnirtconfig=${FNIRTConfig} \
      --fmapmag=${MagnitudeInputName} \
      --fmapphase=${PhaseInputName} \
      --echodiff=${TE} \
      --SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
      --SEPhasePos=${SpinEchoPhaseEncodePositive} \
      --SE_TotalReadoutTime=${SE_RO_Time} \
      --seunwarpdir=${SEUnwarpDir} \     
      --t1samplespacing=${T1wSampleSpacing} \
      --t2samplespacing=${T2wSampleSpacing} \
      --unwarpdir=${UnwarpDir} \
      --gdcoeffs=${GradientDistortionCoeffs} \
      --avgrdcmethod=${AvgrdcSTRING} \
      --topupconfig=${TopupConfig} \
      --printcom=${PRINTCOM}"

  echo ". ${EnvironmentScript}"

done

