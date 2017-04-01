# docker-ci.mk
#
# Copyright (c) 2017, Full 360 Inc
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the organization nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL HERBERT G. FISCHER BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

# Check DOCKER_CI_REPO
ifndef DOCKER_CI_REPO
$(warning warning - DOCKER_CI_REPO is not set. assuming local build)
DOCKER_CI_REPO=
endif

ifdef BUILDARGS
$(foreach B,$(BUILDARGS),$(eval DOCKERBUILDARGS+=--build-arg $(B)))
else
endif

ifndef DOCKERBUILDARGS
DOCKERBUILDARGS=
endif

ifndef IMAGEDOCKERBUILDARGS
IMAGEDOCKERBUILDARGS=
endif


# Default is to not cache when building
ifndef NOCACHE
NOCACHE=--no-cache
else
override NOCACHE=
endif

ifdef LOCALONLY
override DOCKER_CI_REPO=
override PULL=
else
PULL=--pull
endif

# Default is to not cache when building
ifdef DRY_RUN
ifeq (,$(DRY_RUN))
# Only echo docker commands
# DRY_RUN not eq to blank
DOCKER := echo docker
else
# DRY_RUN is blank
DOCKER := docker
endif
else
# DRY_RUN is not set
DOCKER := docker
endif

# Check if logging into AWS ECR is needed
ifndef ECRACCOUNTID
ifneq (,$(findstring dkr.ecr,$(DOCKER_CI_REPO)))
ECRACCOUNTID := $(firstword $(subst ., ,$(DOCKER_CI_REPO)))
AWSECRNAMESPACE := $(lastword $(subst /, ,$(DOCKER_CI_REPO)))
endif
endif

ifneq (,$(DOCKER_CI_REPO))
override DOCKER_CI_REPO := $(DOCKER_CI_REPO)/
endif

##########################################################################################
# Definitions
##########################################################################################

define create_ecr_repo
# Check if AWS ECR
-aws ecr create-repository --repository-name $(AWSECRNAMESPACE)/$(1) >/dev/null 2>&1 | true
endef

# parse the Dockerfile to extract the build variables stored in LABEL
define get_label
$(shell cat $1 | awk -F'"' 'BEGIN {ver="null"} /build.publish.$2/ {ver=$$2} END { print ver }')
endef

# add item to variable if it does not already exist in list
define add_var
ifeq (,$(filter $1,$($2)))
	$2 += $1
endif
endef

# extract group name from Dockerfile relative path in FAKESEMAPHORE
define group
$(firstword $(subst /, ,$1))
endef

define ucase
$(shell echo $1| tr '[:lower:]' '[:upper:]')
endef

# c name from Dockerfile relative path in FAKESEMAPHORE
define image_basename
$(shell echo $1 |sed -e 's/$2-//')
endef

# strip prefix and prefix period
define image
$(shell echo $1 |sed -e 's/$2-//'|sed -e 's/\/\./\//')
endef

# if a major or minor label is not found, the FAKESEMAPHORE will be set to null
define fix_nulls
$(shell echo $1 |sed -e 's/null/latest/'|sed -e 's/-null//')
endef

define semaphore_from_dockerfile
$(call group,$1)-$(call get_label,$1,majorversion)-$(call get_label,$1,imagebase)
endef

define imagebase_from_dockerfile
$(call fix_nulls,$(call group,$1)-$(call get_label,$1,majorversion)-$(call get_label,$1,imagebase))
endef

define image_from_dockerfile
$(call fix_nulls,$(DOCKER_CI_REPO)$(call group,$1):$(call get_label,$1,majorversion)-$(call get_label,$1,imagebase))
endef

define semaphore
$(call fix_nulls,$2/.$1-$(call semaphore_from_dockerfile,$2/Dockerfile))
endef

define docker_tag
$(call group,$1):$(patsubst $(call group,$1)-%,%,$(notdir $(call image,$1,$2)))
endef

define docker_tag_latest
$(if $(findstring latest,$(call docker_tag,$1,$3)),,$(DOCKER) tag $(DOCKER_CI_REPO)$(call docker_tag,$1,$3) $(DOCKER_CI_REPO)$(call group,$2):latest)

$(if $(DOCKER_CI_REPO),,$(if $(findstring latest,$(call docker_tag,$1,$3)),,$(DOCKER) tag $(DOCKER_CI_REPO)$(call docker_tag,$1,$3) $(DOCKER_CI_REPO)$(call group,$2):latest))
endef

define docker_tag_minor
$(if $(filter-out null,$(call get_label,$2,minor)),$(DOCKER) tag $(DOCKER_CI_REPO)$(call docker_tag,$1,$3) $(DOCKER_CI_REPO)$(call group,$2):$(call get_label,$2,minor)$(if $(filter-out null,$(call get_label,$2,imagebase)),-$(call get_label,$2,imagebase),),)

$(if $(DOCKER_CI_REPO),,$(if $(filter-out null,$(call get_label,$2,minor)),$(DOCKER) tag $(DOCKER_CI_REPO)$(call docker_tag,$1,$3) $(DOCKER_CI_REPO)$(call group,$2):$(call get_label,$2,minor)$(if $(filter-out null,$(call get_label,$2,imagebase)),-$(call get_label,$2,imagebase),),))
endef

define docker_push_latest
$(DOCKER) push $(DOCKER_CI_REPO)$(call docker_tag,$1,$3)
endef

define docker_push_minor
$(if $(filter-out null,$(call get_label,$2,minor)),$(DOCKER) push $(DOCKER_CI_REPO)$(call group,$2):$(call get_label,$2,minor)$(if $(filter-out null,$(call get_label,$2,imagebase)),-$(call get_label,$2,imagebase),),)
endef

