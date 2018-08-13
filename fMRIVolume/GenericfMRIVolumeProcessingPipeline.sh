#!/bin/bash 
set -e

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP) , gradunwarp (HCP version 1.0.2) 
#  environment: use SetUpHCPPipeline.sh  (or individually set FSLDIR, FREESURFER_HOME, HCPPIPEDIR, PATH - for gradient_unwarp.py)

########################################## PIPELINE OVERVIEW ########################################## 

# TODO

########################################## OUTPUT DIRECTORIES ########################################## 

# TODO

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source ${HCPPIPEDIR_Global}/log.shlib  # Logging related functions
source ${HCPPIPEDIR_Global}/opts.shlib # Command line option functions


################################################ SUPPORT FUNCTIONS ##################################################

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    cat <<EOF
        
GenericfMRIVolumeProcessingPipeline.sh

Usage: GenericfMRIVolumeProcessingPipeline.sh [options]

  --path=<path>           Path to study processed data folder (required)
                          Used with --subject input to create full path to root 
                          directory for all outputs generated as path/subject
  --subject=<subject>     Subject ID (required)
                          Used with --path input to create full path to root
                          directory for all outputs generated as path/subject
  --fmriname=<fmriname>   Name of the functional task to be processed
  --fmritcs=<fmritcs>     Name of the fMRI time series to be processed
  --fmriscout=<fmriscout> Name of the image to be used as reference for the motion
                          correction for the series
  --fmapmag=<file path>          Fieldmap magnitude file
  --fmapphase=<file path>        Fieldmap phase file
  --echodiff=<delta TE>          Delta TE in ms for field map or "NONE" if 
                                 not used
  --SEPhaseNeg={LR, RL, NONE}    For spin echo field map volume with a negative
                                 phase encoding direction (LR in HCP data), set
                                 to "NONE" if using regular FIELDMAP
  --SEPhasePos={LR, RL, NONE}    For the spin echo field map volume with a 
                                 positive phase encoding direction (RL in HCP 
                                 data), set to "NONE" if using regular FIELDMAP
  --SE_TotalReadoutTime=<SE_TotalReadoutTime>     Total Readout time for the Spin Echo Distortion
                                 Map or "NONE" if not used
  --unwarpdir={x, y, z}        Phase encoding direction of the fMRI time series.
                               (Used with either a regular field map or a spin
                               echo field map).  If spin echo distortion maps are
                               used for B0 correction, both the fMRI and the SE images
                               need to have the same PE direction.
  --fmrires=<fmrires>          Desired resolution of the processed images (in mm).
  --gdcoeffs=<file path>       File containing gradient distortion 
                               coefficients, Set to "NONE" to turn off
  --dcmethod={FIELDMAP, TOPUP} Type of field map used for B0 distortion correction.
  --topupconfig=<file path>    Configuration file for topup or "NONE" if not used.
  --printcom={echo, ""}        Use ="echo" for just printing everything and not running the commands (default is to run)
EOF

    exit 1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "GenericfMRIVolumeProcessingPipeline.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# parse arguments
OutputStudyFolder=`opts_GetOpt1 "--path" $@`  # "$1"
Subject=`opts_GetOpt1 "--subject" $@`  # "$2"
NameOffMRI=`opts_GetOpt1 "--fmriname" $@`  # "$6"
fMRITimeSeries=`opts_GetOpt1 "--fmritcs" $@`  # "$3"
fMRIScout=`opts_GetOpt1 "--fmriscout" $@`  # "$4"
SpinEchoPhaseEncodeNegative=`opts_GetOpt1 "--SEPhaseNeg" $@`  # "$7"
SpinEchoPhaseEncodePositive=`opts_GetOpt1 "--SEPhasePos" $@`  # "$5"
SE_RO_Time=`opts_GetOpt1 "--SE_TotalReadoutTime" $@` # "$"
SBRef_RO_Time=`opts_GetOpt1 "--SBRef_TotalReadoutTime" $@` # "$6"
MagnitudeInputName=`opts_GetOpt1 "--fmapmag" $@`  # "$8" #Expects 4D volume with two 3D timepoints
PhaseInputName=`opts_GetOpt1 "--fmapphase" $@`  # "$9"
deltaTE=`opts_GetOpt1 "--echodiff" $@`  # "${12}"
UnwarpDir=`opts_GetOpt1 "--unwarpdir" $@`  # "${13}"
FinalfMRIResolution=`opts_GetOpt1 "--fmrires" $@`  # "${14}"
DistortionCorrection=`opts_GetOpt1 "--dcmethod" $@`  # "${17}" #FIELDMAP or TOPUP
GradientDistortionCoeffs=`opts_GetOpt1 "--gdcoeffs" $@`  # "${18}"
TopupConfig=`opts_GetOpt1 "--topupconfig" $@`  # "${20}" #NONE if Topup is not being used
RUN=`opts_GetOpt1 "--printcom" $@`  # use ="echo" for just printing everything and not running the commands (default is to run)

