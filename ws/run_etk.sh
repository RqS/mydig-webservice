#!/bin/bash

page_path="$1"
working_dir="$2"
conda_bin_path="$3"
etk_path="$4"
num_processes="$5"
pages_per_tld_to_run="$6"
pages_extra_to_run="$7"
lines_user_data_to_run="$8"
sandpaper_url="$9"
index="${10}"
project_es_url="${11}"

#echo ${page_path}
#echo ${working_dir}
#echo ${conda_bin_path}
#echo ${etk_path}
#echo ${num_processes}
#echo ${pages_per_tld_to_run}
#echo ${pages_extra_to_run}
#echo ${lines_user_data_to_run}
#echo ${sandpaper_url}
#echo ${ws_url}
#echo ${project_es_url}

# prepare data source
#data_file_path="${working_dir}/etk_input.jl"
#if [ ! -f ${data_file_path} ]; then
user_data_file_path="${working_dir}/user_data.jl"
if [ -f ${user_data_file_path} ]; then
    data_file_path="${working_dir}/user_data_picked.jl"
    shuf -n ${lines_user_data_to_run} ${user_data_file_path} > ${data_file_path}
else
    data_file_path="${working_dir}/consolidated_data.jl"
    echo -n > ${data_file_path} # clean all
    ls ${page_path} | grep -v extra.jl | xargs -I {} head -q -n ${pages_per_tld_to_run} ${page_path}/{} \
        >> ${data_file_path} # append tlds data
    head -q -n ${pages_extra_to_run} ${page_path}/extra.jl >> ${data_file_path} # append extra data
fi
#fi

# initiate etk env
source ${conda_bin_path}/activate etk_env

# serial
#python ${etk_path}/etk/run_core.py \
#    -i ${data_file_path} \
#    -o ${working_dir}/etk_out.jl \
#    -c ${working_dir}/etk_config.json > ${working_dir}/etk_stdout.txt


# create output tmp dir
if [ ! -d "${working_dir}/tmp" ]; then
    mkdir "${working_dir}/tmp"
fi

# clean previous outputs and progress
rm ${working_dir}/tmp/output_chunk_*
rm ${working_dir}/etk_progress
rm ${working_dir}/etk_stdout.txt

# create progress file
num_of_docs=$(wc -l ${data_file_path} | awk '{print $1}')
while true; do sleep 5; \
#    wc -l ${working_dir}/tmp/output_chunk_* | tail -n 1 | awk -v total=$num_of_docs '{print total" "$1}' \
#     > ${working_dir}/etk_progress; \
    curl -s "${project_es_url}/_count" | jq .count | awk -v total=$num_of_docs '{print total" "$1}' \
     > ${working_dir}/etk_progress; \
done &
progress_job_id=$!

# run etk parallelly
python -u ${etk_path}/etk/run_core.py \
    --dummy-this-is-mydig-backend-etk-process \
    -i "${data_file_path}" \
    -o "${working_dir}/tmp" \
    -c "${working_dir}/etk_config.json" \
    -m -t ${num_processes} \
    --batch-enabled \
    --batch-size=100 \
    --batch-http-url="${sandpaper_url}/indexing?index=${index}" \
    --batch-http-headers="{\"Content-Type\": \"application/json\"}" \
    --batch-dump-path="${working_dir}/tmp" \
    > "${working_dir}/etk_stdout.txt"
last_exit_code=$?

# close progress background job (sleep more than 5 seconds to let progressbar finish)
sleep 6
kill ${progress_job_id}

if [ ${last_exit_code} -ne 0 ]; then
    exit ${last_exit_code}
fi

# concatenate outputs
#cat ${working_dir}/tmp/output_chunk_* > ${working_dir}/etk_out.jl

#if [ ${last_exit_code} == 0 ]; then
#    cp "${working_dir}/etk_out.jl" "${working_dir}/etk_input.jl"
#fi

exit ${last_exit_code}
