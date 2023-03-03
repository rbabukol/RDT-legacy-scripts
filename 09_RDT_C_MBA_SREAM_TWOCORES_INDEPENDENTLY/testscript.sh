
#!/bin/bash

# Set these as desired


###########################################

confirm_monitor() {
    echo "Monitor per-core memory bandwidth using the MBM feature of Intel RDT for 5s"
    rm -fr pqos_mon.csv
	sleep 1s
    pqos -m all:$CORE0,$CORE1 -u csv -o pqos_mon.csv -t 5 &> /dev/null
	sleep 1s
	echo "Confirm pqos is monitoring MBL..."
	LINE=`cat pqos_mon.csv | tail -n 2 | head -n 1`
	CORE0_CONFIRM=`echo $LINE | grep -E '^.*,"'$CORE0'",.*$' -c`
	LINE=`cat pqos_mon.csv | tail -n 2 | tail -n 1`
    CORE1_CONFIRM=`echo $LINE | grep -E '^.*,"'$CORE1'",.*$' -c`
    if [ $CORE0_CONFIRM -ne 1 ]; then
        echo "Error - couldn't confirm monitor on core $CORE0"
        exit 1
    fi
    if [ $CORE1_CONFIRM -ne 1 ]; then
        echo "Error - couldn't confirm monitor on core $CORE1"
        exit 1
    fi
    CORE0_CONFIRM=`tail pqos_mon.csv -n2 | head -n 1 | cut -d "," -f6 | cut -d "." -f1`
	sleep 1s
    CORE1_CONFIRM=`tail pqos_mon.csv -n2 | tail -n 1 | cut -d "," -f6 | cut -d "." -f1`
    if [ $CORE0_CONFIRM -eq 0 ]; then
        echo "Error - couldn't confirm monitor on core $CORE0"
        exit 1
    fi
    if [ $CORE1_CONFIRM -eq 0 ]; then
        echo "Error - couldn't confirm monitor on core $CORE1"
        exit 1
    fi
    echo "...Confirmed MBL monitor"
}

