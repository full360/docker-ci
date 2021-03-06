## Makefile Environment Variables
- `NOCACHE`: Don't use a cache during build
- `DOCKER_CI_REPO`: which docker repo, not setting it will build locally. Using an AWS ECR will trigger a login during the build process.
- `BUILDARGS`: Docker Build `--build-args`

## An Opinionated Docker Makefile
The new makefile is setup to make it easier to automate the container builds both during development and for CI workflows. It is based on the work done here https://github.com/rbuckland/docker-makefile

The Makefile uses the top-level directory where the Dockerfile is located (_group_ for e.g. `jruby`) and values set in the Dockerfile using the `LABEL` directive to create make targets, both at the group level and the image level and is also used to create the Docker image label. The labels are:
- `build.publish.imagebase` : the base image for e.g. `docker`
- `build.publish.majorversion` : the major version for e.g. `1`
- `build.publish.minorversion` : the minor version for e.g. `1.11`

Using these, the auto generated build targets are:
1. _groups_ that are based on the top level directory that the Dockerfiles are found
2. _images_ that are based on the basename + majorversion set in the Dockerfile labels.

If the labels don't exist, the Makefile will generate the image using `latest` as the version and the group as the image name.

#### Examples
A Dockerfile in `jruby/9.1/alpine-jre/Dockerfile` with
```
LABEL build.publish.majorversion="1"
LABEL build.publish.minorversion="1.11"
LABEL build.publish.imagebase="docker"
```
creates the following make build targets:
- Group: `docker-ci`
- Image: `docker-ci-1-docker`
- docker image: `docker-ci:1-docker`
- docker tags: `docker-ci:latest` and `docker:1.11-docker`

### To Use
Using this in a docker project is simple, create a Makefile, and add the following to pull this down and include it. Add docker-ci.mk to your .gitignore so your build process picks up the latest.

```
REGISTRY_ID ?= <set this to your ecr registry, if using ecr>
REGISTRY_REGION ?= <set to ecr region
REGISTRY ?= $(REGISTRY_ID).dkr.ecr.$(REGISTRY_REGION).amazonaws.com
REGISTRY_NAMESPACE ?= <set to some namespace>
DOCKER_CI_REPO ?= $(REGISTRY)/$(REGISTRY_NAMESPACE)

# USECACHE = true
# DRYRUN = true

DOCKERMK := $(shell if [ ! -e docker-ci.mk ]; then \
                    wget -N -q https://raw.githubusercontent.com/full360/docker-ci/master/docker-ci.mk; fi)
include docker-ci.mk
```
then run `make mkhelp` to see the list of available make commands that this makefile provides. By default the following targets are provided:
```
Available docker-ci.mk targets:
| build
| tag
| push
| clean
| mkhelp
| showgroups
| showimages
| inspectgroup.GROUP
| inspectimg.IMAGE
| inspect.VAR
```

### How it works
The Makefile uses some trickery with semaphore files to get the dependencies correct. To start it finds all the Dockerfiles and uses it to construct a base semaphore list, for the above example:
this semaphore is added to a variable (along with similar ones constructed for each Dockerfile found): `docker-ci/.pre-docker-9.1-jre-alpine`. This list can be seen by running `make mkhelp`

This semaphore list + the operation we want to run (`build`, `tag` etc.) is then passed into a define function that extracts from each semaphore:
1. the group (top level directory) and saves it in the `groups` variable. This list can be seen by running `make showgroups`
2. the semaphores that lie under that _group_ directory and add it to variables with the format `{group}_deps`. This list can be seen in the docker example with `make inspectgroup.GROUP` where GROUP is the group name
3. extracts the image name and adds it to variable `images`. This list can be seen with `make showimages`. You can inspect particular images that `showimages` by running make `inspectimg.IMAGE`
4. In the above cases the `pre-` is stripped before adding to the variables

Then (this is the magic part) each semaphore is modified to replace `pre-` with the operation `build-` or `tag-` for example, and added to the dependency list for each image, and each image is added to the dependency list for each group. Lastly every operation based semaphore is made dependent on the Droolsfile.

When the dependency graph is constructed, if the semaphore is not found as a dependency of the Droolsfile it runs the operations for that Droolsfile. It will also run for any drools file that has changed. The clean target will remove the semaphore files and delete the image.
