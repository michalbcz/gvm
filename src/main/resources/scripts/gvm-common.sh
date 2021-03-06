#!/bin/bash

#
#   Copyright 2012 Marco Vermeulen
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#


#
# common internal function definitions
#

function __gvmtool_check_candidate_present {
	if [ -z "$1" ]; then
		echo -e "\nNo candidate provided."
		__gvmtool_help
		return 1
	fi
}

function __gvmtool_check_version_present {
	if [ -z "$1" ]; then
		echo -e "\nNo candidate version provided."
		__gvmtool_help
		return 1
	fi
}

function __gvmtool_determine_version {
	if [[ "${GVM_ONLINE}" == "false" && -n "$1" && -d "${GVM_DIR}/${CANDIDATE}/$1" ]]; then
		VERSION="$1"

	elif [[ "${GVM_ONLINE}" == "false" && -z "$1" && -L "${GVM_DIR}/${CANDIDATE}/current" ]]; then
		VERSION=$(readlink "${GVM_DIR}/${CANDIDATE}/current" | sed -e "s!${GVM_DIR}/${CANDIDATE}/!!g")

	elif [[ "${GVM_ONLINE}" == "false" && -n "$1" ]]; then
		echo "Stop! ${CANDIDATE} ${1} is not available in aeroplane mode."
		return 1

	elif [[ "${GVM_ONLINE}" == "false" && -z "$1" ]]; then
        echo "${OFFLINE_MESSAGE}"
        return 1

	elif [[ "${GVM_ONLINE}" == "true" && -z "$1" ]]; then
		VERSION=$(curl -s "${GVM_SERVICE}/candidates/${CANDIDATE}/default")

	else
		VERSION_VALID=$(curl -s "${GVM_SERVICE}/candidates/${CANDIDATE}/$1")
		if [[ ${VERSION_VALID} == 'valid' ]]; then
			VERSION="$1"
		else
			echo ""
			echo "Stop! $1 is not a valid ${CANDIDATE} version."
			return 1
		fi
	fi
}

function __gvmtool_build_version_csv {
	CANDIDATE="$1"
	CSV=""
	for version in $(ls -1 "${GVM_DIR}/${CANDIDATE}"); do
		if [ ${version} != 'current' ]; then
			CSV="${version},${CSV}"
		fi
	done
	CSV=${CSV%?}
}

function __gvmtool_determine_current_version {
	unset CURRENT
	CANDIDATE="$1"

	if [[ -n ${isolated_mode} && ${isolated_mode} == 1 ]]; then
		CURRENT=$(echo $PATH | sed -E "s|.gvm/${CANDIDATE}/([^/]+)/bin|!!\1!!|1" | sed -E "s|^.*!!(.+)!!.*$|\1|g")

		if [[ "${CURRENT}" == "current" ]]; then
		    unset CURRENT
		fi
	fi

	if [[ -z ${CURRENT} ]]; then
		CURRENT=$(readlink "${GVM_DIR}/${CANDIDATE}/current" | sed -e "s!${GVM_DIR}/${CANDIDATE}/!!g")
	fi
}

function __gvmtool_download {
	CANDIDATE="$1"
	VERSION="$2"
	mkdir -p "${GVM_DIR}/archives"
	if [ ! -f "${GVM_DIR}/archives/${CANDIDATE}-${VERSION}.zip" ]; then
		echo ""
		echo "Downloading: ${CANDIDATE} ${VERSION}"
		echo ""
		DOWNLOAD_URL="${GVM_SERVICE}/download/${CANDIDATE}/${VERSION}?platform=${GVM_PLATFORM}"
		ZIP_ARCHIVE="${GVM_DIR}/archives/${CANDIDATE}-${VERSION}.zip"
		curl -L "${DOWNLOAD_URL}" > "${ZIP_ARCHIVE}"
		__gvmtool_validate_zip "${ZIP_ARCHIVE}" || return 1
	else
		echo ""
		echo "Found a previously downloaded ${CANDIDATE} ${VERSION} archive. Not downloading it again..."
		__gvmtool_validate_zip "${GVM_DIR}/archives/${CANDIDATE}-${VERSION}.zip" || return 1
	fi
	echo ""
}

