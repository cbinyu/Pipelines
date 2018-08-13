#!/bin/bash 

#
# Author(s): Pablo Velasco (pablo dot velasco at nyu dot edu)
# Modified from copy_evs_into_results.sh, part of the HCP Pipelines
#

##  TO DO:  ##
# -> 
#

#
# Function description
#  Copy E-Prime EV files to be used by FEAT, for all the
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
    echo " EV files are expected in folders: "
    echo "   <study-folder>/<subject-id>/unprocessed/3T/<task-name>/LINKED_DATA/EPRIME/EVs/"
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
    baseDir=${StudyFolder}/${Subject}/MNINonLinear/Results/
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

    get_functional_runs

    # folder with the original data (and ancillary files)
    origDir=${StudyFolder}/${Subject}/unprocessed/3T

    echo "Copying EV files for: "

    # loop through the functional runs:
    for taskname in $funcRuns; do

        # figure out where the EVs directory to copy is
        evs_dir=${origDir}/${taskname}/LINKED_DATA/EPRIME/EVs

        # figure out where a copy of the EVs file should go
        dest_dir=${baseDir}/${taskname}

        echo "  ${taskname}"

        # copy files
        if [ -d "${evs_dir}" ]; then
            cp -rv ${evs_dir} ${dest_dir}
        else
            echo "   Folder not found: ${evs_dir}"
        fi

    done

    echo ""
}

# Invoke the main function
main $@
