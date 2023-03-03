

echo "Restore default pqos allocation"
pqos -R > /dev/null
pqos -R -I > /dev/null
echo " ------------------------------ "
echo "Define a COS for L3 with 4 cache-ways (MASK=0xf) for cores 5-6 and execute memtester 10M on those cores"
rdtset -t 'l3=0xf;cpu=5-6' -c 5-6 memtester 10M > /dev/null &
echo "Sleep 5s"
sleep 5s
L3CA_CHANGE_COUNT=`pqos -s | grep -E ".*L3CA.*=> MASK 0xf$" -c`
if [ $L3CA_CHANGE_COUNT -ne 1 ]; then
	echo "Error - Unexpected allocation found"
	exit 1
fi
echo "L3CA definition change confirmed"
COS_FOUND=`pqos -s | grep -E ".*L3CA.*=> MASK 0xf$" | awk '{print $2}'`
COS_FOUND_COUNT=`echo $COS_FOUND | wc -l`
if [ $COS_FOUND_COUNT -ne 1 ]; then
	echo "Error - Unexpected number of COS definitions found"
	exit 2
fi
CORE_AFFINITY_CHANGE_COUNT=`pqos -s | grep -E "Core [5|6],.* => $COS_FOUND," -c`
if [ $CORE_AFFINITY_CHANGE_COUNT -ne 2 ]; then
	echo "Error - Expected core affinity change not found"
	exit 3
fi
echo "Core affinity change confirmed"
echo "Terminate memtester"
MEMTESTER_PID=`ps aux | grep -i 'memtester' | grep -iv 'rdtset\|grep' | awk '{print $2}'`
kill -9 $MEMTESTER_PID
echo " ------------------------------ "
echo "Define a COS for L3 with INVALID bitmask (MASK=0xffffffff) for cores 5-6 and execute memtester 10M on those cores"
rdtset -t 'l3=0xffffffff;cpu=5-6' -c 5-6 memtester 10M &> temp.temp &
echo "Sleep 5s"
sleep 5s
ALLOCATION_ERROR_COUNT=`grep "One or more of requested L3 CBMs (MASK: 0xffffffff) not supported by system (too long)\|Allocation: Failed to configure allocation" temp.temp -c`
rm -fr temp.temp
if [ $ALLOCATION_ERROR_COUNT -ne 2 ]; then
	echo "Error - Expected specific config error, but did not find one"
	exit 4
fi
echo "Invalid setting was rejected as expected"
echo " ------------------------------ "
echo "Define a COS for L3 with 4 cache-ways (MASK=0xf) for dummy PID 1 over kernel/OS implementation"
rdtset -I -t 'l3=0xf' -c 5-6 -p 1 > /dev/null &
echo "Sleep 5s"
sleep 5s
NUM_SOCKETS=`lscpu | grep "Socket(s):" | awk '{print $2}'`
L3CA_CHANGE_COUNT=`pqos -s -I | grep -E ".*L3CA.*=> MASK 0xf$" -c`
if [ $L3CA_CHANGE_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - Unexpected allocation found"
	exit 5
fi
COS_FOUND=`pqos -s -I | grep -E ".*L3CA.*=> MASK 0xf$" | awk '{print $2}' | uniq`
COS_FOUND_COUNT=`echo $COS_FOUND | wc -l`
if [ $COS_FOUND_COUNT -ne 1 ]; then
echo "Error - Unexpected number of COS definitions found"
exit 6
fi
COS_PID_ASSOCIATION_COUNT=`pqos -s -I | grep -iE "$COS_FOUND => 1$" -c`
if [ $COS_PID_ASSOCIATION_COUNT -ne 1 ]; then
	echo "Error - Unexpected PID association found"
	exit 7
fi
echo "L3CA definition change confirmed"
echo " ------------------------------ "
echo "Define a COS for L3 with INVALID bitmask (MASK=0xffff) for dummy PID 1 over kernel/OS implementation"
rdtset -I -t 'l3=0xffff' -p 1 &> temp.temp &
echo "Sleep 5s"
sleep 5s
ALLOCATION_ERROR_COUNT=`grep "One or more of requested L3 CBMs (MASK: 0xffff) not supported by system (too long)\|Allocation: Failed to configure allocation" temp.temp -c`
rm -fr temp.temp
if [ $ALLOCATION_ERROR_COUNT -ne 2 ]; then
	echo "Error - Expected specific config error, but did not find one"
	exit 8
fi
echo "Invalid setting was rejected as expected"
echo " ------------------------------ "
echo "Done"



