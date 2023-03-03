
echo "Restore default pqos allocation"
pqos -R > /dev/null
echo " ------------------------------ "
echo "Set CPU/core affinity for memtester on core # 4 and begin execution"
rdtset -c 4 memtester 10M &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo "Confirm CPU/core affinity using taskset"
MEMTESTER_PID=`ps aux | grep -i "memtester" | grep -iv "rdtset\|grep" | awk '{print $2}'`
TASKSET_RETURN=`taskset -p $MEMTESTER_PID | grep -E "pid $MEMTESTER_PID.*current affinity mask: 10$" -c`
if [ $TASKSET_RETURN -ne 1 ]; then
	echo "Error - taskset reported affinity is not as expected"
	exit 1
fi
echo "Terminate memtester"
kill -9 $MEMTESTER_PID
echo "CPU/core affinity confirmed"
echo " ------------------------------ "
echo "Set CPU/core affinity for memtester on cores # 4-5 and begin execution"
rdtset -c 4-5 memtester 10M &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo "Confirm CPU/core affinity using taskset"
MEMTESTER_PID=`ps aux | grep -i "memtester" | grep -iv "rdtset\|grep" | awk '{print $2}'`
TASKSET_RETURN=`taskset -p $MEMTESTER_PID | grep -E "pid $MEMTESTER_PID.*current affinity mask: 30$" -c`
if [ $TASKSET_RETURN -ne 1 ]; then
	echo "Error - taskset reported affinity is not as expected"
	exit 1
fi
echo "Terminate memtester"
kill -9 $MEMTESTER_PID
echo "CPU/core affinity confirmed"
echo " ------------------------------ "
echo "Set CPU/core affinity for dummy PID 1 on core # 4"
rdtset -c 4 -p 1 &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo "Confirm CPU/core affinity for dummy PID 1 using taskset"
TASKSET_RETURN=`taskset -p 1 | grep -E "pid 1.*current affinity mask: 10$" -c`
if [ $TASKSET_RETURN -ne 1 ]; then
	echo "Error - taskset reported affinity is not as expected"
	exit 1
fi
echo "CPU/core affinity confirmed"
echo " ------------------------------ "
echo "Set CPU/core affinity for dummy PID 1 on cores # 4-5"
rdtset -c 4-5 -p 1 &> /dev/null &
echo "Sleep 5s"
sleep 5s
echo "Confirm CPU/core affinity for dummy PID 1 using taskset"
TASKSET_RETURN=`taskset -p 1 | grep -E "pid 1.*current affinity mask: 30$" -c`
if [ $TASKSET_RETURN -ne 1 ]; then
	echo "Error - taskset reported affinity is not as expected"
	exit 1
fi
echo "CPU/core affinity confirmed"
echo " ------------------------------ "
echo "Done"


