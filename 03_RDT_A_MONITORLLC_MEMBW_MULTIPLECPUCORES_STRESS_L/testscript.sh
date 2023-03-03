
#!/bin/bash

clean_up()
{
	echo ""
	echo "Clean up"
	killall pqos &> /dev/null 
	killall stress &> /dev/null 
	pqos -r -t0 &> /dev/null &
	rm -fr temp1 temp2
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

	#TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $2; n++ } END { if (n > 0) print sum / n; }'`
	#echo "Average IPC = " $TEMP
	#check_max_value $TEMP 1 "average IPC value of"
	TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $3; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MISSES = " $TEMP "k"
	check_max_value $TEMP 2 "average" "k MISSES"
	#TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
	#echo "Average LLC = " $TEMP
	#check_max_value $TEMP 10000 "average" "LLC"
	TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBL = " $TEMP
	check_max_value $TEMP 1 "average" "MBL"
	TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBR = " $TEMP
	check_max_value $TEMP 0.05 "average" "MBR"
}

killall stress &> /dev/null
echo " ------------------------------ "
CORE_ARRAY=( 0 1 3 21 22 23 )
echo "Restore default monitoring and capture baseline monitoring on cores ${CORE_ARRAY[@]}"
echo "Sleep 15s"
pqos -r -t 2 &> /dev/null
rm -fr temp1 temp2
CORE_LIST=`echo ${CORE_ARRAY[@]} | sed "s/ /,/g"`
pqos -m "all: $CORE_LIST" -o temp1 -t 1000 &> /dev/null &
CORE_LIST=`echo ${CORE_ARRAY[@]} | sed "s/ /,/g" | sed "s/\[//g" | sed "s/\]//g"`
sleep 13s
echo " ------------------------------ "
echo "Confirm only cores $CORE_LIST are in the monitoring output..."
T=`echo $CORE_LIST | sed "s/,/|/g"`
TEMP=`grep -v "CORE" temp1 | grep -v "TIME" | awk '{print $1}' | sort -u | grep -E "$T" -c`
if [ $TEMP -ne ${#CORE_ARRAY[@]} ]; then 
	echo "Error - unexpected output in pqos monitoring data"
	clean_up
	exit 1
fi
echo "...confirmed"
echo " ------------------------------ "
for i in "${CORE_ARRAY[@]}"; do
	echo "Confirm RDT monitoring for core $i is reporting quiescent state..."
	grep -E "$i  [0-9].[0-9]{2} " temp1 > temp2
	confirm_pqos_quiescent_state_from_log "temp2"
	echo "...confirmed"
	echo ""
done
echo "Default monitoring restored"
echo " ------------------------------ "
SAMPLE_TIME=10
echo "Start stress instance on cores $CORE_LIST to load memory and cpu usage"
echo "Sleep $SAMPLE_TIME seconds"
taskset -c $CORE_LIST stress -m 100 -c 100 &> /dev/null &
sleep $SAMPLE_TIME
echo " ------------------------------ "
for i in "${CORE_ARRAY[@]}"; do 
	echo "Confirm RDT monitoring for core $i reflects cpu/mem activity..."
	sleep $((SAMPLE_TIME + 1))
	grep -E "$i  [0-9].[0-9]{2} " temp1 > temp2
	#TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $2; n++ } END { if (n > 0) print sum / n; }'`
	#echo "Average IPC = " $TEMP
	#check_min_value $TEMP 0.5 "average IPC value of"
	TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $3; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MISSES = " $TEMP "k"
	check_min_value $TEMP 5000 "average" "k MISSES"
	#TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
	#echo "Average LLC = " $TEMP
	#check_min_value $TEMP 10000 "average" "LLC"
	TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBL = " $TEMP
	check_min_value $TEMP 1000 "average" "MBL"
	TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBR = " $TEMP
	#check_min_value $TEMP 0.2 "average" "MBR"
	echo "...confirmed"
	echo ""
done
echo " ------------------------------ "
echo "Terminate stress"
killall stress &> /dev/null
echo "Sleep 15s"
sleep 15s
for i in "${CORE_ARRAY[@]}"; do 
	echo "Confirm RDT monitoring for core $i has returned to quiescent state..."
	grep -E "$i  [0-9].[0-9]{2} " temp1 > temp2
	confirm_pqos_quiescent_state_from_log "temp2"
	echo "...confirmed"
	echo ""
done
clean_up

