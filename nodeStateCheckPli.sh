#!/bin/bash

SLACK_WEBHOOK_URL="YOUR_WEBHOOK_URL"
POLLING_INTERVAL=60

HOST_NAME=$(hostname -f)
IP_ADDRESS=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
MONITOR_NAME="${HOST_NAME}"_"${IP_ADDRESS}"
PLI_LOG_FILE=$HOME/.pm2/logs/NodeStartPM2-error.log

#---------------------------------------------
#  Post to Slack
#  $1 : text -> host_name
#  $2 : pretext -> job_name
#  $3 : color -> good/warning/danger
#  $4 : title -> detection type
#  $5 : text -> Job Spec ID
#  $6 : footer -> Detection date and time
#---------------------------------------------
post_to_slack(){
    MES_SLACK=$(jq -n --arg arg1 "$1" --arg arg2 "$2" --arg arg3 "$3" --arg arg4 "$4" --arg arg5 "$5" --arg arg6 "$6" '.text=$arg1 |.attachments[0].pretext=$arg2 | .attachments[0].color=$arg3 | .attachments[0].title=$arg4 | .attachments[0].text=$arg5 | .attachments[0].footer=$arg6 | .attachments[0].footer_icon="https://www.goplugin.co/assets/images/logo.png"')
    curl -X POST -H 'Content-type: application/json' --data "$MES_SLACK" $SLACK_WEBHOOK_URL 2> /dev/null
}

while true; do
    exe_date=$(date +"%Y-%m-%d %T")
    dsp_date=$(date -d"${exe_date}" +"%Y-%m-%dT%T")
    cur_line=$(wc -l ${PLI_LOG_FILE} | awk '{print $1}')
    if [ "${pre_line}" = "" ]; then
        pre_line=${cur_line}
        pre_date="${exe_date}"
        post_to_slack "${dsp_date=$} : $MONITOR_NAME" "" "good" "PLI-NodeState Check Start" "${exe_date}"
    fi
    if [ $(( pre_line )) -gt $(( cur_line )) ]; then
        #Supports log rotation
        pre_line=1
    fi

    # get "nodeStates" JSON Data from log "YYYY-MM-DDThh:mi:ss.nnnZ [ERROR] *nodeStates=[*]*"
    error=$(tail -n +"${pre_line}" ${PLI_LOG_FILE} | \
      grep -e '\[ERROR\]' | grep --line-buffered -o 'nodeStates=.*}]' | cut -c 12- | \
      jq -c '.[]|select(contains({State: "Alive"})|not)' | \
      sed 's/(primary)//g' | sort | uniq | jq -r '"[" + .State + "] " + .Node' | cut -d ':' -f 1)

    if [ "${error}" != "${pre_error}" ]; then
        if [ "${error}" = "" ]; then
            echo "${exe_date} : All Alive"
            post_to_slack "${dsp_date} : $MONITOR_NAME" "PLI-NodeState" "good" "EVM.Nodes changed State" "All Alive" "${exe_date}"
        else
            echo "${exe_date} : ${error}"
            post_to_slack "${dsp_date} : $MONITOR_NAME" "PLI-NodeState" "danger" "EVM.Nodes changed State" "${error}" "${exe_date}"
        fi
    fi

    pre_error=${error}
    pre_line=${cur_line}
    sleep ${POLLING_INTERVAL}
done
