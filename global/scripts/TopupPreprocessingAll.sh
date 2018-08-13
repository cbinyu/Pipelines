#!/bin/bash 
set -e
#set -xv    # un-comment this for the script (and all called within) to be printed out to stdout
# Requirements for this script
#  installed versions of: FSL (version 5.0.6), HCP-gradunwarp (version 1.0.2)
#  environment: as in SetUpHCPPipeline.sh  (or individually: FSLDIR, HCPPIPEDIR_Global, HCPPIPEDIR_Bin and PATH for gradient_unwarp.py)

################################################ SUPPORT FUNCTIONS ##################################################

Usage() {
  echo "`basename $0`: Script for using topup to do distortion correction for EPI (scout)"
  echo " "
  echo "Usage: `basename $0` [--workingdir=<working directory>]"
  echo "            --phaseone=<first set of SE EPI images: with -x PE direction (LR)>"
  echo "            --phasetwo=<second set of SE EPI images: with x PE direction (RL)>"
  echo "            --scoutin=<scout input image: should be corrected for gradient non-linear distortions>"
  echo "            --SE_TotalReadoutTime=<Total readout time for the SE EPI>"
  echo "            --scout_TotalReadoutTime=<Total readout time for the scout input image>"
  echo "            --unwarpdir=<PE direction for unwarping: x/y/z/-x/-y/-z>"
  echo "            [--owarp=<output warpfield image: scout to distortion corrected SE EPI>]"
  echo "            [--ofmapmag=<output 'Magnitude' image: scout to distortion corrected SE EPI>]" 
  echo "            [--ofmapmagbrain=<output 'Magnitude' brain image: scout to distortion corrected SE EPI>]"   
  echo "            [--ofmap=<output scaled topup field map image>]"
  echo "            [--ojacobian=<output Jacobian image>]"
  echo "            --gdcoeffs=<gradient non-linearity distortion coefficients (Siemens format)>"
  echo "             [--topupconfig=<topup config file>]"
  echo " "
  echo "   Note: the input SE EPI images should not be distortion corrected (for gradient non-linearities)"
}

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

################################################### OUTPUT FILES #####################################################

# Output images (in $WD): 
#          BothPhases      (input to topup - combines both pe direction data, plus masking)
#          SBRef2PhaseOne_gdc.mat SBRef2PhaseOne_gdc   (linear registration result)
#          PhaseOne_gdc  PhaseTwo_gdc
#          PhaseOne_gdc_dc  PhaseOne_gdc_dc_jac  PhaseTwo_gdc_dc  PhaseTwo_gdc_dc_jac
#          SBRef_dc   SBRef_dc_jac
#          WarpField  Jacobian
# Output images (not in $WD): 
#          ${DistortionCorrectionWarpFieldOutput}  ${JacobianOutput}

