#! /bin/bash
#
# Build this package and upload it to s3.
# Has many undocumented assumptions, probably you should edit it before using it.
#
# Before using this:
# - on mac:
#   if you have never done this, you may need to:
#    $  brew install bison && brew link --force bison
#   and/or:
#    $ echo 'export PATH="/usr/local/opt/bison/bin:$PATH"' >> ~/.zshrc
#   Also, I had to:
#    $ ln -s /usr/local/opt/openssl/lib/openssl /usr/local/lib
#    $ ln -s /usr/local/opt/openssl/include/openssl /usr/local/include
#
# YMMV
set -u
set -e
set -x


git diff-files --quiet || (echo 'Git tree is dirty' ; false)

GIT_SHA=`git rev-parse --verify HEAD`
VERSION_NAME=1.0.0-${GIT_SHA:0:10}-compass-finagle

# If you want to release:
# - update the version name below,
# - update version in configure.ac
# - update version in lib/python/setup.py
# - run this file as THRIFT_RELEASE=y ./compass_build_and_upload.sh
if [ ! -z "${THRIFT_RELEASE:-}" ] ; then
  VERSION_NAME=1.0.0.compass20171028
  TODAYS_RELEASE="1.0.0.compass$(date +%Y%m%d)"
  if [ "${VERSION_NAME}" != "${TODAYS_RELEASE}" ]; then
    echo "Invalid version: ${VERSION_NAME} - should be: ${TODAYS_RELEASE}"
    echo "If you are only testing, unset the environment_variable THRIFT_RELEASE"
    false
  fi
fi

git clean -fdx
./bootstrap.sh
./configure
make

if [ "$(uname)" = "Darwin" ] ; then
  MAC_VERSION=`sw_vers | sed -n "s/ProductVersion:[^0-9]*\\([0-9][0-9]*\\.[0-9][0-9]*\\)\\..*/\\1/p"`
  # HACK(ugo): reproduce build-support/bazel/thrift_compiler.bzl hack.
  MAC_VERSION="10.11"
  PLATFORM=mac/${MAC_VERSION}
  LINUX_BIN_SHA="unknown"
  MAC_BIN_SHA=`shasum -a 256 compiler/cpp/thrift | cut -d ' ' -f 1`
else
  PLATFORM=linux/x86_64
  LINUX_BIN_SHA=`sha256sum compiler/cpp/thrift`
  MAC_BIN_SHA="unknown"
fi
aws s3 cp compiler/cpp/thrift \
  s3://compass-build-support/bin/thrift/${PLATFORM}/${VERSION_NAME}/thrift \
  --acl public-read

WORKSPACE_FNAME=${HOME}/development/urbancompass/WORKSPACE
cat > ${WORKSPACE_FNAME} <<!
load("//build-support/bazel:thrift_compiler.bzl", "thrift_compiler")

thrift_compiler(
    name = "thrift_java_finagle",
    linux_sha256 = "${LINUX_BIN_SHA}",
    mac_sha256 = "${MAC_BIN_SHA}",
    version = "${VERSION_NAME}",
)

thrift_compiler(
    name = "thrift_java",
    linux_sha256 = "${LINUX_BIN_SHA}",
    mac_sha256 = "${MAC_BIN_SHA}",
    version = "${VERSION_NAME}",
)

load("//3rdparty:java_deps.bzl", "include_java_deps")

include_java_deps()
!

echo "Edited file ${WORKSPACE_FNAME}"
