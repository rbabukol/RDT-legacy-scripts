
#!/bin/bash

CORE_NUMBER=$1

lat_mem_rd() {
	CORE_NUMBER=$1
	CBM_VALUE_HEX=$2
	echo "Restore default pqos allocation"
	pqos -R > /dev/null
	echo "Define allocation class for LLC (COS1, CBM=$CBM_VALUE_HEX)"
	pqos -e "llc:1=$CBM_VALUE_HEX" > /dev/null
	echo "Associate core # $CORE_NUMBER LLC with allocation class COS1"
	pqos -a "llc:1=$CORE_NUMBER" > /dev/null
	echo "Start memory read latency benchmark (lat_mem_rd) on core # $CORE_NUMBER"
	rm -fr t2.temp
	echo "$CBM_VALUE_HEX" > t2.temp
	taskset -c $CORE_NUMBER lat_mem_rd -N 1 -P 1 145M 512 &> t1.temp
	awk '{print $2}' t1.temp | grep -E "[[:digit:]]" >> t2.temp
	rm -fr t1.temp
	echo "Merge results into $COMBINED_RESULT_FILE"
	paste -d "," $COMBINED_RESULT_FILE t2.temp > t3.temp
	rm -fr t2.temp
	mv t3.temp $COMBINED_RESULT_FILE
}

if [ -z $CORE_NUMBER ]; then
	echo "Core # not provided.  Using core 0 default."
	CORE_NUMBER=0
fi

NUM_WAYS=`pqos -s -v | sed -nr "s/.*L3 CAT details:.*ways=([0-9]+),.*/\\1/p"`
echo "Detected $NUM_WAYS cache ways"
if [ $NUM_WAYS -eq 12 ]; then
	CBM_ARRAY=(0x1 0x3 0x7 0xf 0x1f 0x3f 0x7f 0xff 0x1ff 0x3ff 0x7ff 0xfff)
elif [ $NUM_WAYS -eq 15 ]; then
	CBM_ARRAY=(0x1 0x3 0x7 0xf 0x1f 0x3f 0x7f 0xff 0x1ff 0x3ff 0x7ff 0xfff 0x1fff 0x3fff 0x7fff)
else
	echo "Error - unsupported # cache ways"
	exit 1
fi

echo "Running for CBM values:  ${CBM_ARRAY[*]}"
echo "If your CPU supports more or less, then edit CBM_ARRAY in this script accordingly"
#echo "Press ENTER to continue"
#read
echo ""

echo "Running for core # $CORE_NUMBER"
COMBINED_RESULT_FILE="combined_results_core_$CORE_NUMBER.csv"
echo "Prepare result file: $COMBINED_RESULT_FILE file"
echo "" > $COMBINED_RESULT_FILE
echo ""
echo "Start"
echo ""

for i in "${CBM_ARRAY[@]}"; do
	lat_mem_rd $CORE_NUMBER $i
	echo " ------- "
done
sed -i s/,// $COMBINED_RESULT_FILE

echo ""
echo "Done"
echo ""
echo "Warning - Results can be found in $COMBINED_RESULT_FILE"
echo "Warning - Open this CSV file in excel and copy+paste this table into latmemrd_graphic.xlsx to generate the line plot"
echo "Warning - Visually inspect the resluting line plot to confirm the incremental effect of the CBM sweep on LLC (L3, 1M-32M)"
echo ""

