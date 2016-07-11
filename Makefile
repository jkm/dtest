include make/d.mk make/variables.mk make/extensions.mk make/dbg.mk make/util.mk make/compress.mk

STATIC_LIBRARY := libdtest$(STATIC_LIBRARY_EXT)
STATIC_LIBRARY_DBG := $(patsubst %, %.dbg, $(STATIC_LIBRARY))
SHARED_LIBRARY := libdtest$(SHARED_LIBRARY_EXT)
SHARED_LIBRARY_DBG := $(patsubst %, %.dbg, $(SHARED_LIBRARY))
TEST_EXECUTABLE := dtest$(EXECUTABLE_EXT)
TEST_EXECUTABLE_DBG := $(patsubst %, %.dbg, $(TEST_EXECUTABLE))
SOURCE_DIR := src
SOURCES := $(call rwildcard, $(SOURCE_DIR), *.d)
OBJECTS := $(patsubst %.d, %.o, $(SOURCES))

EXAMPLE := example$(EXECUTABLE_EXT)
EXAMPLE_DBG := $(patsubst %, %.dbg, $(EXAMPLE))
EXAMPLE_DIR := tests
EXAMPLES := $(call rwildcard, $(EXAMPLE_DIR), *.d)
EXAMPLE_OBJECTS := $(patsubst %.d, %.o, $(EXAMPLES))

DOCS_DIR := docs/html
DOCS = $(patsubst %.d, %.html, $(SOURCES))

# flags
DCFLAGS := $(DC_INFORMATIONAL_WARNINGS_FLAG) $(DC_WARNDEPRECATE_FLAG) $(DC_SYMBOLICDEBUGINFO_FLAG)
# add import path
DCFLAGS += $(DC_IMPORTPATH_FLAG)$(SOURCE_DIR)

DCFLAGS_RELEASE := $(DC_OPTIMIZE_FLAG) $(DC_INLINE_FLAG) $(DC_RELEASE_FLAG) $(DC_NOBOUNDSCHECK_FLAG)
DCFLAGS_DEBUG := $(DC_DEBUG_FLAG)

BUILD ?= release
ifeq ($(BUILD), release)
	DCFLAGS += $(DCFLAGS_RELEASE)
endif
ifeq ($(BUILD), debug)
	DCFLAGS += $(DCFLAGS_DEBUG)
endif

# wrapping
ifeq ($(DC), dmd)
	LDFLAGS += $(DC_LINKER_FLAG)--wrap=_d_throwc
endif
ifeq ($(DC), gdc)
	LDFLAGS += $(DC_LINKER_FLAG)--wrap=_d_throw
endif
ifeq ($(DC), ldc2)
	LDFLAGS += $(DC_LINKER_FLAG)--wrap=_d_throw_exception
endif

.PHONY: all
all: build

.PHONY: build
# BUG
# temporary fix to build with gdc
# gdc cannot build statically
#build: $(STATIC_LIBRARY) $(STATIC_LIBRARY).dbg $(EXAMPLE) $(EXAMPLE).dbg
build: $(EXAMPLE) $(EXAMPLE).dbg