# this define creates the base targets and dependencies based on each fake
# semaphore. There is no way due to the way make works to filter a list of
# prerequisites. See:
# http://stackoverflow.com/questions/13592154/gnu-make-using-the-filter-function-in-prerequisites
# inputs - OPERATION (build, tag, push etc.), FAKESEMAPHORE
define make-semaphore-deps
# Add group to a variable
$(call add_var,$(call group,$2),GROUPS)

# build a list with the images that go with that group
$(call add_var,$(notdir $(call image,$2,$1)),$(call ucase,$(call group,$2))DEPS)

# build a list with images (for debugging)
$(call add_var,$(notdir $(call image,$2,$1)),IMAGES)

# build a list of operational semaphores to use later as a target
$(call ucase,$1)SEMAPHORES += $2

##################
# Set Dependencies with this graph
# group and image depends on image_basename, depends on semaphore, depends on Dockerfile
##################

$(call group,$2)              : $1-$(call group,$2)

# create a target for the group-operation (gobuild)
$1-$(call group,$2)          : $1-$(notdir $(call image,$2,$1))

# create a target for each image using the basename
$(notdir $(call image,$2,$1)) : $1-$(notdir $(call image,$2,$1))

# create a target for each operation-basename using the image
$1-$(notdir $(call image,$2,$1))  : $2

$2	: $(dir $2)Dockerfile

endef

# find all docker files in local subdirectories
DOCKERDIRS := $(shell \
               find * -mindepth 1 -type f -name Dockerfile | xargs -L1 dirname )
DOCKERFILES := $(DOCKERDIRS:%=%/Dockerfile)

################################################################################
# For each operation that depends on the Dockerfile create the semaphores
# and set the dependencies
################################################################################
OPERATIONS = build tag push
$(foreach O, $(OPERATIONS), \
  $(foreach D, $(DOCKERDIRS), $(eval $(call make-semaphore-deps,$O,$(call semaphore,$O,$D)))))

################################################################################
# Docker Build Target
################################################################################
# set the semaphore target to be dependent on the Dockerfile
$(BUILDSEMAPHORES) :
ifneq (,$(DOCKERBUILDARGS))
	$(info buildargs: $(DOCKERBUILDARGS))
endif
	$(foreach B,$($(call imagebase_from_dockerfile,$(dir $<)Dockerfile).BUILDARGS),$(eval IMAGEDOCKERBUILDARGS+=--build-arg $(B)))
	@echo Building: $< && \
	cd $(dir $<) && \
	$(DOCKER) build $(NOCACHE) $(DOCKERBUILDARGS) $(IMAGEDOCKERBUILDARGS) $(PULL) -t $(DOCKER_CI_REPO)$(call docker_tag,$@,build) .
	$(eval IMAGEDOCKERBUILDARGS=)

.PHONY: build
build : $(BUILDSEMAPHORES)

################################################################################
# Docker Tag Target
################################################################################
$(TAGSEMAPHORES) :
	@echo	Tagging: $<
	@$(call docker_tag_latest,$@,$<,tag)
	@$(call docker_tag_minor,$@,$<,tag)
	@exit 0

.PHONY: tag
tag : $(TAGSEMAPHORES)

################################################################################
# Docker Push Target
################################################################################
$(PUSHSEMAPHORES) :
ifneq (,$(DOCKER_CI_REPO))
ifdef ECRACCOUNTID
	$(info Docker repo is AWS ECR, logging in)
	$(info $(shell eval $$(aws ecr get-login --registry-ids $(ECRACCOUNTID))))
	@echo	Pushing: $<
	@$(call create_ecr_repo,$(call group,$@))
	@$(call docker_push_latest,$@,$<,push)
	@$(call docker_push_minor,$@,$<,push)
	@exit 0
endif
else
	@echo Local Only, not pushing
endif

.PHONY: push
push : $(PUSHSEMAPHORES)

.PHONY: all
all: $(GROUPS)

.PHONY: clean
clean:
	@find . -type f -name .build-* -exec rm {} \; && \
	find . -type f -name .tag-* -exec rm {} \; && \
	find . -type f -name .push-* -exec rm {} \;

.PHONY: mkhelp
mkhelp:
	$(info Available docker-ci.mk targets:       )
	$(foreach O, $(OPERATIONS),  $(info | $(O))  )
	$(info | clean                               )
	$(info | mkhelp                              )
	$(info | showgroups                          )
	$(info | showimages                          )
	$(info | inspectgroup.GROUP                  )
	$(info | inspectimg.IMAGE                    )
	$(info | inspect.VAR                         )
	@exit 0

.PHONY: showimages
showimages:
	$(foreach I, $(IMAGES),  $(info | $(I))      )
	@exit 0

.PHONY: showgroups
showgroups:
	$(foreach G, $(GROUPS), $(info | $(G))       )
	@exit 0

inspectgroup.%:
	$(info Available targets for $*:                               )
	$(info | $*                                                    )
	$(foreach O, $(OPERATIONS),  $(info | $(O)-$*)                 )
	$(info                                                         )
	$(info Images associated with $*:                              )
	$(foreach F, $($(call ucase,$*)DEPS),$(info | $(notdir $F))    )
	@exit 0

inspectimg.%:
	$(info Dockerfile associated with $*: \
	  ./$(dir $(filter %$*, $(BUILDSEMAPHORES)))Dockerfile         )
	$(info                                                         )
	$(foreach O, $(OPERATIONS), \
	  $(foreach I, $(filter $*,$(IMAGES)),  $(info | $(O)-$(I)))   )
	@exit 0

# %: all


# debug variable values
inspect.%  : ; @echo $* = $($*)
