#!/bin/bash

#********************************************************************************
# Copyright 2014 IBM
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#********************************************************************************

#############
# Colors    #
#############
export green='\e[0;32m'
export red='\e[0;31m'
export label_color='\e[0;33m'
export no_color='\e[0m' # No Color

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}

set +e
set +x 





function dra_commands {
    echo -e "${no_color}"
    dra_grunt_command=""
    
    if [ -n "$1" ] && [ "$1" != " " ]; then
        debugme echo "Event: '$1' is defined and not empty"
        
        dra_grunt_command="grunt --gruntfile=node_modules/grunt-idra3/idra.js -tool=$1"
        
        debugme echo -e "\tdra_grunt_command: $dra_grunt_command"
        
        if [ -n "$2" ] && [ "$2" != " " ]; then
            debugme echo -e "\ttestResult: '$2' is defined and not empty"
            
            dra_grunt_command="$dra_grunt_command -testResult=$2"
        
            debugme echo -e "\t\tdra_grunt_command: $dra_grunt_command"
            
        else
            debugme echo -e "testResult: '$2' is not defined or is empty"
            debugme echo -e "${no_color}"
        fi
        
        debugme echo -e "FINAL dra_grunt_command: $dra_grunt_command"
        debugme echo -e "${no_color}"
        
        
        eval "$dra_grunt_command --no-color"
        GRUNT_RESULT=$?
        
        debugme echo "GRUNT_RESULT: $GRUNT_RESULT"
        
        if [ $GRUNT_RESULT -ne 0 ] && [ "${DRA_ADVISORY_MODE}" == "false" ]; then
            exit 1
        fi
    else
        debugme echo "Event: '$1' is not defined or is empty"
    fi
    
    echo -e "${no_color}"
}





if [ -z "$TOOLCHAIN_TOKEN" ]; then
    export CF_TOKEN=$(sed -e 's/^.*"AccessToken":"\([^"]*\)".*$/\1/' ~/.cf/config.json)
else
    export CF_TOKEN=$TOOLCHAIN_TOKEN
fi


OUTPUT_FILE='draserver.txt'
${EXT_DIR}/dra-check.py ${PIPELINE_TOOLCHAIN_ID} "${CF_TOKEN}" "${IDS_PROJECT_NAME}" "${OUTPUT_FILE}"
RESULT=$?

#0 = DRA is present
#1 = DRA not present or there was an error with the http call (err msg will show)
#echo $RESULT

if [ $RESULT -eq 0 ]; then
    debugme echo "DRA is present";
    
    echo -e "${green}"
    echo "**********************************************************************"
    echo "Deployment Risk Analytics (DRA) is active."
    echo "**********************************************************************"
    echo -e "${no_color}"
    
    #
    # Retrieve variables from toolchain API
    #
    DRA_CHECK_OUTPUT=`cat ${OUTPUT_FILE}`
    IFS=$'\n' read -rd '' -a dradataarray <<< "$DRA_CHECK_OUTPUT"
    export CF_ORGANIZATION_ID=${dradataarray[0]}
    export DRA_SERVER=${dradataarray[1]}
    rm ${OUTPUT_FILE}
    
    #
    # Hardcoded until brokers are updated (DRA) and created (DLMS)
    #
    export DLMS_SERVER=http://devops-datastore.stage1.mybluemix.net
    export DRA_SERVER=https://dra3.stage1.mybluemix.net
    
    npm install grunt-idra3

    debugme echo "DRA_SERVER: ${DRA_SERVER}"
fi







npm install grunt
npm install grunt-cli


custom_cmd

echo -e "${no_color}"

debugme echo "DRA_ADVISORY_MODE: ${DRA_ADVISORY_MODE}"
debugme echo "DRA_TEST_TOOL_SELECT: ${DRA_TEST_TOOL_SELECT}"
debugme echo "DRA_TEST_LOG_FILE: ${DRA_TEST_LOG_FILE}"
debugme echo "DRA_MINIMUM_SUCCESS_RATE: ${DRA_MINIMUM_SUCCESS_RATE}"
debugme echo "DRA_CHECK_TEST_REGRESSION: ${DRA_CHECK_TEST_REGRESSION}"