test() {
	SOCKET=$1
	CORE0=$2
	CORE0_COS=$3
	CORE1=$4
	CORE1_COS=$5

	CORE0_CONFIRM=""
	CORE1_CONFIRM=""
	CORE0_COS_NUM=`echo $CORE0_COS | sed "s/COS//g"`
	CORE1_COS_NUM=`echo $CORE1_COS | sed "s/COS//g"`

	echo " ------------------------------ "
	echo "Operating on Socket $SOCKET"

	HT=`lscpu | grep "Thread(s) per core:" | awk '{print $4}'`
	if [ $HT -ne 1 ]; then
		echo "Error - it appears that Hyperthreading is enabled.  Disable it in BIOS before running this test"
		echo "BIOS EDKII Menu -> Socket Configuration -> Processor Configuration -> Hyper-Threading [ALL] : Set to Disable"
		echo "Remember to enable it again after this test"
		exit 1
	fi
	echo "Restore default pqos allocation"
	pqos -R &> /dev/null
	echo " ------------------------------ "
	killall membw &> /dev/null
	sleep 2s
	echo "Start membw benchmark instance on core $CORE0 and leave it running for duration of test" 
	membw -c $CORE0 -b 20000 --nt-write &> /dev/null &
	echo "Sleep 2s"
	sleep 2s
	echo "Start membw benchmark instance on core $CORE1 and leave it running for duration of test" 
	membw -c $CORE1 -b 20000 --nt-write &> /dev/null &
	echo "Sleep 2s"
	sleep 2s
	echo " ------------------------------ "

	confirm_monitor
	echo " ------------------------------ "
	CORE0_BEFORE=`tail pqos_mon.csv -n2 | head -n 1 | cut -d "," -f6 | cut -d "." -f1`
	CORE1_BEFORE=`tail pqos_mon.csv -n2 | tail -n 1 | cut -d "," -f6 | cut -d "." -f1`
	echo "Associate LLC on core $CORE0 to $CORE0_COS and core $CORE1 to $CORE1_COS"
	pqos -a "llc:$CORE0_COS_NUM=$CORE0;llc:$CORE1_COS_NUM=$CORE1" &> /dev/null
	THROT="50"
	TOL="20"
	echo "Set $CORE0_COS and $CORE1_COS to $THROT percent throttling"
	CONFIG_CONFIRM=`pqos -e "mba@$SOCKET:$CORE0_COS_NUM=$THROT;mba@$SOCKET:$CORE1_COS_NUM=$THROT" | grep -E "SOCKET $SOCKET.*[$CORE0_COS|$CORE1_COS].*$THROT% requested, $THROT% applied$" -c`
	if [ $CONFIG_CONFIRM -ne 2 ]; then
		echo "Error - failed to set $THROT % throttling"
		exit 1
	fi
	echo "Throttling set confirmed"
	confirm_monitor
	CORE0_AFTER=`tail pqos_mon.csv -n2 | head -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE1_AFTER=`tail pqos_mon.csv -n2 | tail -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE0_RATIO=`echo "($CORE0_AFTER / $CORE0_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	CORE1_RATIO=`echo "($CORE1_AFTER / $CORE1_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	echo "Throttled / Unthrottled BW for each core:"
	echo "Core $CORE0 ratio: $CORE0_AFTER / $CORE0_BEFORE = $CORE0_RATIO %"
	echo "Core $CORE1 ratio: $CORE1_AFTER / $CORE1_BEFORE = $CORE1_RATIO %"
	PERCENT_DIFF=`echo "(($CORE0_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE0 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE0 ratio is outside of $TOL % tolerance from expected 50% throttle"
		exit 1
	fi
	PERCENT_DIFF=`echo "(($CORE1_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE1 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE1 ratio is outside of 20% tolerance from expected 50% throttle"
		exit 1
	fi
	echo " ------------------------------ "
	THROT="10"
	TOL="71"
	echo "Modify $CORE0_COS throttling to $THROT%"
	CONFIG_CONFIRM=`pqos -e "mba@$SOCKET:$CORE0_COS_NUM=$THROT" | grep -E "SOCKET $SOCKET.*$CORE0_COS.*$THROT% requested, $THROT% applied$" -c`
	if [ $CONFIG_CONFIRM -ne 1 ]; then
		echo "Error - failed to set $THROT % throttling"
		exit 1
	fi
	echo "Throttling set confirmed"
	confirm_monitor
	CORE0_AFTER=`tail pqos_mon.csv -n2 | head -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE1_AFTER=`tail pqos_mon.csv -n2 | tail -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE0_RATIO=`echo "($CORE0_AFTER / $CORE0_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	CORE1_RATIO=`echo "($CORE1_AFTER / $CORE1_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	echo "Throttled / Unthrottled BW for each core:"
	echo "Core $CORE0 ratio: $CORE0_AFTER / $CORE0_BEFORE = $CORE0_RATIO %"
	echo "Core $CORE1 ratio: $CORE1_AFTER / $CORE1_BEFORE = $CORE1_RATIO %"
	PERCENT_DIFF=`echo "(($CORE0_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE0 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE0 ratio is outside of $TOL % tolerance from expected $THROT% throttle"
		exit 1
	fi
	THROT="50"
	TOL="20"
	PERCENT_DIFF=`echo "(($CORE1_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE1 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE1 ratio is outside of $TOL % tolerance from expected $THROT% throttle"
		exit 1
	fi
	echo "Core $CORE1 BW is not affected as expected"
	echo " ------------------------------ "
	THROT="90"
	TOL="20"
	echo "Modify $CORE0_COS throttling to $THROT%"
	CONFIG_CONFIRM=`pqos -e "mba@$SOCKET:$CORE0_COS_NUM=$THROT" | grep -E "SOCKET $SOCKET.*$CORE0_COS.*$THROT% requested, $THROT% applied$" -c`
	if [ $CONFIG_CONFIRM -ne 1 ]; then
		echo "Error - failed to set $THROT % throttling"
		exit 1
	fi
	echo "Throttling set confirmed"
	confirm_monitor
	CORE0_AFTER=`tail pqos_mon.csv -n2 | head -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE1_AFTER=`tail pqos_mon.csv -n2 | tail -n 1 | cut -d "," -f6 | awk '{printf "%.0f",$0}'`
	CORE0_RATIO=`echo "($CORE0_AFTER / $CORE0_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	CORE1_RATIO=`echo "($CORE1_AFTER / $CORE1_BEFORE) * 100" | bc -l | awk '{printf "%.0f",$0}'`
	echo "Throttled / Unthrottled BW for each core:"
	echo "Core $CORE0 ratio: $CORE0_AFTER / $CORE0_BEFORE = $CORE0_RATIO %"
	echo "Core $CORE1 ratio: $CORE1_AFTER / $CORE1_BEFORE = $CORE1_RATIO %"
	PERCENT_DIFF=`echo "(($CORE0_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE0 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE0 ratio is outside of $TOL % tolerance from expected $THROT% throttle"
		exit 1
	fi
	THROT="50"
	TOL="20"
	PERCENT_DIFF=`echo "(($CORE1_RATIO - $THROT) / $THROT) * 100" | bc -l | awk '{printf "%.0f",$0}' | sed "s/-//"`
	if [ $TOL -gt $PERCENT_DIFF ]; then 
		echo "Core $CORE1 ratio is close enough to $THROT %.  See https://hsdes.intel.com/appstore/article/#/16016578408 attached results for this test where similar judgement is used to PASS"
	else
		echo "Error - Core $CORE1 ratio is outside of $TOL % tolerance from expected $THROT% throttle"
		exit 1
	fi
	echo "Core $CORE1 BW is not affected as expected"

	rm -fr pqos_mon.csv
	killall membw
}

test 0 15 COS2 30 COS3
test 1 50 COS4 51 COS3


