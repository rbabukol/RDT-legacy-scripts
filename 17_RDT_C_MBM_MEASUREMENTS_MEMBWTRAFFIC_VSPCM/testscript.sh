
#!/bin/bash

PERCENT_DIFF_THRESHOLD=10

clean_up()
{
	echo ""
	echo "Clean up"
	killall pqos &> /dev/null
	killall membw &> /dev/null
	killall pcm-memory &> /dev/null
	pqos -r -t0 &> /dev/null
	rm -fr temp1 temp2 test.csv
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
	SAMPLES=$(($THRESH + 2))
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
	check_max_value $TEMP 20 "average" "MBL"
	TEMP=`grep -v "CORE" $LOG_FILE_NAME | grep -v "TIME" | tail -n $SAMPLES | awk '{ sum += $6; n++ } END { if (n > 0) print sum / n; }'`
	echo "Average MBR = " $TEMP
	check_max_value $TEMP 0.05 "average" "MBR"
}

killall membw &> /dev/null
killall pcm-memory &> /dev/null
rm -fr temp1 temp2 test.csv
echo " ------------------------------ "
echo "Restore default monitoring and capture baseline monitoring on all cores"
pqos -r -o temp1 -t 12 &> /dev/null &
echo "Sleep 15s"
sleep 15s
echo "Confirm RDT monitoring is reporting quiescent state..."
confirm_pqos_quiescent_state_from_log "temp1"
rm -fr temp1 temp2
echo "...confirmed"
echo " ------------------------------ "
echo "--- Run test for local node nt-write ---"
LOCALITY=0
TARGET_CORE=1
RDT_COL=5
TXT="Local mem BW"
PCM_COL=51
echo "Start membw instance on physical core $TARGET_CORE to load memory usage"
numactl --membind=$LOCALITY membw -c 1 -b 20000 --nt-write &> /dev/null &
SAMPLE_TIME=30
echo "Start RDT monitoring on core $TARGET_CORE."
echo "Sleep $((SAMPLE_TIME + 2)) s"
pqos -m all:$TARGET_CORE -o temp1 -t $SAMPLE_TIME &> /dev/null
grep -E " $TARGET_CORE  [0-9].[0-9]{2} " temp1 > temp2
RDT_AVG=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $'$RDT_COL'; n++ } END { if (n > 0) print sum / n; }'`
echo "Average RDT write BW for core $TARGET_CORE = " $RDT_AVG
check_min_value $RDT_AVG 10000 "average" $TXT
SAMPLE_TIME=30
echo "Start PCM monitoring on core $TARGET_CORE."
pcm-memory -csv > test.csv 2> /dev/null &
echo "Sleep $((SAMPLE_TIME + 2)) s"
sleep $((SAMPLE_TIME + 2))
echo "Terminate pcm-memory"
killall pcm-memory
echo "Terminate membw"
killall membw
PCM_AVG=`cat test.csv | sed "s/ //g" | cut -d "," -f$PCM_COL | grep -E "^[[:digit:]]+.*$" | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`
echo "Average PCM write BW for core $TARGET_CORE = " $PCM_AVG
check_min_value $PCM_AVG 10000 "average" $TXT
PERCENT_DIFF=`echo "(($PCM_AVG - $RDT_AVG) / $RDT_AVG) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
echo "PCM to RDT % diff = " $PERCENT_DIFF "%"
if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF ]; then 
	echo "RDT and PCM write BW are effectively equal (within $PERCENT_DIFF_THRESHOLD %) as expected"
else 
	echo "Error - RDT and PCM write BW are not equal (within $PERCENT_DIFF_THRESHOLD %)"
	clean_up
	exit 1
fi
rm -fr temp1 temp2
echo " ------------------------------ "
echo "--- Run test for remote node nt-write ---"
LOCALITY=1
TARGET_CORE=1
RDT_COL=6
TXT="Local mem BW"
PCM_COL=51
echo "Start membw instance on physical core $TARGET_CORE to load memory usage"
numactl --membind=$LOCALITY membw -c 1 -b 20000 --nt-write &> /dev/null &
SAMPLE_TIME=30
echo "Start RDT monitoring on core $TARGET_CORE."
echo "Sleep $((SAMPLE_TIME + 2)) s"
pqos -m all:$TARGET_CORE -o temp1 -t $SAMPLE_TIME &> /dev/null
grep -E " $TARGET_CORE  [0-9].[0-9]{2} " temp1 > temp2
RDT_AVG=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $'$RDT_COL'; n++ } END { if (n > 0) print sum / n; }'`
echo "Average RDT write BW for core $TARGET_CORE = " $RDT_AVG
check_min_value $RDT_AVG 10000 "average" $TXT
SAMPLE_TIME=30
echo "Start PCM monitoring on core $TARGET_CORE."
pcm-memory -csv > test.csv 2> /dev/null &
echo "Sleep $((SAMPLE_TIME + 2)) s"
sleep $((SAMPLE_TIME + 2))
echo "Terminate pcm-memory"
killall pcm-memory
echo "Terminate membw"
killall membw
PCM_AVG=`cat test.csv | sed "s/ //g" | cut -d "," -f$PCM_COL | grep -E "^[[:digit:]]+.*$" | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`
echo "Average PCM write BW for core $TARGET_CORE = " $PCM_AVG
check_min_value $PCM_AVG 10000 "average" $TXT
PERCENT_DIFF=`echo "(($PCM_AVG - $RDT_AVG) / $RDT_AVG) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
echo "PCM to RDT % diff = " $PERCENT_DIFF "%"
if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF ]; then 
	echo "RDT and PCM write BW are effectively equal (within $PERCENT_DIFF_THRESHOLD %) as expected"
else 
	echo " ******** NOTE ********"
	echo "Warning - The test steps listed in the test_case_definition ticket (https://hsdes.intel.com/appstore/article/#/18016919203) say that RDT and PCM remote mem BW values should be the same"
	echo "Warning - Looking at the automation test logs attached to one of the test_result tickets (https://hsdes.intel.com/appstore/article/#/16016578373) for this test_case we see that this test was passed based on RDT BW being ~2x PCM BW..."
	PERCENT_DIFF_HALF=`echo "(($PERCENT_DIFF - 50) / 50) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF_HALF ]; then 
		echo "Warning - Because the RDT vs. PCM BW is ~2x ($PERCENT_DIFF_THRESHOLD% margin), will not fail this test"
	else
		echo "Error - didn't meet the pass/fail criteria as described in the test_case_definition ticket, nor in the revised behavior shown in the test_result ticket log file"
		clean_up
		exit 1
	fi