function __gvmtool_validate_zip {
	ZIP_ARCHIVE="$1"
	ZIP_OK=$(unzip -t "${ZIP_ARCHIVE}" | grep 'No errors detected in compressed data')
	if [ -z "${ZIP_OK}" ]; then
		rm "${ZIP_ARCHIVE}"
		echo ""
		echo "Stop! The archive was corrupt and has been removed! Please try installing again."
		return 1
	fi
}

function __gvmtool_default_environment_variables {
	if [ ! "${GVM_SERVICE}" ]; then
		GVM_SERVICE="http://localhost:8080"
	fi

	if [ ! "${GVM_DIR}" ]; then
		GVM_DIR="$HOME/.gvm"
	fi
}

function __gvmtool_check_upgrade_available {
	UPGRADE_AVAILABLE=""
	UPGRADE_NOTICE=$(echo "${BROADCAST_LIVE}" | grep 'Your version of GVM is out of date!')
	if [[ -n "${UPGRADE_NOTICE}" && ( "${COMMAND}" != 'selfupdate' ) ]]; then
		UPGRADE_AVAILABLE="true"
	fi
}

function __gvmtool_update_broadcast {
	COMMAND="$1"
	BROADCAST_FILE="${GVM_DIR}/var/broadcast"
	if [ -f "${BROADCAST_FILE}" ]; then
		BROADCAST_HIST=$(cat "${BROADCAST_FILE}")
	fi

	if [[ "${GVM_ONLINE}" == "true" && ( "${BROADCAST_LIVE}" != "${BROADCAST_HIST}" ) && ( "${COMMAND}" != 'broadcast' ) ]]; then
		mkdir -p "${GVM_DIR}/var"
		echo "${BROADCAST_LIVE}" > "${BROADCAST_FILE}"
		echo "${BROADCAST_LIVE}"
	fi
}

function __gvmtool_link_candidate_version {
	CANDIDATE="$1"
	VERSION="$2"

	# Change the 'current' symlink for the candidate, hence affecting all shells.
	if [ -L "${GVM_DIR}/${CANDIDATE}/current" ]; then
		unlink "${GVM_DIR}/${CANDIDATE}/current"
	fi
	ln -s "${GVM_DIR}/${CANDIDATE}/${VERSION}" "${GVM_DIR}/${CANDIDATE}/current"
}

function __gvmtool_install_candidate_version {
	CANDIDATE="$1"
	VERSION="$2"
	__gvmtool_download "${CANDIDATE}" "${VERSION}" || return 1
	echo "Installing: ${CANDIDATE} ${VERSION}"

	mkdir -p "${GVM_DIR}/${CANDIDATE}"

	unzip -oq "${GVM_DIR}/archives/${CANDIDATE}-${VERSION}.zip" -d "${GVM_DIR}/tmp/"
	mv ${GVM_DIR}/tmp/*-${VERSION} "${GVM_DIR}/${CANDIDATE}/${VERSION}"
	echo "Done installing!"
	echo ""
}

function __gvmtool_offline_list {
	echo "------------------------------------------------------------"
	echo "Aeroplane Mode: only showing installed ${CANDIDATE} versions"
	echo "------------------------------------------------------------"
	echo "                                                            "

	gvm_versions=($(echo ${CSV//,/ }))
	for (( i=0 ; i <= ${#gvm_versions} ; i++ )); do
		if [[ -n "${gvm_versions[${i}]}" ]]; then
			if [[ "${gvm_versions[${i}]}" == "${CURRENT}" ]]; then
				echo -e " > ${gvm_versions[${i}]}"
			else
				echo -e " * ${gvm_versions[${i}]}"
			fi
		fi
	done

	if [[ -z "${gvm_versions[@]}" ]]; then
		echo "   None installed!"
	fi

	echo "------------------------------------------------------------"
	echo "* - installed                                               "
	echo "> - currently in use                                        "
	echo "------------------------------------------------------------"

	unset CSV gvm_versions
}
