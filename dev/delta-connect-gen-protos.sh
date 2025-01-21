#!/usr/bin/env bash

#
# Copyright (2024) The Delta Lake Project Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
export PATH="$PATH:~/buf/bin"

set -ex

if [[ $# -gt 1 ]]; then
  echo "Illegal number of parameters."
  echo "Usage: $0 [path]"
  exit -1
fi

DELTA_HOME="$(cd "`dirname $0`"/..; pwd)"
cd "$DELTA_HOME"


OUTPUT_PATH=${DELTA_HOME}/python/delta/connect/proto/
if [[ $# -eq 1 ]]; then
  rm -Rf $1
  mkdir -p $1
  OUTPUT_PATH=$1
fi

pushd ${DELTA_HOME}/spark-connect/common/src/main

LICENSE=$(cat <<'EOF'
#
# Copyright (2024) The Delta Lake Project Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
EOF)
echo "$LICENSE" > /tmp/tmp_licence


# Delete the old generated protobuf files.
rm -Rf gen

# Now, regenerate the new files
buf generate --debug -vvv

# We need to edit the generated python files to account for the actual package location and not
# the location generated by proto.
for f in `find gen/proto/python/delta/connect -name "*.py*"`; do
  # First fix the imports.
  if [[ $f == *_pb2.py || $f == *_pb2_grpc.py ]]; then
    sed \
      -e 's/import spark.connect./import pyspark.sql.connect.proto./g' \
      -e 's/from delta.connect import/from delta.connect.proto import/g' \
      -e "s/DESCRIPTOR, 'delta.connect/DESCRIPTOR, 'delta.connect.proto/g" \
      $f > $f.tmp
    mv $f.tmp $f
  elif [[ $f == *.pyi ]]; then
    sed \
      -e 's/import spark.connect./import pyspark.sql.connect.proto./g' \
      -e 's/spark.connect./pyspark.sql.connect.proto./g' \
      -e 's/import delta.connect./import delta.connect.proto./g' \
      -e 's/delta.connect./delta.connect.proto./g' \
      $f > $f.tmp
    mv $f.tmp $f
  fi


  # Prepend the Apache licence header to the files.
  cp $f $f.bak
  cat /tmp/tmp_licence $f.bak > $f
  LC=$(wc -l < $f)
  echo $LC
  if [[ $f == *_grpc.py && $LC -eq 20 ]]; then
    rm $f
  fi
  rm $f.bak
done

black --config $DELTA_HOME/dev/pyproject.toml gen/proto/python/delta/connect

# Last step copy the result files to the destination module.
for f in `find gen/proto/python/delta/connect -name "*.py*"`; do
  cp $f $OUTPUT_PATH
done

# Clean up everything.
rm -Rf gen