$(SHARED_LIBRARY): DCFLAGS += $(DC_FPIC_FLAG)
$(SHARED_LIBRARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(DC_SHARED_LIBRARY_FLAG) $^ $(DC_OUTPUTFILE_FLAG)$@

$(STATIC_LIBRARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(DC_STATIC_LIBRARY_FLAG) $^ $(DC_OUTPUTFILE_FLAG)$@

$(EXAMPLE): DCFLAGS += $(DC_UNITTEST_FLAG)
# BUG
# temporary fix to build with gdc
$(EXAMPLE): $(EXAMPLE_OBJECTS) $(OBJECTS)
#$(EXAMPLE): $(EXAMPLE_OBJECTS) $(STATIC_LIBRARY)
	$(LD) $(LDFLAGS) $^ $(DC_OUTPUTFILE_FLAG)$@

$(TEST_EXECUTABLE): DCFLAGS += $(DC_UNITTEST_FLAG) $(DC_VERSION_FLAG)dtest_unittest

$(TEST_EXECUTABLE): $(OBJECTS)
	$(LD) $(LDFLAGS) $^ $(DC_OUTPUTFILE_FLAG)$@

.PHONY: tests
tests: $(TEST_EXECUTABLE) $(TEST_EXECUTABLE).dbg
	$(info Executing tests)
	./$(TEST_EXECUTABLE)

.PHONY: docs
docs: DCFLAGS += $(wildcard docs/*.ddoc)
docs: $(DOCS)
	$(MKDIR) $(DOCS_DIR)
	$(MV) $(DOCS) $(DOCS_DIR)
	$(CP) docs/bootDoc/assets/* $(DOCS_DIR)
	$(CP) docs/bootDoc/bootdoc.css $(DOCS_DIR)
	$(CP) docs/bootDoc/bootdoc.js $(DOCS_DIR)
	$(CP) docs/bootDoc/ddoc-icons $(DOCS_DIR)

RELEASE_FILES := $(STATIC_LIBRARY) $(STATIC_LIBRARY_DBG)
RELEASE_ARCHIVES := $(addprefix dtest-$(OS)-$(ARCH)-$(BUILD), .tar .tar.gz .tar.bz2 .tar.xz .zip)

.PHONY: release
release: $(RELEASE_ARCHIVES)

dtest-$(OS)-$(ARCH)-$(BUILD).tar: $(RELEASE_FILES)
	tar -cf $@ $^

dtest-$(OS)-$(ARCH)-$(BUILD).zip: $(RELEASE_FILES)
	zip $@ $^

.PHONY: deploy
deploy: gh_pages

COMMIT := $(shell git rev-parse HEAD)
TAG := $(shell git tag --points-at $(COMMIT))
RELEASE_NAME := $(COMMIT)
ifneq ($(TAG), )
	RELEASE_NAME := $(TAG)
endif

define INDEX_HTML
<!DOCTYPE HTML>
<html lang="en-US">
	<head>
		<meta charset="UTF-8">
		<meta http-equiv="refresh" content="1;url=/dtest/RELEASE_NAME/">
		<title>Redirect</title>
	</head>
	<body>
		If you are not redirected automatically, follow to <a href="/dtest/RELEASE_NAME/">latest build</a>.
	</body>
</html>
endef
export INDEX_HTML

define BUILD_INDEX_HTML
<!DOCTYPE HTML>
<html lang="en-US">
	<head>
		<meta charset="UTF-8">
		<title>Build for commit RELEASE_NAME</title>
	</head>
	<body>
		<ul>
			<li><a href="docs/dtest.html">Documentation</a></li>
		</ul>
		built via travis <a href="https://travis-ci.org/jkm/dtest/builds/TRAVIS_BUILD_ID">build TRAVIS_BUILD_NUMBER</a> from <a href="https://github.com/jkm/dtest/tree/RELEASE_NAME">source</a>.
	</body>
</html>
endef
export BUILD_INDEX_HTML

.PHONY: gh_pages
gh_pages: docs release
	@echo "Deploying to github pages"
	git config user.name "$(shell git --no-pager show -s --format='%an' HEAD)"
	git config user.email "$(shell git --no-pager show -s --format='%ae' HEAD)"
	git fetch origin gh-pages:gh-pages
	git checkout gh-pages
	$(MKDIR) $(RELEASE_NAME)/docs
	$(CP) $(DOCS_DIR)/* $(RELEASE_NAME)/docs
	$(CP) $(RELEASE_ARCHIVES) $(RELEASE_NAME)
	echo "$$BUILD_INDEX_HTML" | m4 -DRELEASE_NAME=$(RELEASE_NAME) -DTRAVIS_BUILD_ID="$(TRAVIS_BUILD_ID)" -DTRAVIS_BUILD_NUMBER="$(TRAVIS_BUILD_NUMBER)" > $(RELEASE_NAME)/index.html
	git add $(RELEASE_NAME)
	echo "$$INDEX_HTML" | m4 -DRELEASE_NAME="$(RELEASE_NAME)" > index.html
	git add index.html
	git commit --amend -m "Add pages"
	git push origin +gh-pages

.PHONY: download
download: download_$(DC)

.PHONY: download_dmd
download_dmd:
	wget -c http://downloads.dlang.org/releases/2016/dmd_2.071.0-0_amd64.deb
	sudo dpkg -i dmd_2.071.0-0_amd64.deb

.PHONY: download_gdc
download_gdc:
	wget -c http://gdcproject.org/downloads/binaries/5.2.0/x86_64-linux-gnu/gdc-5.2.0+2.066.1.tar.xz
	tar xf gdc-5.2.0+2.066.1.tar.xz
	@echo "Update your PATH via export PATH=\$$PATH:\$$PWD/x86_64-pc-linux-gnu/bin"

.PHONY: download_ldc2
download_ldc2:
	wget -c https://github.com/ldc-developers/ldc/releases/download/v1.0.0/ldc2-1.0.0-linux-x86_64.tar.xz
	tar xf ldc2-1.0.0-linux-x86_64.tar.xz
	@echo "Update your PATH via export PATH=\$$PATH:\$$PWD/ldc2-1.0.0-linux-x86_64/bin"

.PHONY: clean
clean:
	$(RMALL) $(TEST_EXECUTABLE) $(TEST_EXECUTABLE_DBG) $(STATIC_LIBRARY) $(STATIC_LIBRARY_DBG) $(SHARED_LIBRARY) $(SHARED_LIBRARY_DBG) $(EXAMPLE) $(EXAMPLE_DBG) $(OBJECTS) $(EXAMPLE_OBJECTS) $(DOCS) $(DOCS_DIR) $(RELEASE_NAME) $(RELEASE_ARCHIVES)
