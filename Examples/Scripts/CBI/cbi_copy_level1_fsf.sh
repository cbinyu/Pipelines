#!/bin/bash 

#
# Author(s): Pablo Velasco (pablo dot velasco at nyu dot edu)
# Modified from copy_evs_into_results.sh, part of the HCP Pipelines
#

##  TO DO:  ##
# -> Can we just copy a template and modify it?
#

#
# Function description
#  Copy 1st-level 'fsf' files to be used by FEAT, for all the
#    tasks in a subject’s folder
#
usage() {
    local scriptName=$(basename ${0})
    echo ""
    echo " Usage ${scriptName} --studyfolder=<study-folder> --subject=<subject-id>"
    echo ""
    echo "   <study-folder> - folder in which study data resides in sub-folders named by subject ID"
    echo "   <subject-id>   - subject ID"
    echo ""
    echo " Functional runs for which to produce FSF files will be expected to be found at: "
    echo "   <study-folder>/<subject-id>/MNINonLinear/Results/"
    echo ""
    echo " Location of Level-1 files: "
    echo "   $HCPPIPEDIR/Examples/fsf_templates/"
    echo ""
    echo " EV files will be copied to: "
    echo "   <study-folder>/<subject-id>/MNINonLinear/Results/<task-name>/"

}

#
# Function description
#  Get the command line options for this script
#
# Global output variables
#  ${StudyFolder} - study folder
#  ${Subject} - subject ID
#
get_options() {
    local scriptName=$(basename ${0})
    local arguments=($@)

    # initialize global output variables
    unset StudyFolder
    unset Subject

    # parse arguments
    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
		argument=${arguments[index]}

		case ${argument} in
			--help)
				usage
				exit 1
				;;
			--studyfolder=*)
				StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--subject=*)
				Subject=${argument#*=}
				index=$(( index + 1 ))
				;;
			*)
				usage
				echo ""
				echo "ERROR: Unrecognized Option: ${argument}"
				echo ""
				exit 1
				;;
		esac
    done

    # check required parameters
    if [ -z ${StudyFolder} ]; then
		usage
		echo ""
		echo "ERROR: <study-folder> not specified"
		echo ""
		exit 1
    fi
	
    if [ -z ${Subject} ]; then
		usage
		echo ""
		echo "ERROR: <subject-id> not specified"
		echo ""
		exit 1
    fi
	
    # report
    echo ""
    echo "-- ${scriptName}: Specified command-line options - Start --"
    echo "   <study-folder>: ${StudyFolder}"
    echo "   <subject-id>: ${Subject}"
    echo "-- ${scriptName}: Specified command-line options - End --"
    echo ""
}

#
# Get functional runs
#  Check folders in ${StudyFolder}/${Subject}/MNINonLinear/Results/
#    and keep the ones with a PE specification at the end of the
#    run name
#
get_functional_runs() {
    funcRuns=""
    for r in `ls $baseDir`; do
	r=${r%/}        # remove trailing "/" (if present)

	# remove trailing _LR, _RL, _AP or _PA:
	r_base=${r%_LR}
	r_base=${r_base%_RL}
	r_base=${r_base%_AP}
	r_base=${r_base%_PA}

	if [ "$r_base" != "$r" ]; then
	    # "r" is a first-level folder ( _RL or _LR)
            # add "r" to the list of funcRuns if not already there:
	    if [[ $funcRuns != *$r* ]]; then
		funcRuns=" $funcRuns $r"
	    fi
	fi
    done
}

#
# Main processing
#
main() {
    get_options $@

    baseDir=${StudyFolder}/${Subject}/MNINonLinear/Results/

    get_functional_runs

    # folder with the original fsf files:
    origDir=$HCPPIPEDIR/Examples/fsf_templates

    if [ -d "${origDir}" ]; then
        
        echo ""
        echo "Copying 1st-level fsf files for: "
        echo ""

        # loop through the functional runs:
        for taskname in $funcRuns; do

            echo "  ${taskname}"

            # copy file:
            fsf_file=${origDir}/${taskname}_hp200_s4_level1.fsf
            if [ -f "$fsf_file" ]; then
                cp -v ${fsf_file} ${baseDir}/${taskname}/
            else
                echo "   File not found: ${fsf_file}"
            fi

        done

        echo ""

    else
        echo "   Folder not found: ${origDir}"
    fi
}

# Invoke the main function
main $@
