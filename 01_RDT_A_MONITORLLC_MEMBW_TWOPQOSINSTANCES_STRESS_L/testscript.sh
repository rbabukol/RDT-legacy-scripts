
#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
 
export PS4

killall stress &> /dev/null
CPUS=`lscpu | grep -E "^CPU\(s\):" | awk '{print $2}'`
if [ $CPUS -eq 0 ]; then
    echo "Error - could not detect # of cpu cores"
    exit 1
fi
echo " ------------------------------ "
echo "Restore default monitoring and capture baseline monitoring behavior"
echo "Sleep 2s"
pqos -r -t 2 | tail -n $CPUS > temp1
awk '{print $3}' temp1 > b3
awk '{print $5}' temp1 > b5
echo " ------------------------------ "
echo "Start stress instance to load memory and cpu usage"
echo "Sleep 2s"
stress -m 100 -c 100 & &> /dev/null
sleep 2s
echo " ------------------------------ "
echo "Confirm RDT monitoring reflects cpu/mem activity (by checking columns 3 and 5 of pqos output)"
THRESHOLD=95
pqos -r -t 2 | tail -n $CPUS > temp1
awk '{print $3}' temp1 > a3
awk '{print $5}' temp1 > a5
COL3_DIFFS=`diff -y --suppress-common-lines a3 b3 | grep "<\||" | wc -l`
COL5_DIFFS=`diff -y --suppress-common-lines a5 b5 | grep "<\||" | wc -l`
COL3_RATIO=`echo "($COL3_DIFFS / $CPUS) * 100" | bc -l | awk '{printf "%.0f",$0}'`
COL5_RATIO=`echo "($COL5_DIFFS / $CPUS) * 100" | bc -l | awk '{printf "%.0f",$0}'`
echo "Terminate stress"
killall stress &> /dev/null
echo "$COL3_RATIO% of pqos column 3 output changed"
if [ $COL3_RATIO -ge $THRESHOLD ]; then 
	echo ""
else
	echo "Error - step 4 - expected $THRESHOLD% of column values to change"
	exit 1
fi
echo "$COL5_RATIO% of pqos column 5 output changed"
if [ $COL5_RATIO -ge $THRESHOLD ]; then 
	echo ""
else
	echo "Error - step 4 - expected $THRESHOLD% of column values to change"
	exit 1
fi
echo "The minimum threshold of $THRESHOLD% change was observed"
echo "pqos monitoring is working"
rm -fr b3 b5 a3 a5 temp1
echo " ------------------------------ "
rm -fr pqos1 pqos2
echo "Attempt to run 2 instances of pqos at the same time"
echo "Start pqos #1"
pqos -t 60 -o pqos1 &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo "Confirm pqos #1 is running..."
TEMP=`head pqos1 -n 2 | grep -E "CORE.*IPC.*MBL.*MBR" -c`
if [ $TEMP -ne 1 ]; then 
	echo "Error - step 5 - was not able to start pqos #1"
	exit 1
fi
echo "...confirmed"
echo "Attempt to start pqos #2"
TEMP=`pqos -t 120 -o pqos2 | grep -E "$Monitoring start error on core.*, status" -c`
if [ $TEMP -ne 1 ]; then 
	echo "Error - step 5 - expected error on attempting to start second pqos, but didn't detect it."
	exit 1
fi

echo "pqos #2 did not start (expected)"
echo ""
echo "Clean up"
killall pqos
pqos -r -t0 &> /dev/null &
rm -fr pqos1 pqos2

