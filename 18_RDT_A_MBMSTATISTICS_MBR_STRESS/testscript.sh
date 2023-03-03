
#!/bin/bash

clean_up()
{
	echo ""
	echo "Clean up"
	killall pqos &> /dev/null 
	killall stress &> /dev/null 
	pqos -r -t0 &> /dev/null
	rm -fr MBR.txt temp1 temp2
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
	echo "Average MBR = " $TEMP
	check_max_value $TEMP 1 "average" "MBR"
	TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBR = " $TEMP
	check_max_value $TEMP 0.05 "average" "MBR"
}

echo " ------------------------------ "
echo "Restore default monitoring and capture baseline monitoring on all cores"
pqos -r -o temp1 -t 12 &> /dev/null &
echo "Sleep 15s"
sleep 15s
echo "Confirm RDT monitoring for is reporting quiescent state..."
confirm_pqos_quiescent_state_from_log "temp1"
rm -fr temp1
echo "...confirmed"
echo " ------------------------------"
TARGET_CORE=0
echo "Start memory load tool with simultaneous redirection of the process to one selected CPU (Socket 0)."
echo "Additionally with numactl tool force the use of memory allocated to the second socket (Socket1)."
taskset -c $TARGET_CORE numactl --membind=1 stress -m 100 &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo " ------------------------------"
SAMPLE_TIME=60
echo "Start collecting MBR statistics for physical core $TARGET_CORE with pqos for $SAMPLE_TIME s"
rm -fr MBR.txt
pqos --mon-core="mbr:$TARGET_CORE" --mon-file=MBR.txt -t $SAMPLE_TIME &> /dev/null
echo "Terminate stress"
killall stress
echo " ------------------------------ "
echo "Check MBR in RDT log to confirm successful logging..."
grep -E " $TARGET_CORE  [0-9].[0-9]{2} " MBR.txt > temp2
TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBR for core $TARGET_CORE = " $TEMP
check_min_value $TEMP 5000 "average" "MBR"
echo "...confirmed"
clean_up