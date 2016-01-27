# Copyright 2015 The Vanadium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

SHELL := /bin/bash -euo pipefail

ifdef USE_MOJO_DEV_PROFILE
	MOJO_PROFILE := mojo-dev
else
	MOJO_PROFILE := mojo
endif

ifdef ANDROID
	TARGET := arm-android
	MOJO_ANDROID_FLAGS := --android

	# Put adb in front of $PATH.
	export PATH := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) ANDROID_PLATFORM_TOOLS=):$(PATH)
else
	TARGET := amd64-linux
endif

LDFLAGS := -shared
ifdef RELEASE
	# Configure ldflags to omit debug information.
	# See https://golang.org/doc/gdb
	#
	# NOTE(nlacasse): The Go team recommends passing "-w" to strip debug
	# information instead of "-s" (https://codereview.appspot.com/88030045).
	# It appears that "-s" used to strip the pclntab and thus mangle panic
	# traces, but that is no longer the behavior (as of
	# https://codereview.appspot.com/88030045).
	# I've left the "-s" for now, since it seems to work and panic traces look
	# fine, but if other issues arise we should switch to "-w".
	LDFLAGS += -s
endif


# Add Dart SDK to path.
PATH := $(shell jiri v23-profile env --profiles=dart DART_SDK=)/bin:$(PATH)

# Set variables from environment based on profile and target.
MOJO_DEVTOOLS := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_DEVTOOLS=)
MOJO_SDK := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SDK=)
MOJO_SERVICES := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SERVICES=)
MOJO_SHARED_LIB := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SYSTEM_THUNKS=)
MOJO_SHELL := $(shell jiri v23-profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SHELL=)

export GOPATH := $(GOPATH):$(CURDIR)/go:$(CURDIR)/gen/go

# NOTE(nlacasse): Running Go Mojo services requires passing the
# --enable-multiprocess flag to mojo_shell.  This is because the Go runtime is
# very large, and can interfere with C++ memory if they are in the same
# process.
MOJO_SHELL_FLAGS := -v --enable-multiprocess

# Compiles a Go program and links against the Mojo C library.
# $1 is input filename.
# $2 is output filename.
define MOGO_BUILD
	mkdir -p $(dir $2)
	jiri go -profiles=$(MOJO_PROFILE),base -target=$(TARGET) build -o $2 -tags="mojo include_mojo_cgo" -ldflags="$(LDFLAGS)" -buildmode=c-shared $1
endef

# Runs Go tests with mojo libraries
# $1 is input package pattern
define MOGO_TEST
	jiri go -profiles=$(MOJO_PROFILE),base test $1
endef

# Generates go bindings from .mojom file.
# $1 is input filename.
# $2 is root directory containing mojom files.
# $3 is output directory.
# $4 is language (go, dart, ...).
define MOJOM_GEN
	mkdir -p $3
	$(MOJO_SDK)/src/mojo/public/tools/bindings/mojom_bindings_generator.py $1 -I $2 -d $2 -o $3 -g $4 $5
endef

define MOJO_RUN
	$(MOJO_DEVTOOLS)/mojo_run --config-file $(CURDIR)/mojoconfig --shell-path $(MOJO_SHELL) $(MOJO_SHELL_FLAGS) $(MOJO_ANDROID_FLAGS) $1
endef

.PHONY: mojo-env-check
mojo-env-check:
ifndef JIRI_ROOT
	$(error JIRI_ROOT is not set)
endif
ifeq ($(shell jiri v23-profile list dart),)
	$(error dart profile not installed. Run "jiri v23-profile install dart")
endif
ifeq ($(shell jiri v23-profile list $(MOJO_PROFILE) | grep $(TARGET)),)
	$(error profile $(MOJO_PROFILE) not installed for target $(TARGET). Run "jiri v23-profile install --target=$(TARGET) $(MOJO_PROFILE)")
endif
