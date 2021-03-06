#!/usr/bin/env bash
#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

set -e

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source "$DIR/../common/_common.sh"

[ ! -z "$TFM" ] || die "Missing required environment variable TFM"
[ ! -z "$RID" ] || die "Missing required environment variable RID"
[ ! -z "$CONFIGURATION" ] || die "Missing required environment variable CONFIGURATION"
[ ! -z "$OUTPUT_DIR" ] || die "Missing required environment variable OUTPUT_DIR"
[ ! -z "$HOST_DIR" ] || die "Missing required environment variable HOST_DIR"
[ ! -z "$COMPILATION_OUTPUT_DIR" ] || die "Missing required environment variable COMPILATION_OUTPUT_DIR"

PROJECTS=( \
    Microsoft.DotNet.Cli \
    Microsoft.DotNet.ProjectModel.Server \
    Microsoft.DotNet.Tools.Builder \
    Microsoft.DotNet.Tools.Compiler \
    Microsoft.DotNet.Tools.Compiler.Csc \
    Microsoft.DotNet.Tools.Compiler.Fsc \
    Microsoft.DotNet.Tools.Compiler.Native \
    Microsoft.DotNet.Tools.Mcg \
    Microsoft.DotNet.Tools.New \
    Microsoft.DotNet.Tools.Pack \
    Microsoft.DotNet.Tools.Publish \
    Microsoft.DotNet.Tools.Repl \
    Microsoft.DotNet.Tools.Repl.Csi \
    dotnet-restore \
    Microsoft.DotNet.Tools.Resgen \
    Microsoft.DotNet.Tools.Run \
    Microsoft.DotNet.Tools.Test \
)

BINARIES_FOR_COREHOST=( \
    csi \
    csc \
    vbc \
)

FILES_TO_CLEAN=( \
    README.md \
    Microsoft.DotNet.Runtime \
    Microsoft.DotNet.Runtime.dll \
    Microsoft.DotNet.Runtime.deps \
    Microsoft.DotNet.Runtime.pdb \
)

RUNTIME_OUTPUT_DIR="$OUTPUT_DIR/runtime/coreclr"
BINARIES_OUTPUT_DIR="$COMPILATION_OUTPUT_DIR/bin/$CONFIGURATION/$TFM"
RUNTIME_BINARIES_OUTPUT_DIR="$COMPILATION_OUTPUT_DIR/runtime/coreclr/$CONFIGURATION/$TFM"

mkdir -p "$OUTPUT_DIR/bin"
mkdir -p "$RUNTIME_OUTPUT_DIR"

for project in ${PROJECTS[@]}
do
    echo dotnet publish --native-subdirectory --framework "$TFM" --output "$COMPILATION_OUTPUT_DIR/bin" --configuration "$CONFIGURATION" "$REPOROOT/src/$project"
    dotnet publish --native-subdirectory --framework "$TFM" --output "$COMPILATION_OUTPUT_DIR/bin" --configuration "$CONFIGURATION" "$REPOROOT/src/$project"
done

if [ ! -d "$BINARIES_OUTPUT_DIR" ]
then
    BINARIES_OUTPUT_DIR="$COMPILATION_OUTPUT_DIR/bin"
fi
cp -R -f $BINARIES_OUTPUT_DIR/* $OUTPUT_DIR/bin

# Bring in the runtime
dotnet publish --output "$COMPILATION_OUTPUT_DIR/runtime/coreclr" --configuration "$CONFIGURATION" "$REPOROOT/src/Microsoft.DotNet.Runtime"

if [ ! -d "$RUNTIME_BINARIES_OUTPUT_DIR" ]
then
    RUNTIME_BINARIES_OUTPUT_DIR="$COMPILATION_OUTPUT_DIR/runtime/coreclr"
fi
cp -R -f $RUNTIME_BINARIES_OUTPUT_DIR/* $RUNTIME_OUTPUT_DIR

# Clean up bogus additional files
for file in ${FILES_TO_CLEAN[@]}
do
    [ -e "$RUNTIME_OUTPUT_DIR/$file" ] && rm "$RUNTIME_OUTPUT_DIR/$file"
done

# Copy the runtime app-local for the tools
cp -R $RUNTIME_OUTPUT_DIR/* $OUTPUT_DIR/bin

# Deploy CLR host to the output
if [[ "$OSNAME" == "osx" ]]; then
   COREHOST_LIBNAME=libhostpolicy.dylib
else
   COREHOST_LIBNAME=libhostpolicy.so
fi
cp "$HOST_DIR/corehost" "$OUTPUT_DIR/bin"
cp "$HOST_DIR/${COREHOST_LIBNAME}" "$OUTPUT_DIR/bin"

# corehostify externally-provided binaries (csc, vbc, etc.)
for binary in ${BINARIES_FOR_COREHOST[@]}
do
    cp $OUTPUT_DIR/bin/corehost $OUTPUT_DIR/bin/$binary
    mv $OUTPUT_DIR/bin/${binary}.exe $OUTPUT_DIR/bin/${binary}.dll
done

cd $OUTPUT_DIR

# Fix up permissions. Sometimes they get dropped with the wrong info
find . -type f | xargs chmod 644
$REPOROOT/scripts/build/fix-mode-flags.sh

if [ ! -f "$OUTPUT_DIR/bin/csc.ni.exe" ]; then
    info "Crossgenning Roslyn compiler ..."
    $REPOROOT/scripts/crossgen/crossgen_roslyn.sh "$OUTPUT_DIR/bin"
fi

# Make OUTPUT_DIR Folder Accessible
chmod -R a+r $OUTPUT_DIR

# No compile native support in centos yet
# https://github.com/dotnet/cli/issues/453
if [ "$OSNAME" != "centos" ]; then
    # Copy in AppDeps
    if [ ! -d "$OUTPUT_DIR/bin/appdepsdk" ]; then
        header "Acquiring Native App Dependencies"
        DOTNET_HOME=$OUTPUT_DIR DOTNET_TOOLS=$OUTPUT_DIR $REPOROOT/scripts/build/build_appdeps.sh "$OUTPUT_DIR/bin"
    fi
fi

# Stamp the output with the commit metadata
COMMIT=$(git rev-parse HEAD)
echo $COMMIT > $OUTPUT_DIR/.version
echo $DOTNET_CLI_VERSION >> $OUTPUT_DIR/.version