# ------------------------------------------------------------------------------
#  Show Command Line Options
# ------------------------------------------------------------------------------

log_Msg "OutputStudyFolder: ${OutputStudyFolder}"
log_Msg "Subject: ${Subject}"
log_Msg "NameOffMRI: ${NameOffMRI}"
log_Msg "fMRITimeSeries: ${fMRITimeSeries}"
log_Msg "fMRIScout: ${fMRIScout}"
log_Msg "SpinEchoPhaseEncodeNegative: ${SpinEchoPhaseEncodeNegative}"
log_Msg "SpinEchoPhaseEncodePositive: ${SpinEchoPhaseEncodePositive}"
log_Msg "SE_RO_Time: ${SE_RO_Time}"
log_Msg "SBRef_RO_Time: ${SBRef_RO_Time}"
log_Msg "MagnitudeInputName: ${MagnitudeInputName}"
log_Msg "PhaseInputName: ${PhaseInputName}"
log_Msg "deltaTE: ${deltaTE}"
log_Msg "UnwarpDir: ${UnwarpDir}"
log_Msg "FinalfMRIResolution: ${FinalfMRIResolution}"
log_Msg "DistortionCorrection: ${DistortionCorrection}"
log_Msg "GradientDistortionCoeffs: ${GradientDistortionCoeffs}"
log_Msg "TopupConfig: ${TopupConfig}"

# Setup PATHS
PipelineScripts=${HCPPIPEDIR_fMRIVol}
GlobalScripts=${HCPPIPEDIR_Global}

#Naming Conventions
T1wImage="T1w_acpc_dc"
T1wRestoreImage="T1w_acpc_dc_restore"
T1wRestoreImageBrain="T1w_acpc_dc_restore_brain"
T1wFolder="T1w" #Location of T1w images
AtlasSpaceFolder="MNINonLinear"
ResultsFolder="Results"
BiasField="BiasField_acpc_dc"
BiasFieldMNI="BiasField"
T1wAtlasName="T1w_restore"
MovementRegressor="Movement_Regressors" #No extension, .txt appended
MotionMatrixFolder="MotionMatrices"
MotionMatrixPrefix="MAT_"
FieldMapOutputName="FieldMap"
MagnitudeOutputName="Magnitude"
MagnitudeBrainOutputName="Magnitude_brain"
ScoutName="Scout"
OrigScoutName="${ScoutName}_orig"
OrigTCSName="${NameOffMRI}_orig"
FreeSurferBrainMask="brainmask_fs"
fMRI2strOutputTransform="${NameOffMRI}2str"
RegOutput="Scout2T1w"
AtlasTransform="acpc_dc2standard"
OutputfMRI2StandardTransform="${NameOffMRI}2standard"
Standard2OutputfMRITransform="standard2${NameOffMRI}"
QAImage="T1wMulEPI"
JacobianOut="Jacobian"


########################################## DO WORK ########################################## 