fi
rm -fr temp1 temp2
echo " ------------------------------ "
echo "--- Run test for remote node write ---"
LOCALITY=1
TARGET_CORE=1
RDT_COL=6
TXT="Local mem BW"
PCM_COL=51
echo "Start membw instance on physical core $TARGET_CORE to load memory usage"
numactl --membind=$LOCALITY membw -c 1 -b 20000 --write &> /dev/null &
SAMPLE_TIME=30
echo "Start RDT monitoring on core $TARGET_CORE."
echo "Sleep $((SAMPLE_TIME + 2)) s"
pqos -m all:$TARGET_CORE -o temp1 -t $SAMPLE_TIME &> /dev/null
grep -E " $TARGET_CORE  [0-9].[0-9]{2} " temp1 > temp2
RDT_AVG=`tail -n $SAMPLE_TIME temp2 | awk '{ sum += $'$RDT_COL'; n++ } END { if (n > 0) print sum / n; }'`
echo "Average RDT write BW for core $TARGET_CORE = " $RDT_AVG
check_min_value $RDT_AVG 10000 "average" $TXT
SAMPLE_TIME=30
echo "Start PCM monitoring on core $TARGET_CORE."
pcm-memory -csv > test.csv 2> /dev/null &
echo "Sleep $((SAMPLE_TIME + 2)) s"
sleep $((SAMPLE_TIME + 2))
echo "Terminate pcm-memory"
killall pcm-memory
echo "Terminate membw"
killall membw
PCM_AVG=`cat test.csv | sed "s/ //g" | cut -d "," -f$PCM_COL | grep -E "^[[:digit:]]+.*$" | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`
echo "Average PCM write BW for core $TARGET_CORE = " $PCM_AVG
check_min_value $PCM_AVG 10000 "average" $TXT
PERCENT_DIFF=`echo "(($PCM_AVG - $RDT_AVG) / $RDT_AVG) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
echo "PCM to RDT % diff = " $PERCENT_DIFF "%"
if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF ]; then 
	echo "RDT and PCM write BW are effectively equal (within $PERCENT_DIFF_THRESHOLD %) as expected"
else 
	PERCENT_DIFF_THRESHOLD=30
	echo " ******** NOTE ********"
	echo "Warning - The test steps listed in the test_case_definition ticket (https://hsdes.intel.com/appstore/article/#/18016919203) say that RDT and PCM remote mem BW values should be the same."
	echo "Warning - The expected sample output in the test_case_definition ticket shows a 60% gap between PCM to RDT BW values..."
	echo "Warning - Looking at the automation test logs attached to one of the test_result tickets (https://hsdes.intel.com/appstore/article/#/16016578373) for this test_case we see that this test was passed based on PCM BW being larger than RDT BW...there are no details beyond that."
	echo "Warning - Based on this confusion use a marging of $PERCENT_DIFF_THRESHOLD% and confirm PCM BW is larger than RDT BW."
	TEMP=`echo "(($PCM_AVG - $RDT_AVG) < 0 )" | bc -l`
	if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF ] && [ `echo "(($PCM_AVG - $RDT_AVG) < 0 )" | bc -l` -eq 0 ]; then 
		echo "Warning - Because PCM BW is greater than RDT BW and within $PERCENT_DIFF_THRESHOLD% margin, will not fail this test"
	else
		echo "Error - didn't meet the pass/fail criteria as described in the test_case_definition ticket, nor in the revised behavior described above"
		clean_up
		exit 1
	fi
fi


clean_up


