include make/d.mk make/variables.mk make/extensions.mk make/dbg.mk make/util.mk

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

DOCS_DIR := docs/html/
DOCS = $(patsubst %.d, %.html, $(SOURCES))

# flags
DCFLAGS := $(DC_INFORMATIONAL_WARNINGS_FLAG) $(DC_WARNDEPRECATE_FLAG) $(DC_SYMBOLICDEBUGINFO_FLAG)
# add import path
DCFLAGS += $(DC_IMPORTPATH_FLAG)$(SOURCE_DIR)

DCFLAGS_RELEASE := $(DC_OPTIMIZE_FLAG) $(DC_INLINE_FLAG) $(DC_RELEASE_FLAG) $(DC_NOBOUNDSCHECK_FLAG)
DCFLAGS_DEBUG := $(DC_DEBUG_FLAG) $(DC_UNITTEST_FLAG)

BUILD ?= release
ifeq ($(BUILD), release)
	DCFLAGS += $(DCFLAGS_RELEASE)
endif
ifeq ($(BUILD), debug)
	DCFLAGS += $(DCFLAGS_DEBUG)
endif

# wrapping
ifeq ($(DC), gdc)
	LDFLAGS += $(DC_LINKER_FLAG)--wrap=_d_throwc
endif

.PHONY: all
all: build

.PHONY: build
build: $(STATIC_LIBRARY) $(STATIC_LIBRARY).dbg $(EXAMPLE) $(EXAMPLE).dbg

$(SHARED_LIBRARY): DCFLAGS += $(DC_FPIC_FLAG)
$(SHARED_LIBRARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(DC_SHARED_LIBRARY_FLAG) $^ $(DC_OUTPUTFILE_FLAG)$@

$(STATIC_LIBRARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(DC_STATIC_LIBRARY_FLAG) $^ $(DC_OUTPUTFILE_FLAG)$@

$(EXAMPLE): DCFLAGS += $(DC_UNITTEST_FLAG)
$(EXAMPLE): $(EXAMPLE_OBJECTS) $(STATIC_LIBRARY)
	$(LD) $(LDFLAGS) $^ $(DC_OUTPUTFILE_FLAG)$@

$(TEST_EXECUTABLE): DCFLAGS += $(DC_UNITTEST_FLAG)
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

.PHONY: clean
clean:
	$(RMALL) $(TEST_EXECUTABLE) $(TEST_EXECUTABLE_DBG) $(STATIC_LIBRARY) $(STATIC_LIBRARY_DBG) $(SHARED_LIBRARY) $(SHARED_LIBRARY_DBG) $(EXAMPLE) $(EXAMPLE_DBG) $(OBJECTS) $(EXAMPLE_OBJECTS) $(DOCS) $(DOCS_DIR)
