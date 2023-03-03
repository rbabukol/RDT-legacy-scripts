
#!/bin/bash

clean_up()
{
	echo ""
	echo "Clean up"
	killall pqos &> /dev/null 
	killall stress &> /dev/null 
	pqos -r -t0 &> /dev/null &
	rm -fr temp1
}

check_min_value()
{
	VALUE=$1
	THRESH=$2
	PRETXT=$3
	POSTTXT=$4
	if (( $(echo "$VALUE < $THRESH" | bc -l) )); then
		echo "Error - expected a minimum $PRETXT $THRESH $POSTTXT, but recorded $VALUE"
		clean_up
		exit 1
	fi
}

check_max_value()
{
	VALUE=$1
	THRESH=$2
	PRETXT=$3
	POSTTXT=$4
	if (( $(echo "$VALUE > $THRESH" | bc -l) )); then
		echo "Error - expected a maximum $PRETXT $THRESH $POSTTXT, but recorded $VALUE"
		clean_up
		exit 1
	fi
}

confirm_pqos_quiescent_state_from_log()
{
LOG_FILE_NAME=$1
THRESH=10
SAMPLES=$(($THRESH + 1))
echo "Check the last $SAMPLES samples"
NUM_SAMPLES=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | wc -l`
check_min_value $NUM_SAMPLES $SAMPLES "" "samples"

TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $2; n++ } END { if (n > 0) print sum / n; }'`
echo "Average IPC = " $TEMP
check_max_value $TEMP 1 "average IPC value of"
TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $3; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MISSES = " $TEMP "k"
check_max_value $TEMP 20 "average" "k MISSES"
#TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
#echo "Average LLC = " $TEMP
#check_max_value $TEMP 10000 "average" "LLC"
TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL = " $TEMP
check_max_value $TEMP 1 "average" "MBL"
TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBR = " $TEMP
check_max_value $TEMP 1 "average" "MBR"
}

killall stress &> /dev/null
echo " ------------------------------ "
echo "Restore default monitoring and capture baseline monitoring on cores 12-23 for 15s"
pqos -r -t 2 &> /dev/null
rm -fr temp1
pqos -m "all: [12-23]" -o temp1 -t 1000 &> /dev/null &
sleep 13s
echo " ------------------------------ "
echo "Confirm only cores 12-23 are in the monitoring output..."
TEMP=`grep -v "CORE" temp1 | grep -v "TIME" | awk '{print $1}' | sort -u | grep -E "^12-23$" -c`
if [ $TEMP -ne 1 ]; then 
	echo "Error - unexpected output in pqos monitoring data"
	clean_up
	exit 1
fi
echo "...confirmed"
echo " ------------------------------ "
confirm_pqos_quiescent_state_from_log "temp1"
echo "Default monitoring restored"
echo " ------------------------------ "
echo "Start stress instance on cores 12-23 to load memory and cpu usage"
echo "Sleep 2s"
taskset -c 12-23 stress -m 100 -c 100 &> /dev/null &
sleep 2s
echo " ------------------------------ "
SAMPLE_TIME=10
echo "Confirm RDT monitoring for cores 12-23 reflects cpu/mem activity for $SAMPLE_TIME seconds..."
sleep $((SAMPLE_TIME + 1))
TEMP=`grep "12-23" temp1 | tail -n $SAMPLE_TIME | awk '{ sum += $2; n++ } END { if (n > 0) print sum / n; }'`
echo "Average IPC = " $TEMP
check_min_value $TEMP 1 "average IPC value of"
TEMP=`grep "12-23" temp1 | tail -n $SAMPLE_TIME | awk '{ sum += $3; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MISSES = " $TEMP "k"
check_min_value $TEMP 50000 "average" "k MISSES"
#TEMP=`grep "12-23" temp1 | tail -n $SAMPLE_TIME | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
#echo "Average LLC = " $TEMP
#check_min_value $TEMP 10000 "average" "LLC"
TEMP=`grep "12-23" temp1 | tail -n $SAMPLE_TIME | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL = " $TEMP
check_min_value $TEMP 20000 "average" "MBL"
TEMP=`grep "12-23" temp1 | tail -n $SAMPLE_TIME | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBR = " $TEMP
check_min_value $TEMP 0.3 "average" "MBR"
echo ""
echo "... cpu/mem activity confirmed"
echo " ------------------------------ "
echo "Terminate stress and sleep for 15s..."
killall stress &> /dev/null
sleep 15s
echo "Confirm RDT monitoring for cores 12-23 have returned to quiescent state..."
confirm_pqos_quiescent_state_from_log "temp1"
echo "...confirmed"
clean_up

