#!/usr/bin/env bash
# Copyright 2019 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ==============================================================================
# Make sure we're in the project root path.
SCRIPT_DIR=$( cd ${0%/*} && pwd -P )
ROOT_DIR=$( cd "$SCRIPT_DIR/.." && pwd -P )
if [[ ! -d "tensorflow_io" ]]; then
    echo "ERROR: PWD: $PWD is not project root"
    exit 1
fi

set -x -e

PLATFORM="$(uname -s | tr 'A-Z' 'a-z')"

if [[ ${PLATFORM} == "darwin" ]]; then
    N_JOBS=$(sysctl -n hw.ncpu)
else
    N_JOBS=$(grep -c ^processor /proc/cpuinfo)
fi

echo ""
echo "Bazel will use ${N_JOBS} concurrent job(s)."
echo ""

export CC_OPT_FLAGS='-mavx'
export TF_NEED_CUDA=0 # TODO: Verify this is used in GPU custom-op

export PYTHON_BIN_PATH=`which python`

python --version
python -m pip --version
docker  --version

export PYTHON_VERSION=3.8

export BAZEL_VERSION=$(cat .bazelversion)
export BAZEL_OPTIMIZATION="--copt=-msse4.2 --copt=-mavx --compilation_mode=opt"
export BAZEL_OS=$(uname | tr '[:upper:]' '[:lower:]')

docker run -i --rm -v $PWD:/v -w /v --net=host \
  -e BAZEL_VERSION=${BAZEL_VERSION} \
  -e BAZEL_OPTIMIZATION="${BAZEL_OPTIMIZATION}" \
  gcr.io/tensorflow-testing/nosla-ubuntu16.04-manylinux2010@sha256:3a9b4820021801b1fa7d0592c1738483ac7abc209fc6ee8c9ef06cf2eab2d170 /v/.github/workflows/build.bazel.sh

sudo chown -R $(id -nu):$(id -ng) .

docker run -i --rm --user $(id -u):$(id -g) -v /etc/password:/etc/password -v $PWD:/v -w /v --net=host \
  python:${PYTHON_VERSION}-slim python setup.py --data build -q bdist_wheel

ls dist/*
for f in dist/*.whl; do
  docker run -i --rm -v $PWD:/v -w /v --net=host \
    quay.io/pypa/manylinux2010_x86_64 bash -x -e /v/tools/build/auditwheel repair --plat manylinux2010_x86_64 $f
done

sudo chown -R $(id -nu):$(id -ng) .
ls wheelhouse/*

## Set test services
bash -x -e tests/test_gcloud/test_gcs.sh gcs-emulator
bash -x -e tests/test_kafka/kafka_test.sh
bash -x -e tests/test_pulsar/pulsar_test.sh
bash -x -e tests/test_aws/aws_test.sh
bash -x -e tests/test_pubsub/pubsub_test.sh pubsub
bash -x -e tests/test_prometheus/prometheus_test.sh start
bash -x -e tests/test_azure/start_azure.sh
bash -x -e tests/test_sql/sql_test.sh sql
bash -x -e tests/test_elasticsearch/elasticsearch_test.sh start

docker run -i --rm -v $PWD:/v -w /v --net=host \
  buildpack-deps:20.04 bash -x -e .github/workflows/build.wheel.sh python${PYTHON_VERSION}

## In case there are any files generated by docker with root user
sudo chown -R $(id -nu):$(id -ng) .

exit $?
