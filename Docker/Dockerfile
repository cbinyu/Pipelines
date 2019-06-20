###########################################################
# This is the Dockerfile to build a machine that runs the #
# HCP Pipelines first public release (v.3.4) on data      #
# organized in a BIDS-compliant directory structure.  It  #
# includes all the required dependencies at the latest    #
# versions: (https://github.com/Washington-University/    #
#Pipelines/blob/v3.4.0/README.md                          #
# -FSL                  v.5.0.6                           #
# -FreeSurfer           v.5.3.0-HCP                       #
# -Connectome Workbench v.1.0                             #
# -HCP gradunwarp       v.1.0.2                           #
#							  #
# Notes:						  #
# 1. The FreeSurfer license file is NOT distributed here. #
# To be able to run FS, a link has been created pointing  #
# to /usr/local/etc/pipelines/FS_license.txt.  You need   #
# to place the FS license file in a folder in the host    #
# machine, name it FS_license.txt and make sure it is     #
# world readable.  Then, when you run the Docker image,   #
# mount that folder as /usr/local/etc/pipelines.          #
# E.g:							  #
#   docker run -v /my/host/folder:/usr/local/etc/pipelines ...
#
# 2. The gradient coil coefficients file is also NOT      #
# distributed here.  This file is not required to run the #
# pipelines.  However, if you want to do the gradient non-#
# linearity correction, you need it. For that purpose, a  #
# link has been created pointing to                       #
# /usr/local/etc/pipelines/coeff.grad                     #
# You need to place the gradients coefficients file in    #
# the same folder in the host machine, that you placed    #
# FS_license.txt, name it coeff.grad and make sure it is  #
# world readable.  Then, when you run the Docker image,   #
# mount that folder as /usr/local/etc/pipelines.          #
# E.g:							  #
#   docker run -v /my/host/folder:/usr/local/etc/pipelines ...
###########################################################


###   Start with CentOS 6.9 image   ###
FROM centos:centos6.9

# Add EPEL as a repo for yum:
RUN rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm

# Specify where to install packages:
ENV INSTALL_FOLDER=/usr/local/

###   Install FSL   ###

# Install FSL 5.0.6:
# "fslinstaller.py" only works for python 2.X.
# So just download the source code for 5.0.6:
# Note: fsl uses 'bc', and also 'numpy'
RUN yum -y update \
    && yum install -y tar unzip bc numpy\
    && yum clean all \
    && curl -sSL https://fsl.fmrib.ox.ac.uk/fsldownloads/oldversions/fsl-5.0.6-centos6_64.tar.gz | tar xz -C ${INSTALL_FOLDER} \
    --exclude='fsl/doc' \
    --exclude='fsl/data/first' \    
    --exclude='fsl/data/atlases' \
    --exclude='fsl/data/possum' \    
    --exclude='fsl/src' \    
    --exclude='fsl/extras/src' \    
    --exclude='fsl/bin/fslview*' \
#    # Note: ${INSTALL_FOLDER}/fsl/data/standard is needed for functional processing \
    && yum clean all


# Configure environment
ENV FSLDIR=${INSTALL_FOLDER}/fsl/ \
    FSLOUTPUTTYPE=NIFTI_GZ
# (Note: the following cannot be included in the same one-line with
#        the above, since it depends on the previous variables)
ENV PATH=${FSLDIR}/bin:$PATH \
    LD_LIBRARY_PATH=${FSLDIR}:${LD_LIBRARY_PATH}


###   Install FreeSurfer   ###

# Install dependencies for FS
RUN yum -y update \
    && yum install -y tcsh libgomp perl netcdf libGLU libXmu \
    && yum clean all

# Download FS_v5.3.0 for HCP from the official repo and untar to ${INSTALL_FOLDER}:
# Note: I'm getting rid of 'lib/cuda' and 'bin/*_cuda' because it requires specific cuda
#       libraries, which I don't want to install for now.
ENV FREESURFER_HOME=${INSTALL_FOLDER}/freesurfer
RUN curl -sSL ftp://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/5.3.0-HCP/freesurfer-Linux-centos6_x86_64-stable-pub-v5.3.0-HCP.tar.gz | tar xz -C ${INSTALL_FOLDER} \
    --exclude='freesurfer/trctrain' \
    --exclude='freesurfer/subjects/fsaverage_sym' \
    --exclude='freesurfer/subjects/fsaverage?' \
    --exclude='freesurfer/subjects/cvs_avg35*' \
    --exclude='freesurfer/subjects/bert' \
    --exclude='freesurfer/subjects/V1_average' \
    --exclude='freesurfer/subjects/sample-00?.mgz' \
    --exclude='freesurfer/average/mult-comp-cor' \
    --exclude='freesurfer/lib/cuda' \
    --exclude='freesurfer/bin/*_cuda' \
    --exclude='freesurfer/lib/qt'

# Configure license 
# (Note: FS_license is not distributed here. See note in header.)
# Create link to license file in a host folder which will be mounted
#   at run time:
RUN ln -s /usr/local/etc/pipelines/FS_license.txt ${FREESURFER_HOME}/license.txt

