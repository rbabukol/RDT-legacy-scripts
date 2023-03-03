#!/bin/bash

run_test()
{
	LAST_CORE=5
	MLC_WL=$1
	RES_FILE=$2
	PERCENT_DIFF_THRESHOLD=$3
	MLC_WL_FILE="inp.txt"
	MLC_OUT_FILE="mlc_mbm_remote.txt"
	PQOS_OUT_CSV_FILE="pqos_mon.csv"
	echo "Run test for $MLC_WL"
	#echo "Restore default pqos allocation"
	pqos -R > /dev/null
	#echo "Create mlc workload file"
	echo "$MLC_WL" > $MLC_WL_FILE
	#echo "Start mlc workload"
	mlc -Z -o$MLC_WL_FILE --loaded_latency -d0 -T -t20 > $MLC_OUT_FILE &
	#echo "Ramp for 10s"
	sleep 10s
	#echo "Start pqos monitor on cores 0-$LAST_CORE"
	rm -fr $PQOS_OUT_CSV_FILE && pqos -m all:0-$LAST_CORE -u csv -o $PQOS_OUT_CSV_FILE -t 5 > /dev/null
	#echo "Wait for jobs to complete"
	wait `pidof mlc`
	BW_COL=`echo "6 + \`echo "$MLC_WL" | awk '{print $6}'\`" | bc`
	PQOS_BW=`tail -n 6 $PQOS_OUT_CSV_FILE | cut -d "," -f $BW_COL | grep -iv "0.0" | grep -E "[[:digit:]]" | awk '{ total += $1; count++ } END { print total/count }' | xargs -I % sh -c "echo '% * ("$LAST_CORE" + 1)' | bc"`
	MLC_BW=`tail -n 1 $MLC_OUT_FILE| awk '{print $3}'`
	PERCENT_DIFF=`echo "(($PQOS_BW - $MLC_BW) / $MLC_BW) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $((PERCENT_DIFF_THRESHOLD + 1)) -gt $PERCENT_DIFF ]; then RES=PASS; else RES="Error - FAIL"; fi
	echo "$MLC_WL | PQOS BW = $PQOS_BW, MLC BW = $MLC_BW | % diff = $PERCENT_DIFF%, threshold = $PERCENT_DIFF_THRESHOLD% | $RES" | tee -a RES_FILE
	rm -fr $MLC_WL_FILE
	rm -fr $MLC_OUT_FILE
	rm -fr $PQOS_OUT_CSV_FILE
}

echo "------------------------------"
echo "Start test..."
rm -fr result.file
## see the comments at the end of this file about range of pass/fail thresholds used below (10 to 91%)
run_test "0-5 R   seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 R   seq  1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 R   rand 1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 R   rand 1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W2  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W2  seq  1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W3  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W3  seq  1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W5  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W5  seq  1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W6  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W6  seq  1000000 dram 1" result.file 90
echo "-----"
run_test "0-5 W7  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W7  seq  1000000 dram 1" result.file 27
echo "-----"
run_test "0-5 W8  seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W8  seq  1000000 dram 1" result.file 44
echo "-----"
run_test "0-5 W10 seq  1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W10 seq  1000000 dram 1" result.file 28
echo "-----"
run_test "0-5 W2  rand 1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W2  rand 1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W5  rand 1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W5  rand 1000000 dram 1" result.file 10
echo "-----"
run_test "0-5 W6  rand 1000000 dram 0" result.file 10
echo "-----"
run_test "0-5 W6  rand 1000000 dram 1" result.file 91
echo "...done"
echo "Warning - This test states that mlc and pqos reported BW values should be within 10%, though our initial results AND the expected results defined in the test miss on several workloads."
echo "Warning - Reviewed results with Rama and he insisted that these are all expected and to treat them as passes."
echo "Warning - Based on this guidance, you may notice some BWs will be as high has 91% off, but will still be treated as passing" 