debugme echo "DRA_CRITICAL_TESTCASES: ${DRA_CRITICAL_TESTCASES}"
debugme echo -e "${no_color}"







#0 = DRA is present
#1 = DRA not present or there was an error with the http call (err msg will show)
#echo $RESULT

if [ $RESULT -eq 0 ]; then
    debugme echo "DRA is present";
    
    
    criteriaList=()


    if [ -n "${DRA_TEST_TOOL_SELECT}" ] && [ "${DRA_TEST_TOOL_SELECT}" != "none" ] && \
        [ -n "${DRA_TEST_LOG_FILE}" ] && [ "${DRA_TEST_LOG_FILE}" != " " ]; then

        dra_commands "${DRA_TEST_TOOL_SELECT}" "${DRA_TEST_LOG_FILE}"

        if [ -n "${DRA_MINIMUM_SUCCESS_RATE}" ] && [ "${DRA_MINIMUM_SUCCESS_RATE}" != " " ]; then
            name="At least ${DRA_MINIMUM_SUCCESS_RATE}% success in tests (${DRA_TEST_TOOL_SELECT})"
            criteria="{ \"name\": \"$name\", \"conditions\": [ { \"eval\": \"_jUnitTestSuccessPercentage\", \"op\": \">=\", \"value\": ${DRA_MINIMUM_SUCCESS_RATE} } ] }"

            #echo "criteria:  $criteria"
            criteriaList=("${criteriaList[@]}" "$criteria")
        fi

        if [ -n "${DRA_CHECK_TEST_REGRESSION}" ] && [ "${DRA_CHECK_TEST_REGRESSION}" == "true" ]; then
            name="No regression in tests (${DRA_TEST_TOOL_SELECT})"
            criteria="{ \"name\": \"$name\", \"conditions\": [ { \"eval\": \"_hasJUnitTestRegressed\", \"op\": \"=\", \"value\": false } ] }"

            #echo "criteria:  $criteria"
            criteriaList=("${criteriaList[@]}" "$criteria")
        fi

        if [ -n "${DRA_CRITICAL_TESTCASES}" ] && [ "${DRA_CRITICAL_TESTCASES}" != " " ]; then
            name="No critical test failures (${DRA_TEST_TOOL_SELECT})"
            criteria="{ \"name\": \"$name\", \"conditions\": [ { \"eval\": \"_hasJUnitCriticalTestsPassed(${DRA_CRITICAL_TESTCASES})\", \"op\": \"=\", \"value\": true } ] }"

            #echo "criteria:  $criteria"
            criteriaList=("${criteriaList[@]}" "$criteria")
        fi
    fi









    if [ ${#criteriaList[@]} -gt 0 ]; then
        
        mode=""
        
        if [ "${DRA_ADVISORY_MODE}" == "false" ]; then
            mode="decision"
        else
            mode="advisory"
        fi
        
        criteria="{ \"name\": \"DynamicCriteria\", \"mode\": \"$mode\", \"rules\": [ "

        for i in "${criteriaList[@]}"
        do
            criteria="$criteria $i,"
        done


        criteria="${criteria%?}"
        criteria="$criteria ] }"


        echo $criteria > dynamicCriteria.json

        debugme echo "Dynamic Criteria:"
        debugme cat dynamicCriteria.json
        debugme echo ""
        debugme echo "CF_ORGANIZATION_ID: $CF_ORGANIZATION_ID"
        debugme echo "PIPELINE_INITIAL_STAGE_EXECUTION_ID: $PIPELINE_INITIAL_STAGE_EXECUTION_ID"


        echo -e "${no_color}"
        grunt --gruntfile=node_modules/grunt-idra3/idra.js -decision=dynamic -criteriafile=dynamicCriteria.json --no-color
        DECISION_RESULT=$?
        echo -e "${no_color}"
        debugme echo "DECISION_RESULT: $DECISION_RESULT"
        
        return $DECISION_RESULT
    fi
else
    debugme echo "DRA is not present";
fi    