# Configure basic freesurfer ENV:
ENV OS=Linux \
    FS_OVERRIDE=0 \
    FIX_VERTEX_AREA=  \
    FSF_OUTPUT_FORMAT=nii.gz \
    MNI_DIR=${FREESURFER_HOME}/mni \
    LOCAL_DIR=${FREESURFER_HOME}/local \
    FSFAST_HOME=${FREESURFER_HOME}/fsfast \
    FMRI_ANALYSIS_DIR=${FREESURFER_HOME}/fsfast
# (Note: the following cannot be included in the same one-line with
#        the above, since it depends on the previous variables)
ENV MINC_BIN_DIR=${MNI_DIR}/bin \
    MINC_LIB_DIR=${MNI_DIR}/lib \
    MNI_DATAPATH=${MNI_DIR}/data \
    PERL5LIB=${MNI_DIR}/lib/perl5/5.8.5 \
    MNI_PERL5LIB=${MNI_DIR}/lib/perl5/5.8.5 \
    PATH=${FREESURFER_HOME}/bin:${FREESURFER_HOME}/fsfast/bin:${FREESURFER_HOME}/tktools:${FREESURFER_HOME}/mni/bin:${PATH} \
    # Number of cores to use for FS commands: \
    NSLOTS=20


###   Install HCP Workbench   ###

# Install HCP Workbench v.1.0 from the official repo:
RUN curl -sS https://ftp.humanconnectome.org/workbench/workbench-rh_linux64-v1.0.zip > /tmp/wb_file.zip \
    && unzip /tmp/wb_file.zip -d ${INSTALL_FOLDER} \
    && rm /tmp/wb_file.zip


###   Install HCP Grad-Unwarp   ###

# Install Python 2.7.
# In Centos 6.9, you need to install CentOS Software Collections Repository
RUN yum -y update \
    && yum install -y centos-release-scl \
    && yum install -y python27 python-pip \     # you need to run this as a separte command from the above \
    && yum clean all
RUN scl enable python27 'pip install numpy==1.16.2 scipy==1.2.1 nibabel==2.3.3'

# Install HCP's version of 'gradunwarp' (v.1.0.3) from github:
ENV GRADUNWARP_VERSION=v1.1.0
RUN yum -y update \
    && yum install -y gcc \
    && yum clean all
RUN curl -sSL https://github.com/Washington-University/gradunwarp/archive/${GRADUNWARP_VERSION}.tar.gz \
        | tar xz -C ${INSTALL_FOLDER} \
    && cd ${INSTALL_FOLDER}/gradunwarp-${GRADUNWARP_VERSION#v} \
    && scl enable python27 'python setup.py install'


###   Install HCP Pipelines   ###

# Install packages needed for the pipelines (and wget):
RUN yum -y update \
    && yum install -y freetype libpng libSM libXrender fontconfig libXext \
    && yum clean all

# Install HCP Pipelines, branch 'v3.4', from github, and get folder where it is installed.
ENV HCPPIPEDIR=${INSTALL_FOLDER}/Pipelines
RUN mkdir ${HCPPIPEDIR} \
    && curl -sSL https://github.com/cbinyu/Pipelines/archive/v3.4.tar.gz \
        | tar -vxz -C ${HCPPIPEDIR} --strip-components=1

# Configure Gradient Coefficients file: 
# (Note: The Gradient Coefficients file is not distributed here. See note in header.)
# Create link to Gradient Coefficients file in a host folder which will be mounted
#   at run time:
RUN ln -s /usr/local/etc/pipelines/coeff.grad ${HCPPIPEDIR}/global/config/coeff.grad

WORKDIR	 /tmp





###########

###   Modify some batches to run them in parallel   ###

# GenericfMRIVolumeProcessingPipelineBatch.sh: 
    # (Append "&" to the end of lines including "--mctype=${MCType}"):
    # (Note that ${HCPPIPEDIR} is not defined for this layer!)
#RUN sed -i 's|--mctype=\${MCType}|& \&|' ${INSTALL_FOLDER}/*/Examples/Scripts/GenericfMRIVolumeProcessingPipelineBatch.sh



# Set up the HCP Pipeline environment:
# If you need to modify the SetUp file:
#ENV SETUPFILE=${HCPPIPEDIR}/Examples/Scripts/SetUpHCPPipeline.sh
#RUN sed -i 's/export HCPPIPEDIR=${HOME}\/projects\/Pipelines//' $SETUPFILE \
#    && sed -i 's/export CARET7DIR=${HOME}\/workbench\/bin_linux64/export CARET7DIR=${INSTALL_FOLDER}\/workbench\/bin_rh_linux64/' $SETUPFILE \
#    && echo "source ${SETUPFILE}" >> /root/.bashrc
# Configure bashrc to source FreeSurferEnv.sh
#RUN /bin/bash -c ' echo -e "source $FREESURFER_HOME/FreeSurferEnv.sh &>/dev/null" >> /root/.bashrc '



####   Modify fsl_sub to run single machine multi-core   ###
#
## Keep a copy of the original, and get new version from GitHub:
#RUN mv ${FSLDIR}/bin/fsl_sub ${FSLDIR}/bin/fsl_sub_orig \
#    && curl -sSL https://raw.githubusercontent.com/neurolabusc/fsl_sub/master/fsl_sub -o ${FSLDIR}/bin/fsl_sub \
#    && chmod +x ${FSLDIR}/bin/fsl_sub
#
## Modify environment to tell it how many cores to use:
#ENV FSLPARALLEL=20


# Potential folders to clean:
