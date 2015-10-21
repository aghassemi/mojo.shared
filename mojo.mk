# Copyright 2015 The Vanadium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

SHELL := /bin/bash -euo pipefail
V23_GOPATH := $(shell echo `jiri run env | grep GOPATH | cut -d\= -f2`)

ifdef ANDROID
	# Configure compiler and linker for Android.
	export GOROOT := $(MOJO_DIR)/src/third_party/go/tool/android_arm
	export CGO_ENABLED := 1
	export GOOS := android
	export GOARCH := arm
	export GOARM := 7

	ANDROID_NDK := $(JIRI_ROOT)/third_party/android/ndk-toolchain

	export CC := $(ANDROID_NDK)/bin/arm-linux-androideabi-gcc
	export CXX := $(ANDROID_NDK)/bin/arm-linux-androideabi-g++

	MOJO_ANDROID_FLAGS := --android
	MOJO_BUILD_DIR := $(MOJO_DIR)/src/out/android_Debug
	MOJO_SHARED_LIB := $(PWD)/gen/lib/android/libsystem_thunk.a
	MOJO_SHELL_PATH := $(MOJO_BUILD_DIR)/apks/MojoShell.apk
else
	# Configure compiler and linker for Linux.
	export GOROOT := $(MOJO_DIR)/src/third_party/go/tool/linux_amd64

	MOJO_BUILD_DIR := $(MOJO_DIR)/src/out/Debug
	MOJO_SHARED_LIB := $(PWD)/gen/lib/linux_amd64/libsystem_thunk.a
	MOJO_SHELL_PATH := $(MOJO_BUILD_DIR)/mojo_shell
endif

GOPATH := $(V23_GOPATH):$(MOJO_DIR):$(MOJO_DIR)/third_party/go:$(MOJO_BUILD_DIR)/gen/go:$(PWD)/go:$(PWD)/gen/go

# NOTE(nlacasse): Running Go Mojo services requires passing the
# --enable-multiprocess flag to mojo_shell.  This is because the Go runtime is
# very large, and can interfere with C++ memory if they are in the same
# process.
MOJO_SHELL_FLAGS := -v --enable-multiprocess \
	--config-alias MOJO_BUILD_DIR=$(MOJO_BUILD_DIR)

LDFLAGS := -shared

# Compiles a Go program and links against the Mojo C library.
# $1 is input filename.
# $2 is output filename.
define MOGO_BUILD
	mkdir -p $(dir $2)
	GOPATH="$(GOPATH)" \
	CGO_CFLAGS="-I$(MOJO_DIR)/src $(CGO_CFLAGS)" \
	CGO_CXXFLAGS="-I$(MOJO_DIR)/src $(CGO_CXXFLAGS)" \
	CGO_LDFLAGS="-L$(dir $(MOJO_SHARED_LIB)) -lsystem_thunk $(CGO_LDFLAGS)" \
	$(GOROOT)/bin/go build -o $2 -tags=mojo -ldflags="$(LDFLAGS)" -buildmode=c-shared $1
	rm -f $(basename $2).h
endef

# Runs Go tests with mojo libraries
# $1 is input package pattern
define MOGO_TEST
	GOPATH="$(GOPATH)" \
	CGO_CFLAGS="-I$(MOJO_DIR)/src $(CGO_CFLAGS)" \
	CGO_CXXFLAGS="-I$(MOJO_DIR)/src $(CGO_CXXFLAGS)" \
	CGO_LDFLAGS="-L$(dir $(MOJO_SHARED_LIB)) -lsystem_thunk $(CGO_LDFLAGS)" \
	$(GOROOT)/bin/go test $1
endef

# Generates go bindings from .mojom file.
# $1 is input filename.
# $2 is root directory containing mojom files.
# $3 is output directory.
# $4 is language (go, dart, ...).
define MOJOM_GEN
	mkdir -p $3
	$(MOJO_DIR)/src/mojo/public/tools/bindings/mojom_bindings_generator.py $1 -d $2 -o $3 -g $4
endef

define MOJO_RUN
	$(MOJO_DIR)/src/mojo/devtools/common/mojo_run --config-file $(PWD)/mojoconfig $(MOJO_SHELL_FLAGS) $(MOJO_ANDROID_FLAGS) $1
endef

# Builds the library that Mojo services must be linked with.
$(MOJO_SHARED_LIB): $(MOJO_BUILD_DIR)/obj/mojo/public/platform/native/system.system_thunks.o | mojo-env-check
	mkdir -p $(dir $@)
	ar rcs $@ $(MOJO_BUILD_DIR)/obj/mojo/public/platform/native/system.system_thunks.o

.PHONY: mojo-env-check
mojo-env-check:
ifndef MOJO_DIR
	$(error MOJO_DIR is not set)
endif
ifndef JIRI_ROOT
	$(error JIRI_ROOT is not set)
endif
ifeq ($(wildcard $(MOJO_BUILD_DIR)),)
	$(error ERROR: $(MOJO_BUILD_DIR) does not exist.  Please see README.md for instructions on compiling Mojo resources.)
endif
ifdef ANDROID
ifeq ($(wildcard $(ANDROID_NDK)),)
	$(error ERROR: $(ANDROID_NDK) does not exist.  Please install android profile with "jiri profile install android")
endif
endif
