# Copyright 2015 The Vanadium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

SHELL := /bin/bash -euo pipefail

ifdef USE_MOJO_DEV_PROFILE
	MOJO_PROFILE := v23:mojodev
else
	MOJO_PROFILE := v23:mojo
endif

ifdef ANDROID
	TARGET := arm-android
	MOJO_ANDROID_FLAGS := --android

	# Put adb in front of $PATH.
	export PATH := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) ANDROID_PLATFORM_TOOLS=):$(PATH)
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
PATH := $(shell jiri profile env --profiles=v23:dart DART_SDK=)/bin:$(PATH)

# Set variables from environment based on profile and target.
MOJO_DEVTOOLS := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_DEVTOOLS=)
MOJO_SDK := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SDK=)
MOJO_SERVICES := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SERVICES=)
MOJO_SHARED_LIB := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SYSTEM_THUNKS=)
MOJO_SHELL := $(shell jiri profile env --profiles=$(MOJO_PROFILE) --target=$(TARGET) MOJO_SHELL=)

export GOPATH := $(GOPATH):$(CURDIR)/go:$(CURDIR)/gen/go

# NOTE(nlacasse): Running Go Mojo services requires passing the
# --enable-multiprocess flag to mojo_shell.  This is because the Go runtime is
# very large, and can interfere with C++ memory if they are in the same
# process.
MOJO_SHELL_FLAGS := -v --enable-multiprocess

# Generates go bindings from .mojom file.
# $1 is input filename.
# $2 is root directory containing mojom files.
# $3 is output directory.
# $4 is language (go, dart, ...).
# $5 is for any extra flags you want to add, like "--generate-type-info".
define MOJOM_GEN
	mkdir -p $3
	$(MOJO_SDK)/src/mojo/public/tools/bindings/mojom_bindings_generator.py $1 -I $2 -d $2 -o $3 -g $4 $5
endef

# Compiles a Go program and links against the Mojo C library.
# $1 is input filename.
# $2 is output filename.
define MOGO_BUILD
	mkdir -p $(dir $2)
	jiri go -profiles=$(MOJO_PROFILE),v23:base -target=$(TARGET) build -o $2 -tags="mojo include_mojo_cgo" -ldflags="$(LDFLAGS)" -buildmode=c-shared $1
endef

# Runs Go tests with mojo libraries.
# $1 is input package pattern
define MOGO_TEST
	jiri go -profiles=$(MOJO_PROFILE),v23:base test $1
endef

# On Linux we need to use a different $HOME directory for each mojo run
# to avoid collision of the cache storage.
define MOJO_RUN
	set -e; HOME=$$(mktemp -d); trap "rm -rf $$HOME" EXIT; \
	$(MOJO_DEVTOOLS)/mojo_run --config-file $(CURDIR)/mojoconfig --shell-path $(MOJO_SHELL) $(MOJO_SHELL_FLAGS) $(MOJO_ANDROID_FLAGS) $1
endef

# Runs mojo app tests.
# $1 is apptest list filename.
define MOJO_APPTEST
	$(MOJO_DEVTOOLS)/mojo_test --config-file $(CURDIR)/mojoconfig --shell-path $(MOJO_SHELL) $(MOJO_SHELL_FLAGS) --disable-cache $(MOJO_ANDROID_FLAGS) $1
endef

.PHONY: mojo-env-check
mojo-env-check:
ifndef JIRI_ROOT
	$(error JIRI_ROOT is not set)
endif
# TODO(aghassemi): Switch to profile-v23 when mojo is available via the new profiles
# TODO(aghassemi): v23-profile list or profile-v23 available no longer print out
# the targets, we need that to ensure profile is installed for the right target.
ifeq ($(shell jiri profile list | grep v23:dart),)
	$(error dart profile not installed. Run "jiri profile install v23:dart")
endif
ifeq ($(shell jiri profile list | grep $(MOJO_PROFILE)),)
	$(error profile $(MOJO_PROFILE) not installed. Run "jiri profile install --target=$(TARGET) $(MOJO_PROFILE)")
endif