################################################## OPTION PARSING #####################################################

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options
if [ $# -lt 7 ] ; then Usage; exit 1; fi

# parse arguments
WD=`getopt1 "--workingdir" $@`  # "$1"
PhaseEncodeOne=`getopt1 "--phaseone" $@`  # "$2" #SCRIPT REQUIRES LR/X-/-1 VOLUME FIRST (SAME IS TRUE OF AP/PA)
PhaseEncodeTwo=`getopt1 "--phasetwo" $@`  # "$3" #SCRIPT REQUIRES RL/X/1 VOLUME SECOND (SAME IS TRUE OF AP/PA)
ScoutInputName=`getopt1 "--scoutin" $@`  # "$4"
SE_RO_Time=`getopt1 "--SE_TotalReadoutTime" $@` # "$5"
scout_RO_Time=`getopt1 "--scout_TotalReadoutTime" $@` # "$6"
UnwarpDir=`getopt1 "--unwarpdir" $@`  # "$7"
DistortionCorrectionWarpFieldOutput=`getopt1 "--owarp" $@`  # "$8"
DistortionCorrectionMagnitudeOutput=`getopt1 "--ofmapmag" $@`
DistortionCorrectionMagnitudeBrainOutput=`getopt1 "--ofmapmagbrain" $@`
DistortionCorrectionFieldOutput=`getopt1 "--ofmap" $@`
JacobianOutput=`getopt1 "--ojacobian" $@`  # "$9"
GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`  # "$10"
TopupConfig=`getopt1 "--topupconfig" $@`  # "${12}"

GlobalScripts=${HCPPIPEDIR_Global}

# default parameters #Breaks when --owarp becomes optional
#DistortionCorrectionWarpFieldOutput=`$FSLDIR/bin/remove_ext $DistortionCorrectionWarpFieldOutput`
#WD=`defaultopt $WD ${DistortionCorrectionWarpFieldOutput}.wdir`

echo " "
echo " START: Topup Field Map Generation and Gradient Unwarping"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

########################################## DO WORK ########################################## 

# PhaseOne and PhaseTwo are sets of SE EPI images with opposite phase encodes
${FSLDIR}/bin/imcp $PhaseEncodeOne ${WD}/PhaseOne.nii.gz
${FSLDIR}/bin/imcp $PhaseEncodeTwo ${WD}/PhaseTwo.nii.gz
${FSLDIR}/bin/imcp $ScoutInputName ${WD}/SBRef.nii.gz

# Apply gradient non-linearity distortion correction to input images (SE pair)
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
  ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${WD} \
      --coeffs=${GradientDistortionCoeffs} \
      --in=${WD}/PhaseOne \
      --out=${WD}/PhaseOne_gdc \
      --owarp=${WD}/PhaseOne_gdc_warp
  ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${WD} \
      --coeffs=${GradientDistortionCoeffs} \
      --in=${WD}/PhaseTwo \
      --out=${WD}/PhaseTwo_gdc \
      --owarp=${WD}/PhaseTwo_gdc_warp

  # Make a dilated mask in the distortion corrected space
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseOne -abs -bin -dilD ${WD}/PhaseOne_mask
  ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${WD}/PhaseOne_mask -r ${WD}/PhaseOne_mask -w ${WD}/PhaseOne_gdc_warp -o ${WD}/PhaseOne_mask_gdc
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseTwo -abs -bin -dilD ${WD}/PhaseTwo_mask
  ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${WD}/PhaseTwo_mask -r ${WD}/PhaseTwo_mask -w ${WD}/PhaseTwo_gdc_warp -o ${WD}/PhaseTwo_mask_gdc

  # Make a conservative (eroded) intersection of the two masks
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseOne_mask_gdc -mas ${WD}/PhaseTwo_mask_gdc -ero -bin ${WD}/Mask
  # Merge both sets of images
  ${FSLDIR}/bin/fslmerge -t ${WD}/BothPhases ${WD}/PhaseOne_gdc ${WD}/PhaseTwo_gdc
else 
  cp ${WD}/PhaseOne.nii.gz ${WD}/PhaseOne_gdc.nii.gz
  cp ${WD}/PhaseTwo.nii.gz ${WD}/PhaseTwo_gdc.nii.gz
  fslmerge -t ${WD}/BothPhases ${WD}/PhaseOne_gdc ${WD}/PhaseTwo_gdc
  fslmaths ${WD}/PhaseOne_gdc.nii.gz -mul 0 -add 1 ${WD}/Mask
fi


# Set up text files with all necessary parameters
txtfname=${WD}/acqparams.txt
if [ -e $txtfname ] ; then
  rm $txtfname
fi

dimtOne=`${FSLDIR}/bin/fslval ${WD}/PhaseOne dim4`
dimtTwo=`${FSLDIR}/bin/fslval ${WD}/PhaseTwo dim4`

echo "Total readout time for SE distortion images is $SE_RO_Time secs"

###   Populate the parameter file appropriately:   ###
source ${HCPPIPEDIR_Global}/get_params_from_json.shlib   #Get parameters from json file.
##  Phase One:  ##
PEDir=`read_header_param PhaseEncodingDirection ${PhaseEncodeOne%.nii*}.json`
PEDir="${PEDir%\"}"   # remove trailing quote (")
PEDir="${PEDir#\"}"   # remove leading quote (")
# The HCP Pipelines want x/y/z, rather than i/j/k:
if   [ $PEDir = "i"  ]; then PEDirOne="x";
elif [ $PEDir = "i-" ]; then PEDirOne="x-";
elif [ $PEDir = "j"  ]; then PEDirOne="y";
elif [ $PEDir = "j-" ]; then PEDirOne="y-";
elif [ $PEDir = "k"  ]; then PEDirOne="z";
elif [ $PEDir = "k-" ]; then PEDirOne="z-";
fi
# X direction phase encode
if [[ $PEDirOne = "x" ]] ; then
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "1 0 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# -X direction phase encode
elif [[ $PEDirOne = "x-" || $PEDirOne = "-x" ]] ; then
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "-1 0 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# Y direction phase encode
elif [[ $PEDirOne = "y" ]] ; then
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "0 1 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# -Y direction phase encode
elif [[ $PEDirOne = "y-" || $PEDirOne = "-y" ]] ; then
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "0 -1 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
fi

##  Phase Two:  ##
PEDir=`read_header_param PhaseEncodingDirection ${PhaseEncodeTwo%.nii*}.json`
PEDir="${PEDir%\"}"   # remove trailing quote (")
PEDir="${PEDir#\"}"   # remove leading quote (")
# The HCP Pipelines want x/y/z, rather than i/j/k:
if   [ $PEDir = "i"  ]; then PEDirTwo="x";
elif [ $PEDir = "i-" ]; then PEDirTwo="x-";
elif [ $PEDir = "j"  ]; then PEDirTwo="y";
elif [ $PEDir = "j-" ]; then PEDirTwo="y-";
elif [ $PEDir = "k"  ]; then PEDirTwo="z";
elif [ $PEDir = "k-" ]; then PEDirTwo="z-";
fi
# X direction phase encode
if [[ $PEDirTwo = "x" ]] ; then
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "1 0 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# -X direction phase encode
elif [[ $PEDirTwo = "x-" || $PEDirTwo = "-x" ]] ; then
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "-1 0 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# Y direction phase encode
elif [[ $PEDirTwo = "y" ]] ; then
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "0 1 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
# -Y direction phase encode
elif [[ $PEDirTwo = "y-" || $PEDirTwo = "-y" ]] ; then
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "0 -1 0 $SE_RO_Time" >> $txtfname
    i=`echo "$i + 1" | bc`
  done
fi

#Pad in Z by one slice if odd so that topup does not complain (slice consists of zeros that will be dilated by following step)
numslice=`fslval ${WD}/BothPhases dim3`
if [ ! $(($numslice % 2)) -eq "0" ] ; then
  echo "Padding Z by one slice"
  for Image in ${WD}/BothPhases ${WD}/Mask ; do
    fslroi ${Image} ${WD}/slice.nii.gz 0 -1 0 -1 0 1 0 -1
    fslmaths ${WD}/slice.nii.gz -mul 0 ${WD}/slice.nii.gz
    fslmerge -z ${Image} ${Image} ${WD}/slice.nii.gz
    rm ${WD}/slice.nii.gz
  done
fi

# Extrapolate the existing values beyond the mask (adding 1 just to avoid smoothing inside the mask)
${FSLDIR}/bin/fslmaths ${WD}/BothPhases -abs -add 1 -mas ${WD}/Mask -dilM -dilM -dilM -dilM -dilM ${WD}/BothPhases

# RUN TOPUP
# Needs FSL (version 5.0.6)

# TO-DO: if topup has been run for these images, do not run it again.
${FSLDIR}/bin/topup --imain=${WD}/BothPhases --datain=$txtfname --config=${TopupConfig} --out=${WD}/Coefficents --iout=${WD}/Magnitudes --fout=${WD}/TopupField --dfout=${WD}/WarpField --rbmout=${WD}/MotionMatrix --jacout=${WD}/Jacobian -v 

#Remove Z slice padding if needed
if [ ! $(($numslice % 2)) -eq "0" ] ; then
  echo "Removing Z slice padding"
  for Image in ${WD}/BothPhases ${WD}/Mask ${WD}/Coefficents_fieldcoef ${WD}/Magnitudes ${WD}/TopupField* ${WD}/WarpField* ${WD}/Jacobian* ; do
    fslroi ${Image} ${Image} 0 -1 0 -1 0 ${numslice} 0 -1
  done
fi

# The amount of distortion is proportional to the TotalReadoutTime, so if the
#   scout_TotalReadoutTime is different from the SE_TotalReadoutTime, scale it:
RO_time_scale=`echo "scale=9; ${scout_RO_Time} / ${SE_RO_Time}" | bc -l` 


###   UNWARP   ###
if [[ $UnwarpDir = $PEDirOne ]] ; then
  # select the first volume from PhaseOne
  VolumeNumber=$((0 + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
  # register scout to SE input (PhaseOne) + combine motion and distortion correction
  ${FSLDIR}/bin/flirt -dof 6 -interp spline -in ${WD}/SBRef.nii.gz -ref ${WD}/PhaseOne_gdc -omat ${WD}/SBRef2PhaseOne_gdc.mat -out ${WD}/SBRef2PhaseOne_gdc
  ${FSLDIR}/bin/convert_xfm -omat ${WD}/SBRef2WarpField.mat -concat ${WD}/MotionMatrix_${vnum}.mat ${WD}/SBRef2PhaseOne_gdc.mat
  # Scale the WarpField to correct for differences in the TotalReadoutTime between the SE- and the scout- images:
  ${FSLDIR}/bin/fslmaths ${WD}/WarpField_${vnum} -mul ${RO_time_scale} ${WD}/WarpField_${vnum}_scaled
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${WD}/PhaseOne_gdc --premat=${WD}/SBRef2WarpField.mat --warp1=${WD}/WarpField_${vnum}_scaled --out=${WD}/WarpField.nii.gz
  ${FSLDIR}/bin/imcp ${WD}/Jacobian_${vnum}.nii.gz ${WD}/Jacobian.nii.gz
  SBRefPhase=One
else
  # select the first volume from PhaseTwo
  VolumeNumber=$(($dimtOne + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
  # register scout to SE input (PhaseTwo) + combine motion and distortion correction
  ${FSLDIR}/bin/flirt -dof 6 -interp spline -in ${WD}/SBRef.nii.gz -ref ${WD}/PhaseTwo_gdc -omat ${WD}/SBRef2PhaseTwo_gdc.mat -out ${WD}/SBRef2PhaseTwo_gdc
  ${FSLDIR}/bin/convert_xfm -omat ${WD}/SBRef2WarpField.mat -concat ${WD}/MotionMatrix_${vnum}.mat ${WD}/SBRef2PhaseTwo_gdc.mat
  # TO-DO: scale to correct for differences in the TotalReadoutTime between the SE- and the scout- images:
  ${FSLDIR}/bin/fslmaths ${WD}/WarpField_${vnum} -mul ${RO_time_scale} ${WD}/WarpField_${vnum}_scaled
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${WD}/PhaseTwo_gdc --premat=${WD}/SBRef2WarpField.mat --warp1=${WD}/WarpField_${vnum}_scaled --out=${WD}/WarpField.nii.gz
  ${FSLDIR}/bin/imcp ${WD}/Jacobian_${vnum}.nii.gz ${WD}/Jacobian.nii.gz
  SBRefPhase=Two
fi

# PhaseTwo (first vol) - warp and Jacobian modulate to get distortion corrected output
VolumeNumber=$(($dimtOne + 1))
vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/PhaseTwo_gdc -r ${WD}/PhaseTwo_gdc --premat=${WD}/MotionMatrix_${vnum}.mat -w ${WD}/WarpField_${vnum} -o ${WD}/PhaseTwo_gdc_dc
${FSLDIR}/bin/fslmaths ${WD}/PhaseTwo_gdc_dc -mul ${WD}/Jacobian_${vnum} ${WD}/PhaseTwo_gdc_dc_jac
# PhaseOne (first vol) - warp and Jacobian modulate to get distortion corrected output
VolumeNumber=$((0 + 1))
vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/PhaseOne_gdc -r ${WD}/PhaseOne_gdc --premat=${WD}/MotionMatrix_${vnum}.mat -w ${WD}/WarpField_${vnum} -o ${WD}/PhaseOne_gdc_dc
${FSLDIR}/bin/fslmaths ${WD}/PhaseOne_gdc_dc -mul ${WD}/Jacobian_${vnum} ${WD}/PhaseOne_gdc_dc_jac

# Scout - warp and Jacobian modulate to get distortion corrected output
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/SBRef.nii.gz -r ${WD}/SBRef.nii.gz -w ${WD}/WarpField.nii.gz -o ${WD}/SBRef_dc.nii.gz
${FSLDIR}/bin/fslmaths ${WD}/SBRef_dc.nii.gz -mul ${WD}/Jacobian.nii.gz ${WD}/SBRef_dc_jac.nii.gz

# Calculate Equivalent Field Map
${FSLDIR}/bin/fslmaths ${WD}/TopupField -mul 6.2831853 ${WD}/TopupField
${FSLDIR}/bin/fslmaths ${WD}/Magnitudes.nii.gz -Tmean ${WD}/Magnitude.nii.gz
${FSLDIR}/bin/bet ${WD}/Magnitude ${WD}/Magnitude_brain -f 0.35 -m #Brain extract the magnitude image

# copy images to specified outputs
if [ ! -z ${DistortionCorrectionWarpFieldOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/WarpField.nii.gz ${DistortionCorrectionWarpFieldOutput}.nii.gz
fi
if [ ! -z ${JacobianOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Jacobian.nii.gz ${JacobianOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionFieldOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/TopupField.nii.gz ${DistortionCorrectionFieldOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionMagnitudeOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Magnitude.nii.gz ${DistortionCorrectionMagnitudeOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionMagnitudeBrainOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Magnitude_brain.nii.gz ${DistortionCorrectionMagnitudeBrainOutput}.nii.gz
fi

echo " "
echo " END: Topup Field Map Generation and Gradient Unwarping"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ########################################## 

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "# First, cd to the directory with this file is found." >> $WD/qa.txt
echo "" >> $WD/qa.txt
echo "# Inspect topup correction:" >> $WD/qa.txt
echo "fslview ./BothPhases ./Magnitudes ./Magnitude" >> $WD/qa.txt
echo "# Inspect results of various corrections (phase one)" >> $WD/qa.txt
echo "fslview ./PhaseOne ./PhaseOne_gdc ./PhaseOne_gdc_dc ./PhaseOne_gdc_dc_jac" >> $WD/qa.txt
echo "# Inspect results of various corrections (phase two)" >> $WD/qa.txt
echo "fslview ./PhaseTwo ./PhaseTwo_gdc ./PhaseTwo_gdc_dc ./PhaseTwo_gdc_dc_jac" >> $WD/qa.txt
echo "# Compare phases one and two" >> $WD/qa.txt
echo "fslview ./PhaseOne_gdc_dc ./PhaseTwo_gdc_dc ./PhaseOne_gdc_dc_jac ./PhaseTwo_gdc_dc_jac" >> $WD/qa.txt
echo "# Check linear registration of Scout to SE EPI" >> $WD/qa.txt
echo "fslview ./Phase${SBRefPhase}_gdc ./SBRef2Phase${SBRefPhase}_gdc" >> $WD/qa.txt
echo "# Inspect results of various corrections to scout" >> $WD/qa.txt
echo "fslview ./SBRef ./SBRef_dc ./SBRef_dc_jac" >> $WD/qa.txt
echo "# Visual check of warpfield and Jacobian" >> $WD/qa.txt
if [ ! -z "${DistortionCorrectionWarpFieldOutput}" ] ; then
  echo "fslview ../`basename ${DistortionCorrectionWarpFieldOutput}` ../`basename ${JacobianOutput}`" >> $WD/qa.txt
else
  echo "fslview ../`basename ${JacobianOutput}`" >> $WD/qa.txt
fi
##############################################################################################

