#!/bin/bash

NUM_SOCKETS=`lscpu | grep "Socket(s):" | awk '{print $2}'`
echo "Restore default pqos allocation"
pqos -R > /dev/null
pqos -R -I > /dev/null
echo " ------------------------------ "
echo "Verify MBA capability is detected on platform"
MBA_CAP_FOUND=`pqos -s -v | grep -E "MBA capability detected$" -c`
if [ $MBA_CAP_FOUND -ne 1 ]; then
	echo "Error - MBA capability was not detected"
	exit 1
fi
echo "MBA verified"
echo " ------------------------------ "
echo "Define allocation class for MBA (COS2, up to 50% Mem BW Allocation for all cores)"
CONFIRMATION_COUNT=`pqos -e 'mba:2=50' | grep -E ".*MBA COS2 => 50% requested, 50% applied$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition failed"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s | grep -E "MBA COS2 => 50% available$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition command was successful, but changes could not be confirmed"
	exit 2
fi
echo "Definition was successful"
echo " ------------------------------ "
echo "Define allocation class for MBA (COS2, up to 20% Mem BW Allocation for all cores)"
CONFIRMATION_COUNT=`pqos -e 'mba:2=20' | grep -E ".*MBA COS2 => 20% requested, 20% applied$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition failed"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s | grep -E "MBA COS2 => 20% available$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition command was successful, but changes could not be confirmed"
	exit 2
fi
echo "Definition was successful"
echo " ------------------------------ "
echo "Define allocation class for MBA (COS2, up to 80% Mem BW Allocation for all cores)"
CONFIRMATION_COUNT=`pqos -e 'mba:2=80' | grep -E ".*MBA COS2 => 80% requested, 80% applied$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition failed"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s | grep -E "MBA COS2 => 80% available$" -c`
if [ $CONFIRMATION_COUNT -ne $NUM_SOCKETS ]; then
	echo "Error - COS definition command was successful, but changes could not be confirmed"
	exit 2
fi
echo "Definition was successful"
echo " ------------------------------ "
echo "Define INVALID allocation class for MBA (COS2, up to 200% Mem BW Allocation for all cores)"
CONFIRMATION_COUNT=`pqos -e 'mba:2=200' | grep -E "^ERROR: MBA COS2 rate out of range \(from 1-100\)\!$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
	echo "Error - Did not receive expected error for invalid COS definition"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s | grep -E "MBA COS2 => 200% available$" -c`
if [ $CONFIRMATION_COUNT -ne 0 ]; then
	echo "Error - the invalid COS definition command was detected, but not expected"
	exit 2
fi
echo "Invalid definition test was successful"
echo " ------------------------------ "
echo "Associate allocation class COS6 on LLC with cores 1 and 3"
CONFIRMATION_COUNT=`pqos -a 'llc:6=1,3' | grep -E "^Allocation configuration altered.$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
	echo "Error - COS6 association command was not successful"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s | grep -E "Core [1|3],.*=> COS6," -c`
if [ $CONFIRMATION_COUNT -ne 2 ]; then
	echo "Error - COS6 association was not successful"
	exit 2
fi
echo "Association was successful"
echo " ------------------------------ "
echo "Attempt an invalid association for class COS6 on LLC with core 1000"
CONFIRMATION_COUNT=`pqos -a 'llc:6=1000' | grep -E "^Core number or class id is out of bounds\!$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
	echo "Error - Did not receive expected error for invalid association"
	exit 2
fi
echo "Invalid association test was successful"
echo " ------------------------------ "
echo "Associate dummy PID 1 with COS2"
CONFIRMATION_COUNT=`pqos -I -a 'pid:2=1' | grep -E "^Allocation configuration altered.$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
	echo "Error - dummy PID 1 association with COS2 command was not successful"
	exit 2
fi
CONFIRMATION_COUNT=`pqos -s -I | grep -E "COS2 => 1$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
	echo "Error - dummy PID 1 association with COS2 was not successful"
	exit 2
fi
echo "Association was successful"
echo " ------------------------------ "
echo "Associate invalid, dummy PID 9999999999 with COS2"
CONFIRMATION_COUNT=`pqos -I -a 'pid:2=9999999999' | grep -E "^Task ID number or class id is out of bounds\!$" -c`
if [ $CONFIRMATION_COUNT -ne 1 ]; then
echo "Error - invalid, dummy PID 9999999999 association with COS2 command did not report error as expected"
exit 2
fi
CONFIRMATION_COUNT=`pqos -s -I | grep -E "COS2 => 9999999999$" -c`
if [ $CONFIRMATION_COUNT -ne 0 ]; then
	echo "Error - invalid, dummy PID 9999999999 association with COS2 was detected, but not expected"
	exit 2
fi
echo "Invalid association test was successful"
echo " ------------------------------ "
echo "Done"


