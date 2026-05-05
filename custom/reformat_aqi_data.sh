#!/usr/bin/env bash
set -e
proj_dir=/home/pi/pi_air_quality_monitor
cd ${proj_dir} || exit

source check_ranges.func

data_dir=${proj_dir}/json_data
log_dir=logs
mkdir -p ${data_dir} ${log_dir}
data_log=/var/www/html/aqi_data.json
runtime_log=${log_dir}/service_aqi_runtime.log
startts=
stopts=
runtime=
ELAPSED=
events=

function key_swap(){
case $1 in 
	.labels)
	keyname="\"timestamp\" : "
	#keyname=" \"data\": [ { \"timestamp\":"
	keyfile=${data_dir}/timestamp.json
;;
	.aqi.data)
	#keyname=" \"data\": [ { \"aqi\":"
	keyname="\"aqi\" : "
	keyfile=${data_dir}/aqi.json
;;
	.pm10.data)
	keyname="\"pm10\":"
	keyfile=${data_dir}/pm10.json
;;
	.pm2.data)
	keyname="\"pm2\":"
	keyfile=${data_dir}/pm2.json
;;
esac
}

function time_script(){
case $1 in 
	start)
		startts=$(date +%s.%N)
		export startts
		echo "${startts}" >> ${runtime_log}
		;;
	stop)
		stopts=$(date +%s.%N)
		export stopts
		echo "${stopts}" >> ${runtime_log}
		;;
	calc)
		runtime=$(echo "${stopts} - ${startts}" | bc -l)
		mins=$(echo "${runtime} / 60" | bc -l)
		ELAPSED="Processed ${events} events in ${runtime} seconds [${mins} minutes]"
		export runtime ELAPSED
		echo -e "${ELAPSED}\n$(check_ranges ts)" >> ${runtime_log}
	;;
esac
}

function update_timestamps(){
tsfile=${data_dir}/timestamp.json
tsconv=${tsfile}.tsconv
tstmp=${tsfile}.tmp
tskeys=${tsfile}.keynames

cat $tsfile | awk '{print $3" "$4}' | sed 's/",//g' | sed 's/^"//g'| while IFS= read -r somedate ; do
	date -d "${somedate}"  +"%Y-%m-%dT%H:%M:%S%:z";
done > $tsconv

sed 's/^/: \"/g' ${tsconv} | sed 's/$/\",/g' > ${tstmp}
mv ${tstmp} ${tsconv}

cut -d':' -f1 ${tsfile} | sed 's/^/ \"data\" : { /g'  > ${tskeys}
paste ${tskeys} ${tsconv} > ${tsfile}
}

function reformat_aqi_data(){
for KEYNAMEQ in ".labels" ".aqi.data" ".pm10.data" ".pm2.data"; do
	key_swap "${KEYNAMEQ}"
	aqi_monitor json | jq .historical${KEYNAMEQ} | tr -d '[]' | grep '.' | sed '$s/$/,/' | sed "s/^/${keyname}/g" > ${keyfile}
done
update_timestamps
paste json_data/{timestamp,aqi,pm10,pm2}.json | sed 's/^/{/g' | sed 's/,$/} }/g'
}

function remove_invalid_lines(){
while IFS= read -r line; do
	x=$(echo "${line}" | grep 'data\|timestamp\|aqi\|pm10\|pm2' -o | wc -l);
	[[ "$x" -eq 5 ]] && echo "${line}";
done < ${data_log}.tmp > data_tmp.clean
cp data_tmp.clean ${data_log}.tmp
events=$(wc -l < ${data_log}.tmp)
export events
}

time_script start
reformat_aqi_data >> ${data_log}.tmp
sort -u ${data_log}.tmp -o ${data_log}.tmp
remove_invalid_lines
cat ${data_log}.tmp | jq -s > ${data_log}
time_script stop

time_script calc
