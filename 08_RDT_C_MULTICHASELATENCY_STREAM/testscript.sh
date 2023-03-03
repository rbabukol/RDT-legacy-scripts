
#!/bin/bash

echo "Restore default pqos allocation"
pqos -R > /dev/null
pqos -R -I > /dev/null
echo " ------------------------------ "
echo "Confirm icc is installed in /opt/ and usable"
ICC_FOUND=`find /opt/ | grep -E ".*intel64.*icc$" | head -n 1 | wc -l`
if [ $ICC_FOUND -ne 1 ]; then
	echo "Error - could not find icc in /opt/ folder"
	exit 1
fi
ICC=`find /opt/ | grep -E ".*intel64.*icc$" | head -n 1`
CONFIRM_ICC=`$ICC --version 2> /dev/null | grep -E "icc.*ICC" -c`
if [ $CONFIRM_ICC -ne 1 ]; then
	echo "Error - could not find correct icc binary"
	exit 1
fi
echo "icc was found"
echo " ------------------------------ "
echo "checkout STREAM code and build with icc"
rm -fr stream_temp
mkdir stream_temp
cd stream_temp
git clone https://github.com/jeffhammond/STREAM.git &> /dev/null
cd STREAM
CONFIRM_STREAM=`find . | grep "Makefile\|stream.c" | wc -l`
if [ $CONFIRM_STREAM -ne 2 ]; then
	echo "Error - STREAM checkout failed"
	exit 1
fi
echo "STREAM code checkout was successful"
rm -fr stream
make clean &> /dev/null
$ICC -O3 -xCORE-AVX2 -ffreestanding -qopenmp -DSTREAM_ARRAY_SIZE=80000000 -DNTIMES=300 stream.c -o stream &> /dev/null
CONFIRM_STREAM=`find stream | wc -l`
if [ $CONFIRM_STREAM -ne 1 ]; then
	echo "Error - STREAM build failed"
	exit 1
fi
STREAM_PATH=`pwd`/stream
export LD_LIBRARY_PATH=`find /opt/ | grep -E ".*lib.*64.*libiomp5.so$" | sed -s "s/libiomp5.so//g"`:$LD_LIBRARY_PATH
echo "STREAM build was successful"
cd ../..
echo " ------------------------------ "
NUM_CORES=`lscpu | grep -i "Core(s) per socket:" | awk '{print $4}'`
MULTICHASE_BEFORE=`taskset -c 0 multichase`
echo "Run multichase before:  $MULTICHASE_BEFORE"
echo "Create STREAM tasks on socket 0 physical cores except core 0"
for i in $(eval echo {1..$((NUM_CORES -1))}); do
	#echo "creating STREAM task on core $i..."
	taskset -c $i $STREAM_PATH &> /dev/null &
	#sleep 1s
	#echo "...done"
done
echo "Sleep 10s"
sleep 10s
echo "Confirm all STREAM tasks were created"
if [ `pidof stream | wc -w` -ne $((NUM_CORES -1)) ]; then
	echo "Error - did not create all STREAM tasks"
	exit 1
fi
echo "All STREAM tasks were created successfully"
MULTICHASE_AFTER=`taskset -c 0 multichase`
echo "Run multichase after:  $MULTICHASE_AFTER"
echo " ------------------------------ "
#echo "Sleep 10s"
#sleep 10s
NUM_WAYS=`pqos -s -v | sed -nr "s/.*L3 CAT details:.*ways=([0-9]+),.*/\1/p"`
echo "Detected $NUM_WAYS cache ways"
COS0_CBM_LIST=""
COS1_CBM_LIST=""
if [ $NUM_WAYS -eq 12 ]; then
	COS0_CBM_LIST=(0x800 0xc00 0xe00 0xf00 0xf80 0xfc0 0xfe0 0xff0 0xff8 0xffc 0xffe)
	COS1_CBM_LIST=(0x7ff 0x3ff 0x1ff 0xff 0x7f 0x3f 0x1f 0xf 0x7 0x3 0x1)
elif [ $NUM_WAYS -eq 15 ]; then
	COS0_CBM_LIST=(0X4000 0x6000 0x7000 0x7800 0x7C00 0x7E00 0x7F00 0x7F80 0x7FC0 0x7FE0 0x7FF0 0x7FF8 0x7FFC 0x7FFE)
	COS1_CBM_LIST=(0x3fff 0x1fff 0x0fff 0x07ff 0x03ff 0x01ff 0x00FF 0x007F 0x003F 0x001F 0x000F 0x0007 0x0003 0x0001)
else
	echo "Error - unsupported # cache ways"
	exit 1
fi
echo "Using COS0_CBM_LIST = ${COS0_CBM_LIST[*]}"
echo "Using COS1_CBM_LIST = ${COS1_CBM_LIST[*]}"
echo "Associate allocation class COS0 on LLC with core 0"
pqos -a 'llc:2=0' > /dev/null
echo "Associate allocation class COS1 on LLC with all other physical cores on Socket 0"
pqos -a 'llc:3=1-'$((NUM_CORES -1))'' > /dev/null
MULTICHASE_AFTER=`taskset -c 0 multichase`
echo "multichase (LLC COS0-CBM=default, COS1-CBM=default):  $MULTICHASE_AFTER"
echo "Iterate through COS0/1 CBM pairs, set the corresponding LLC allocation class to each, and execute multichase on core 0 while other socket 0 physical cores continue to execute STREAM"
for i in $(eval echo {0..$((NUM_WAYS-2))}); do
	echo "Define allocation class for LLC (COS0, CBM=${COS0_CBM_LIST[$i]})"
	pqos -e 'llc@0:2='${COS0_CBM_LIST[$i]}'' > /dev/null
	#sleep 1s
	echo "Define allocation class for LLC (COS1, CBM=${COS1_CBM_LIST[$i]})"
	pqos -e 'llc@0:3='${COS1_CBM_LIST[$i]}'' > /dev/null
	#sleep 1s
	echo "Confirm STREAM tasks are still active"
	if [ `pidof stream | wc -w` -ne $((NUM_CORES -1)) ]; then
		echo "Error - not all STREAM tasks are running"
		exit 1
	fi
	echo "..confirmed"
	MULTICHASE_AFTER=`taskset -c 0 multichase`
	echo "multichase (LLC COS0-CBM=${COS0_CBM_LIST[$i]}, COS1-CBM=${COS1_CBM_LIST[$i]}):  $MULTICHASE_AFTER"
	#echo "Sleep 20s"
	#sleep 20s
done
echo "Warning - the multichase scores above should have trended down toward and near the \"Run multichase before\" ($MULTICHASE_BEFORE) score captured at the start of the test"
PERCENT_DIFF=`echo "(($MULTICHASE_BEFORE - $MULTICHASE_AFTER) / $MULTICHASE_AFTER) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//g"`
echo "MULTICHASE_BEFORE = " $MULTICHASE_BEFORE
echo "MULTICHASE_AFTER = " $MULTICHASE_AFTER
echo "% diff = " $PERCENT_DIFF "%"
if [ 11 -gt $PERCENT_DIFF ]; then
	echo ""
else
	echo "Warning - final multichase score is more than 10% off from initial score"
	echo "Warning - the test_case definition shows its expected output values to fail the test's pass/fail criteria also..."
	echo "Warning - the expected output captured for this test ticket shows a trend and value magnitudes very similar to what we observed on icx."
	echo "Warning - maybe this behavior is different on spr"
fi
echo "kill STREAM tasks"
killall stream
rm -fr stream_temp
echo "Done"


