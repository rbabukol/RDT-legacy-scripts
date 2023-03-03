
#!/bin/bash

echo "Restore default pqos allocation and monitoring"
pqos -R -I > /dev/null
echo " ------------------------------ "
pqos -s -I | grep "MBA COS" > mba_before.txt
echo "Set MBA to 50% for cores 5,6 and start memtester on those cores"
rdtset -I -t "mba=50;cpu=5-6" -c 5-6 memtester 10M &> /dev/null &
sleep 5s
pqos -s -I | grep "MBA COS" > mba_after.txt
echo "Confirm the change in pqos -s output..."
FOUND1=`diff mba_before.txt mba_after.txt | grep -E "^<.*=> 100% available$" -c`
FOUND2=`diff mba_before.txt mba_after.txt | grep -E "^>.*=> 50% available$" -c`
rm -fr mba_before.txt
rm -fr mba_after.txt
if [ $(($FOUND1 + $FOUND2)) -ne 2 ]; then
	echo "Error - could not confirm change in pqos output"
	exit 1
fi
echo "Change confirmed"
echo "Terminate memtester"
killall memtester
echo " ------------------------------ "
echo "Set MBA to 200% (Intentionally Invalid) for cores 5,6 and start memtester on those cores"
rdtset -I -t "mba=200;cpu=5-6" -c 5-6 memtester 10M &> 200_temp.txt 
FOUND1=`grep -E "^Invalid RDT parameters" -c 200_temp.txt`
rm -fr 200_temp.txt
if [ $FOUND1 -ne 1 ]; then
	echo "Error - did not detect appropriate error message for invalid setting"
	exit 1
fi
echo "rdtset rejected the invalid setting and provided expected message"

echo "Done"