# to distinguish between different runs and acquisitions:
acqRun=${fMRITimeSeries##*_task-${NameOffMRI}_}
acqRun=${acqRun%_bold.nii*}

T1wFolder="$OutputStudyFolder"/"sub-$Subject"/"$T1wFolder"
AtlasSpaceFolder="$OutputStudyFolder"/"sub-$Subject"/"$AtlasSpaceFolder"
ResultsFolder="$AtlasSpaceFolder"/"$ResultsFolder"/"$NameOffMRI"/"$acqRun"
fMRIFolder="$OutputStudyFolder"/"sub-$Subject"/"$NameOffMRI"/"$acqRun"
if [ ! -e "$fMRIFolder" ] ; then
  log_Msg "mkdir -p ${fMRIFolder}"
  mkdir -p "$fMRIFolder"
fi
cp "$fMRITimeSeries" "$fMRIFolder"/"$OrigTCSName".nii.gz

#Create fake "Scout" if it doesn't exist
if [ $fMRIScout = "NONE" ] ; then
  ${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$OrigScoutName" 0 1
else
  cp "$fMRIScout" "$fMRIFolder"/"$OrigScoutName".nii.gz
fi
scout_RO_Time=${SBRef_RO_Time}


#Gradient Distortion Correction of fMRI
log_Msg "Gradient Distortion Correction of fMRI"
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
    log_Msg "mkdir -p ${fMRIFolder}/GradientDistortionUnwarp"
    mkdir -p "$fMRIFolder"/GradientDistortionUnwarp
    ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	--workingdir="$fMRIFolder"/GradientDistortionUnwarp \
	--coeffs="$GradientDistortionCoeffs" \
	--in="$fMRIFolder"/"$OrigTCSName" \
	--out="$fMRIFolder"/"$NameOffMRI"_gdc \
	--owarp="$fMRIFolder"/"$NameOffMRI"_gdc_warp

    log_Msg "mkdir -p ${fMRIFolder}/${ScoutName}_GradientDistortionUnwarp"	
     mkdir -p "$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp
     ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	 --workingdir="$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp \
	 --coeffs="$GradientDistortionCoeffs" \
	 --in="$fMRIFolder"/"$OrigScoutName" \
	 --out="$fMRIFolder"/"$ScoutName"_gdc \
	 --owarp="$fMRIFolder"/"$ScoutName"_gdc_warp
else
    log_Msg "NOT PERFORMING GRADIENT DISTORTION CORRECTION"
    ${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$NameOffMRI"_gdc
    ${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$NameOffMRI"_gdc "$fMRIFolder"/"$NameOffMRI"_gdc_warp 0 3
    ${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp -mul 0 "$fMRIFolder"/"$NameOffMRI"_gdc_warp
    ${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigScoutName" "$fMRIFolder"/"$ScoutName"_gdc
fi

log_Msg "mkdir -p ${fMRIFolder}/MotionCorrection_FLIRTbased"
mkdir -p "$fMRIFolder"/MotionCorrection_FLIRTbased
${RUN} "$PipelineScripts"/MotionCorrection_FLIRTbased.sh \
    "$fMRIFolder"/MotionCorrection_FLIRTbased \
    "$fMRIFolder"/"$NameOffMRI"_gdc \
    "$fMRIFolder"/"$ScoutName"_gdc \
    "$fMRIFolder"/"$NameOffMRI"_mc \
    "$fMRIFolder"/"$MovementRegressor" \
    "$fMRIFolder"/"$MotionMatrixFolder" \
    "$MotionMatrixPrefix" 


#EPI Distortion Correction and EPI to T1w Registration
log_Msg "EPI Distortion Correction and EPI to T1w Registration"
if [ -e ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased ] ; then
  rm -r ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased
fi
log_Msg "mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased"
mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased

${RUN} ${PipelineScripts}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased.sh \
    --workingdir=${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased \
    --scoutin=${fMRIFolder}/${ScoutName}_gdc \
    --t1=${T1wFolder}/${T1wImage} \
    --t1restore=${T1wFolder}/${T1wRestoreImage} \
    --t1brain=${T1wFolder}/${T1wRestoreImageBrain} \
    --fmapmag=${MagnitudeInputName} \
    --fmapphase=${PhaseInputName} \
    --echodiff=${deltaTE} \
    --SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
    --SEPhasePos=${SpinEchoPhaseEncodePositive} \
    --SE_TotalReadoutTime=${SE_RO_Time} \
    --scout_TotalReadoutTime=${scout_RO_Time} \
    --unwarpdir=${UnwarpDir} \
    --owarp=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
    --biasfield=${T1wFolder}/${BiasField} \
    --oregim=${fMRIFolder}/${RegOutput} \
    --freesurferfolder=${T1wFolder} \
    --freesurfersubjectid=${Subject} \
    --gdcoeffs=${GradientDistortionCoeffs} \
    --qaimage=${fMRIFolder}/${QAImage} \
    --method=${DistortionCorrection} \
    --topupconfig=${TopupConfig} \
    --ojacobian=${fMRIFolder}/${JacobianOut} 
    
#One Step Resampling
log_Msg "One Step Resampling"
log_Msg "mkdir -p ${fMRIFolder}/OneStepResampling"
mkdir -p ${fMRIFolder}/OneStepResampling
${RUN} ${PipelineScripts}/OneStepResampling.sh \
    --workingdir=${fMRIFolder}/OneStepResampling \
    --infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
    --t1=${AtlasSpaceFolder}/${T1wAtlasName} \
    --fmriresout=${FinalfMRIResolution} \
    --fmrifolder=${fMRIFolder} \
    --fmri2structin=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
    --struct2std=${AtlasSpaceFolder}/xfms/${AtlasTransform} \
    --owarp=${AtlasSpaceFolder}/xfms/${OutputfMRI2StandardTransform} \
    --oiwarp=${AtlasSpaceFolder}/xfms/${Standard2OutputfMRITransform} \
    --motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
    --motionmatprefix=${MotionMatrixPrefix} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --freesurferbrainmask=${AtlasSpaceFolder}/${FreeSurferBrainMask} \
    --biasfield=${AtlasSpaceFolder}/${BiasFieldMNI} \
    --gdfield=${fMRIFolder}/${NameOffMRI}_gdc_warp \
    --scoutin=${fMRIFolder}/${OrigScoutName} \
    --scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --jacobianin=${fMRIFolder}/${JacobianOut} \
    --ojacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}
    
#Intensity Normalization and Bias Removal
log_Msg "Intensity Normalization and Bias Removal"
${RUN} ${PipelineScripts}/IntensityNormalization.sh \
    --infmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --biasfield=${fMRIFolder}/${BiasFieldMNI}.${FinalfMRIResolution} \
    --jacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution} \
    --brainmask=${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin_norm \
    --inscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm \
    --usejacobian=false

log_Msg "mkdir -p ${ResultsFolder}"
mkdir -p ${ResultsFolder}
# MJ QUERY: WHY THE -r OPTIONS BELOW?
# TBr Response: Since the copy operations are specifying individual files
# to be copied and not directories, the recursive copy options (-r) to the
# cp calls below definitely seem unnecessary. They should be removed in 
# a code clean up phase when tests are in place to verify that removing them
# has no unexpected bad side-effect.
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}.nii.gz
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}.txt ${ResultsFolder}/${MovementRegressor}.txt
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}_dt.txt ${ResultsFolder}/${MovementRegressor}_dt.txt
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}_SBRef.nii.gz
${RUN} cp -r ${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}.nii.gz ${ResultsFolder}/${NameOffMRI}_${JacobianOut}.nii.gz
${RUN} cp -r ${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution}.nii.gz ${ResultsFolder}
###Add stuff for RMS###
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS.txt ${ResultsFolder}/Movement_RelativeRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS.txt ${ResultsFolder}/Movement_AbsoluteRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS_mean.txt ${ResultsFolder}/Movement_RelativeRMS_mean.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS_mean.txt ${ResultsFolder}/Movement_AbsoluteRMS_mean.txt
###Add stuff for RMS###

log_Msg "Completed"

