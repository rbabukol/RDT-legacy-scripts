
#!/bin/bash

clean_up()
{
	echo ""
	echo "Clean up"
	killall pqos &> /dev/null 
	killall memtester &> /dev/null 
	pqos -r -t0 &> /dev/null
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

killall memtester &> /dev/null
rm -fr temp1 temp2
echo " ------------------------------ "
echo "Confirm MBM capability is detected on platform..."
TEMP=`pqos -d | grep -E "(Memory Bandwidth Monitoring \(MBM\) events:$)|(Total Memory Bandwidth)" -c`
if [ $TEMP -ne 2 ]; then
	echo "Error - Verify MBM capability"
	exit 1
fi
echo "...confirmed"
echo " ------------------------------ "
echo "Restore default monitoring and capture baseline monitoring on all cores"
pqos -r -o temp1 -t 12 &> /dev/null &
sleep 15s
echo "Sleep 15s"
echo "Confirm RDT monitoring for is reporting quiescent state..."
confirm_pqos_quiescent_state_from_log "temp1"
rm -fr temp1
echo "...confirmed"
echo " ------------------------------ "
TARGET_CORE=4
CORES_PER_SOCKET=`lscpu | grep -i "Core(s) per socket" | awk '{print $4}'`
echo "Start memtester instance on physical core $TARGET_CORE to load memory usage"
taskset -c 4 memtester 100M &> /dev/null &
echo " ------------------------------ "
SAMPLE_TIME=10
echo "Start MBM monitoring on all Socket 0 physical cores and verify core $TARGET_CORE MBL activity compared to non-active cores..."
echo "Sleep $((SAMPLE_TIME + 1)) s"
pqos -m mbl:0-$((CORES_PER_SOCKET - 1)) -m mbr:0-$((CORES_PER_SOCKET - 1)) -o temp1 -t $SAMPLE_TIME &> /dev/null
grep -E " $TARGET_CORE  [0-9].[0-9]{2} " temp1 > temp2
TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL for core $TARGET_CORE = " $TEMP
check_min_value $TEMP 10000 "average" "MBL"
grep -Ev " $TARGET_CORE  [0-9].[0-9]{2} " temp1 > temp2
TEMP=`grep -v "CORE" temp2 | grep -v "TIME" | awk '{ sum += $4; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL for all other cores = " $TEMP
check_max_value $TEMP 100 "average" "MBL"
rm -fr temp1 temp2
echo "...verified MBL activity"
echo " ------------------------------ "
echo "Start MBM monitoring on memtester pid and a second dummy pid (1) to verify activity by pid..."
MEMTESTER_PID=`pidof memtester`
echo "memtester pid = " $MEMTESTER_PID
SAMPLE_TIME=10
echo "Sleep $((SAMPLE_TIME + 1)) s"
pqos -I -p mbl:$MEMTESTER_PID -p mbr:$MEMTESTER_PID -p mbr:1 -o temp1 -t $SAMPLE_TIME &> /dev/null
echo "Confirm MBL and MBR columns are present in minotoring output..."
TEMP=`grep -E "(MBL\[MB/s\])|(MBR\[MB/s\])" -c temp1`
if [ $TEMP -lt 1 ]; then
	echo "Error - MBL and MBR columns were not found in minotoring data"
	exit 1
fi
echo "...confirmed"
grep -E " $MEMTESTER_PID[ ]+$TARGET_CORE[ ]+[0-9].[0-9]{2} " temp1 > temp2
TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL for pid $MEMTESTER_PID = " $TEMP
check_min_value $TEMP 5000 "average" "MBL"
#TEMP=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
#echo "Average MBR for pid $MEMTESTER_PID = " $TEMP
#check_min_value $TEMP 10000 "average" "MBR"
grep -E " 1[ ]+[0-9]+[ ]+[0-9].[0-9]{2} " temp1 > temp2
TEMP=`grep -v "CORE" temp2 | grep -v "TIME" | awk '{ sum += $5; n++ } END { if (n > 0) print sum / n; }'`
echo "Average MBL for pid 1 = " $TEMP
check_max_value $TEMP 5 "average" "MBL"
#TEMP=`grep -v "CORE" temp2 | grep -v "TIME" | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
#echo "Average MBR for pid 1= " $TEMP
#check_max_value $TEMP 5 "average" "MBR"

echo "...verified MBL activity"
echo " ------------------------------ "
clean_up

