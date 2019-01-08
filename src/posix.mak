################################################################################
# Important variables:
# --------------------
#
# HOST_CXX:             Host C++ compiler to use (g++,clang++)
# HOST_DMD:             Host D compiler to use for bootstrapping
# AUTO_BOOTSTRAP:       Enable auto-boostrapping by downloading a stable DMD binary
# INSTALL_DIR:          Installation folder to use
# MODEL:                Target architecture to build for (32,64) - defaults to the host architecture
#
################################################################################
# Build modes:
# ------------
# BUILD: release (default) | debug (enabled a build with debug instructions)
#
# Opt-in build features:
#
# ENABLE_RELEASE:       Optimized release built
# ENABLE_DEBUG:         Add debug instructions and symbols (set if ENABLE_RELEASE isn't set)
# ENABLE_WARNINGS:      Enable C++ build warnings
# ENABLE_PROFILING:     Build dmd with a profiling recorder (C++)
# ENABLE_PGO_USE:       Build dmd with existing profiling information (C++)
#   PGO_DIR:            Directory for profile-guided optimization (PGO) logs
# ENABLE_LTO:           Enable link-time optimizations
# ENABLE_UNITTEST:      Build dmd with unittests (sets ENABLE_COVERAGE=1)
# ENABLE_PROFILE:       Build dmd with a profiling recorder (D)
# ENABLE_COVERAGE       Build dmd with coverage counting
# ENABLE_SANITIZERS     Build dmd with sanitizer (e.g. ENABLE_SANITIZERS=address,undefined)
#
# Targets
# -------
#
# all					Build dmd
# unittest              Run all unittest blocks
# cxx-unittest          Check conformance of the C++ headers
# build-examples        Build DMD as library examples
# clean                 Remove all generated files
# man                   Generate the man pages
# checkwhitespace       Checks for trailing whitespace and tabs
# zip                   Packs all sources into a ZIP archive
# gitzip                Packs all sources into a ZIP archive
# install               Installs dmd into $(INSTALL_DIR)
################################################################################

# get OS and MODEL
include osmodel.mak

ifeq (,$(TARGET_CPU))
    $(info no cpu specified, assuming X86)
    TARGET_CPU=X86
endif

# Default to a release built, override with BUILD=debug
ifeq (,$(BUILD))
BUILD=release
endif

ifneq ($(BUILD),release)
    ifneq ($(BUILD),debug)
        $(error Unrecognized BUILD=$(BUILD), must be 'debug' or 'release')
    endif
    ENABLE_DEBUG := 1
endif

# default to PIC on x86_64, use PIC=1/0 to en-/disable PIC.
# Note that shared libraries and C files are always compiled with PIC.
ifeq ($(PIC),)
    ifeq ($(MODEL),64) # x86_64
        PIC:=1
    else
        PIC:=0
    endif
endif
ifeq ($(PIC),1)
    override PIC:=-fPIC
else
    override PIC:=
endif

GIT_HOME=https://github.com/dlang
TOOLS_DIR=../../tools

INSTALL_DIR=../../install
SYSCONFDIR=/etc
TMP?=/tmp
PGO_DIR=$(abspath pgo)

D = dmd

C=$D/backend
TK=$D/tk
ROOT=$D/root
EX=examples
RES=../res

GENERATED = ../generated
G = $(GENERATED)/$(OS)/$(BUILD)/$(MODEL)
$(shell mkdir -p $G)

DSCANNER_HASH=3a859d39c4b59822b1bc0452b3ddcd598ef390a2
DSCANNER_DIR=$G/dscanner-$(DSCANNER_HASH)

ifeq (osx,$(OS))
    export MACOSX_DEPLOYMENT_TARGET=10.9
endif

HOST_CXX=c++
# compatibility with old behavior
ifneq ($(HOST_CC),)
  $(warning ===== WARNING: Please use HOST_CXX=$(HOST_CC) instead of HOST_CC=$(HOST_CC). =====)
  HOST_CXX=$(HOST_CC)
endif
CXX=$(HOST_CXX)
AR=ar
GIT=git

# determine whether CXX is gcc or clang based
CXX_VERSION:=$(shell $(CXX) --version)
ifneq (,$(findstring g++,$(CXX_VERSION))$(findstring gcc,$(CXX_VERSION))$(findstring Free Software,$(CXX_VERSION)))
	CXX_KIND=g++
endif
ifneq (,$(findstring clang,$(CXX_VERSION)))
	CXX_KIND=clang++
endif

HOST_DC?=
ifneq (,$(HOST_DC))
  $(warning ========== Use HOST_DMD instead of HOST_DC ========== )
  HOST_DMD=$(HOST_DC)
endif

# Host D compiler for bootstrapping
ifeq (,$(AUTO_BOOTSTRAP))
  # No bootstrap, a $(HOST_DC) installation must be available
  HOST_DMD?=dmd
  HOST_DMD_PATH=$(abspath $(shell which $(HOST_DMD)))
  ifeq (,$(HOST_DMD_PATH))
    $(error '$(HOST_DMD)' not found, get a D compiler or make AUTO_BOOTSTRAP=1)
  endif
  HOST_DMD_RUN:=$(HOST_DMD)
else
  # Auto-bootstrapping, will download dmd automatically
  # Keep var below in sync with other occurrences of that variable, e.g. in circleci.sh
  HOST_DMD_VER=2.079.1
  HOST_DMD_ROOT=$(GENERATED)/host_dmd-$(HOST_DMD_VER)
  # dmd.2.072.2.osx.zip or dmd.2.072.2.linux.tar.xz
  HOST_DMD_BASENAME=dmd.$(HOST_DMD_VER).$(OS)$(if $(filter $(OS),freebsd),-$(MODEL),)
  # http://downloads.dlang.org/releases/2.x/2.072.2/dmd.2.072.2.linux.tar.xz
  HOST_DMD_URL=http://downloads.dlang.org/releases/2.x/$(HOST_DMD_VER)/$(HOST_DMD_BASENAME)
  HOST_DMD=$(HOST_DMD_ROOT)/dmd2/$(OS)/$(if $(filter $(OS),osx),bin,bin$(MODEL))/dmd
  HOST_DMD_PATH=$(HOST_DMD)
  HOST_DMD_RUN=$(HOST_DMD) -conf=$(dir $(HOST_DMD))dmd.conf
endif

HOST_DMD_VERSION:=$(shell $(HOST_DMD_RUN) --version)
ifneq (,$(findstring dmd,$(HOST_DMD_VERSION))$(findstring DMD,$(HOST_DMD_VERSION)))
	HOST_DMD_KIND=dmd
endif
ifneq (,$(findstring gdc,$(HOST_DMD_VERSION))$(findstring GDC,$(HOST_DMD_VERSION)))
	HOST_DMD_KIND=gdc
endif
ifneq (,$(findstring gdc,$(HOST_DMD_VERSION))$(findstring gdmd,$(HOST_DMD_VERSION)))
	HOST_DMD_KIND=gdc
endif
ifneq (,$(findstring ldc,$(HOST_DMD_VERSION))$(findstring LDC,$(HOST_DMD_VERSION)))
	HOST_DMD_KIND=ldc
endif

# Compiler Warnings
ifdef ENABLE_WARNINGS
WARNINGS := -Wall -Wextra -Werror \
	-Wno-attributes \
	-Wno-char-subscripts \
	-Wno-deprecated \
	-Wno-empty-body \
	-Wno-format \
	-Wno-missing-braces \
	-Wno-missing-field-initializers \
	-Wno-overloaded-virtual \
	-Wno-parentheses \
	-Wno-reorder \
	-Wno-return-type \
	-Wno-sign-compare \
	-Wno-strict-aliasing \
	-Wno-switch \
	-Wno-type-limits \
	-Wno-unknown-pragmas \
	-Wno-unused-function \
	-Wno-unused-label \
	-Wno-unused-parameter \
	-Wno-unused-value \
	-Wno-unused-variable
# GCC Specific
ifeq ($(CXX_KIND), g++)
WARNINGS += \
	-Wno-logical-op \
	-Wno-narrowing \
	-Wno-unused-but-set-variable \
	-Wno-uninitialized \
	-Wno-class-memaccess \
	-Wno-implicit-fallthrough
endif
else
# Default Warnings
WARNINGS := -Wno-deprecated -Wstrict-aliasing -Werror
# Clang Specific
ifeq ($(CXX_KIND), clang++)
WARNINGS += \
    -Wno-logical-op-parentheses
endif
endif

OS_UPCASE := $(shell echo $(OS) | tr '[a-z]' '[A-Z]')

MMD=-MMD -MF $(basename $@).deps

# Default compiler flags for all source files
CXXFLAGS := $(WARNINGS) \
	-fno-exceptions -fno-rtti \
	-D__pascal= -DMARS=1 -DTARGET_$(OS_UPCASE)=1 -DDM_TARGET_CPU_$(TARGET_CPU)=1 \
	$(MODEL_FLAG) $(PIC)
# GCC Specific
ifeq ($(CXX_KIND), g++)
CXXFLAGS += \
    -std=gnu++98
endif
# Clang Specific
ifeq ($(CXX_KIND), clang++)
CXXFLAGS += \
    -xc++
endif

DFLAGS=
override DFLAGS += -version=MARS $(PIC) -J$G
# Enable D warnings
override DFLAGS += -w -de

# Append different flags for debugging, profiling and release.
ifdef ENABLE_DEBUG
CXXFLAGS += -g -g3 -DDEBUG=1 -DUNITTEST
override DFLAGS += -g -debug
endif
ifdef ENABLE_RELEASE
CXXFLAGS += -O2
override DFLAGS += -O -release -inline
else
# Add debug symbols for all non-release builds
override DFLAGS += -g
endif
ifdef ENABLE_PROFILING
CXXFLAGS  += -pg -fprofile-arcs -ftest-coverage
endif
ifdef ENABLE_PGO_GENERATE
CXXFLAGS  += -fprofile-generate=${PGO_DIR}
endif
ifdef ENABLE_PGO_USE
CXXFLAGS  += -fprofile-use=${PGO_DIR} -freorder-blocks-and-partition
endif
ifdef ENABLE_LTO
CXXFLAGS  += -flto
endif
ifdef ENABLE_UNITTEST
override DFLAGS  += -unittest -cov
endif
ifdef ENABLE_PROFILE
override DFLAGS  += -profile
endif
ifdef ENABLE_COVERAGE
ifeq ($(OS),osx)
# OSX uses libclang_rt.profile_osx for coverage, not libgcov
# Attempt to find it by parsing `clang`'s output
CLANG_LIB_SEARCH_DIR := $(shell clang -print-search-dirs | grep libraries | cut -d= -f2)
COVERAGE_LINK_FLAGS := -L-L$(CLANG_LIB_SEARCH_DIR)/lib/darwin/ -L-lclang_rt.profile_osx
else
COVERAGE_LINK_FLAGS := -L-lgcov
endif
override DFLAGS  += -cov $(COVERAGE_LINK_FLAGS)
CXXFLAGS += --coverage
endif
ifdef ENABLE_SANITIZERS
CXXFLAGS += -fsanitize=${ENABLE_SANITIZERS}

ifeq ($(HOST_DMD_KIND), dmd)
HOST_CXX += -fsanitize=${ENABLE_SANITIZERS}
endif
ifneq (,$(findstring gdc,$(HOST_DMD_KIND))$(findstring ldc,$(HOST_DMD_KIND)))
override DFLAGS += -fsanitize=${ENABLE_SANITIZERS}
endif

endif

# Unique extra flags if necessary
DMD_FLAGS  := -I$D -Wuninitialized
BACK_FLAGS := -I$(ROOT) -I$(TK) -I$C -I$G -I$D -DDMDV2=1
BACK_DFLAGS := -version=DMDV2
ROOT_FLAGS := -I$(ROOT)

ifeq ($(OS), osx)
ifeq ($(MODEL), 64)
D_OBJC := 1
endif
endif

ifneq (gdc, $(HOST_DMD_KIND))
  BACK_MV = -mv=dmd.backend=$C
  BACK_BETTERC = $(BACK_MV) -betterC
  # gdmd doesn't support -dip25
  override DFLAGS  += -dip25
endif

######## DMD frontend source files

FRONT_SRCS=$(addsuffix .d, $(addprefix $D/,access aggregate aliasthis apply argtypes arrayop	\
	arraytypes astcodegen attrib builtin canthrow cli clone compiler complex cond constfold	\
	cppmangle cppmanglewin ctfeexpr ctorflow dcast dclass declaration delegatize denum dimport	\
	dinifile dinterpret dmacro dmangle dmodule doc dscope dstruct dsymbol dsymbolsem	\
	dtemplate dversion env escape expression expressionsem func			\
	hdrgen id impcnvtab imphint init initsem inline inlinecost intrange	\
	json lambdacomp lib libelf libmach link mars mtype nogc nspace objc opover optimize parse permissivevisitor sapply templateparamsem	\
	sideeffect statement staticassert target typesem traits transitivevisitor parsetimevisitor visitor	\
	typinf utils scanelf scanmach statement_rewrite_walker statementsem staticcond safe blockexit printast \
	semantic2 semantic3))

LEXER_SRCS=$(addsuffix .d, $(addprefix $D/, console entity errors filecache globals id identifier lexer tokens utf ))

LEXER_ROOT=$(addsuffix .d, $(addprefix $(ROOT)/, array ctfloat file filename outbuffer port rmem \
	rootobject stringtable hash))

ROOT_SRCS = $(addsuffix .d,$(addprefix $(ROOT)/,aav array ctfloat file \
	filename man outbuffer port response rmem rootobject speller \
	longdouble stringtable hash))

GLUE_SRCS=$(addsuffix .d, $(addprefix $D/,irstate toctype glue gluelayer todt tocsym toir dmsc \
	tocvdebug s2ir toobj e2ir eh iasm iasmdmd iasmgcc objc_glue))

DMD_SRCS=$(FRONT_SRCS) $(GLUE_SRCS) $(BACK_HDRS) $(TK_HDRS)

######## DMD backend source files

ifeq (X86,$(TARGET_CPU))
    TARGET_CH =
    TARGET_OBJS =
else
    ifeq (stub,$(TARGET_CPU))
        TARGET_CH = $C/code_stub.h
        TARGET_OBJS = platform_stub.o
    else
        $(error unknown TARGET_CPU: '$(TARGET_CPU)')
    endif
endif

BACK_OBJS = \
    fp.o \
	\
	tk.o strtold.o \
	$(TARGET_OBJS)

BACK_DOBJS = bcomplex.o evalu8.o divcoeff.o dvec.o go.o gsroa.o glocal.o gdag.o gother.o gflow.o \
	out.o \
	gloop.o compress.o cgelem.o cgcs.o ee.o cod4.o cod5.o nteh.o blockopt.o memh.o cg.o cgreg.o \
	dtype.o debugprint.o symbol.o elem.o dcode.o cgsched.o cg87.o cgxmm.o cgcod.o cod1.o cod2.o \
	cod3.o cv8.o dcgcv.o pdata.o util2.o var.o md5.o backconfig.o ph2.o drtlsym.o dwarfeh.o ptrntab.o \
	aarray.o dvarstats.o dwarfdbginf.o elfobj.o cgen.o os.o goh.o barray.o

G_OBJS  = $(addprefix $G/, $(BACK_OBJS))
G_DOBJS = $(addprefix $G/, $(BACK_DOBJS))
#$(info $$G_OBJS is [${G_OBJS}])

ifeq (osx,$(OS))
	BACK_DOBJS += machobj.o
else
#	BACK_DOBJS += elfobj.o
endif

######## DMD glue layer and backend

GLUE_SRC = \
	$(addprefix $D/, \
	libelf.d scanelf.d libmach.d scanmach.d \
	objc_glue.d)

BACK_HDRS=$C/cc.d $C/cdef.d $C/cgcv.d $C/code.d $C/cv4.d $C/dt.d $C/el.d $C/global.d \
	$C/obj.d $C/oper.d $C/outbuf.d $C/rtlsym.d $C/code_x86.d $C/iasm.d $C/codebuilder.d \
	$C/ty.d $C/type.d $C/exh.d $C/mach.d $C/mscoff.d $C/dwarf.d $C/dwarf2.d $C/xmm.d \
	$C/dlist.d $C/melf.d $C/varstats.di $C/dt.d

TK_HDRS=

BACK_SRC = \
	$C/optabgen.d \
	$C/bcomplex.d $C/blockopt.d $C/cg.d $C/cg87.d $C/cgxmm.d \
	$C/cgcod.d $C/cgcs.d $C/dcgcv.d $C/cgelem.d $C/cgen.d $C/cgobj.d \
	$C/compress.d $C/cgreg.d $C/var.d $C/strtold.c \
	$C/cgsched.d $C/cod1.d $C/cod2.d $C/cod3.d $C/cod4.d $C/cod5.d \
	$C/dcode.d $C/symbol.d $C/debugprint.d $C/dt.d $C/ee.d $C/elem.d \
	$C/evalu8.d $C/fp.c $C/go.d $C/gflow.d $C/gdag.d \
	$C/gother.d $C/glocal.d $C/gloop.d $C/gsroa.d $C/newman.d \
	$C/nteh.d $C/os.d $C/out.d $C/ptrntab.d $C/drtlsym.d \
	$C/dtype.d \
	$C/token.h \
	$C/elfobj.d \
	$C/dwarfdbginf.d $C/aarray.d \
	$C/platform_stub.c $C/code_stub.h \
	$C/machobj.d $C/mscoffobj.d \
	$C/pdata.d $C/cv8.d $C/backconfig.d $C/divcoeff.d \
	$C/dvarstats.d $C/dvec.d \
	$C/md5.d $C/barray.d \
	$C/ph2.d $C/util2.d $C/dwarfeh.d $C/goh.d $C/memh.d $C/filespec.d \
	$(TARGET_CH)

TK_SRC = \
	$(TK)/filespec.h $(TK)/mem.h $(TK)/list.h $(TK)/vec.h \
	$(TK)/mem.c

######## CXX header files (only needed for cxx-unittest)

SRC = $(addprefix $D/, aggregate.h aliasthis.h arraytypes.h	\
	attrib.h compiler.h complex_t.h cond.h ctfe.h ctfe.h declaration.h doc.h dsymbol.h	\
	enum.h errors.h expression.h globals.h hdrgen.h identifier.h \
	id.h import.h init.h json.h \
	mangle.h mars.h module.h mtype.h nspace.h objc.h                \
	scope.h statement.h staticassert.h target.h template.h tokens.h	\
	version.h visitor.h libomf.d scanomf.d libmscoff.d scanmscoff.d)         \
	$(DMD_SRCS)

ROOT_SRC = $(addprefix $(ROOT)/, array.h ctfloat.h dcompat.h file.h filename.h \
	longdouble.h object.h outbuffer.h port.h \
	rmem.h root.h)

######## Additional files

SRC_MAKE = posix.mak osmodel.mak

STRING_IMPORT_FILES = $G/VERSION $G/SYSCONFDIR.imp $(RES)/default_ddoc_theme.ddoc

DEPS = $(patsubst %.o,%.deps,$(DMD_OBJS) $(BACK_OBJS) $(BACK_DOBJS))

######## Begin build targets

all: $G/dmd

auto-tester-build: $G/dmd checkwhitespace cxx-unittest $G/dmd_frontend
.PHONY: auto-tester-build

toolchain-info:
	@echo '==== Toolchain Information ===='
	@echo 'uname -a:' $$(uname -a)
	@echo 'MAKE(${MAKE}):' $$(${MAKE} --version)
	@echo 'SHELL(${SHELL}):' $$(${SHELL} --version || true)
	@echo 'HOST_DMD(${HOST_DMD}):' $$(${HOST_DMD} --version)
	@echo 'HOST_CXX(${HOST_CXX}):' $$(${HOST_CXX} --version)
# Not currently possible to choose what linker HOST_CXX uses via `make LD=ld.gold`.
	@echo ld: $$(ld -v)
	@echo gdb: $$(! command -v gdb &>/dev/null || gdb --version)
	@echo '==== Toolchain Information ===='
	@echo

$G/backend.a: $(G_OBJS) $(G_DOBJS) $(SRC_MAKE)
	$(AR) rcs $@ $(G_OBJS) $(G_DOBJS)

$G/lexer.a: $(LEXER_SRCS) $(LEXER_ROOT) $(HOST_DMD_PATH) $(SRC_MAKE) $(STRING_IMPORT_FILES)
	$(HOST_DMD_RUN) -lib -of$@ $(MODEL_FLAG) -J$G $(DFLAGS) $(LEXER_SRCS) $(LEXER_ROOT)

$G/dmd_frontend: $(FRONT_SRCS) $D/gluelayer.d $(ROOT_SRCS) $G/lexer.a $(STRING_IMPORT_FILES) $(HOST_DMD_PATH)
	$(HOST_DMD_RUN) -of$@ $(MODEL_FLAG) -vtls -J$G -J$(RES) $(DFLAGS) $(filter-out $(STRING_IMPORT_FILES) $(HOST_DMD_PATH),$^) -version=NoBackend

ifdef ENABLE_LTO
$G/dmd: $(DMD_SRCS) $(ROOT_SRCS) $G/lexer.a $(G_OBJS) $(G_DOBJS) $(STRING_IMPORT_FILES) $(HOST_DMD_PATH) $G/dmd.conf
	$(HOST_DMD_RUN) -of$@ $(MODEL_FLAG) -vtls -J$G -J$(RES) $(DFLAGS) $(filter-out $(STRING_IMPORT_FILES) $(HOST_DMD_PATH) $G/dmd.conf,$^)
else
$G/dmd: $(DMD_SRCS) $(ROOT_SRCS) $G/backend.a $G/lexer.a $(STRING_IMPORT_FILES) $(HOST_DMD_PATH) $G/dmd.conf
	$(HOST_DMD_RUN) -of$@ $(MODEL_FLAG) -vtls -J$G -J$(RES) $(DFLAGS) $(filter-out $(STRING_IMPORT_FILES) $(HOST_DMD_PATH) $(LEXER_ROOT) $G/dmd.conf,$^)
endif

$G/dmd-unittest: $(DMD_SRCS) $(ROOT_SRCS) $(LEXER_SRCS) $(G_OBJS) $(G_DOBJS) $(STRING_IMPORT_FILES) $(HOST_DMD_PATH)
	$(HOST_DMD_RUN) -of$@ $(MODEL_FLAG) -vtls -J$G -J$(RES) $(DFLAGS) -g -unittest -main -version=NoMain $(filter-out $(STRING_IMPORT_FILES) $(HOST_DMD_PATH),$^)

unittest: $G/dmd-unittest
	$<

######## DMD as a library examples

EXAMPLES=$(addprefix $G/examples/, avg impvisitor)
PARSER_SRCS=$(addsuffix .d, $(addprefix $D/,parse astbase parsetimevisitor transitivevisitor permissivevisitor strictvisitor utils))

$G/parser.a: $(PARSER_SRCS) $(LEXER_SRCS) $(ROOT_SRCS) $G/dmd $G/dmd.conf $(SRC_MAKE)
	$G/dmd -lib -of$@ $(MODEL_FLAG) -J$G $(DFLAGS) $(PARSER_SRCS) $(LEXER_SRCS) $(ROOT_SRCS)

$G/examples/%: $(EX)/%.d $G/parser.a $G/dmd
	$G/dmd -of$@ $(MODEL_FLAG) $(DFLAGS) $G/parser.a $<

build-examples: $(EXAMPLES)

######## Manual cleanup

clean:
	rm -Rf $(GENERATED)
	rm -f $(addprefix $D/backend/, $(optabgen_output))
	@[ ! -d ${PGO_DIR} ] || echo You should issue manually: rm -rf ${PGO_DIR}

######## Download and install the last dmd buildable without dmd

ifneq (,$(AUTO_BOOTSTRAP))
CURL_FLAGS:=-fsSL --retry 5 --retry-max-time 120 --connect-timeout 5 --speed-time 30 --speed-limit 1024
$(HOST_DMD_PATH):
	mkdir -p ${HOST_DMD_ROOT}
ifneq (,$(shell which xz 2>/dev/null))
	curl ${CURL_FLAGS} ${HOST_DMD_URL}.tar.xz | tar -C ${HOST_DMD_ROOT} -Jxf - || rm -rf ${HOST_DMD_ROOT}
else
	TMPFILE=$$(mktemp deleteme.XXXXXXXX) &&	curl ${CURL_FLAGS} ${HOST_DMD_URL}.zip > $${TMPFILE}.zip && \
		unzip -qd ${HOST_DMD_ROOT} $${TMPFILE}.zip && rm $${TMPFILE}.zip;
endif
endif

######## generate a default dmd.conf

define DEFAULT_DMD_CONF
[Environment32]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/$(OS)/$(BUILD)/32$(if $(filter $(OS),osx),, -L--export-dynamic)

[Environment64]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/$(OS)/$(BUILD)/64$(if $(filter $(OS),osx),, -L--export-dynamic) -fPIC
endef

export DEFAULT_DMD_CONF

$G/dmd.conf: $(SRC_MAKE)
	echo "$$DEFAULT_DMD_CONF" > $@

######## optabgen generates some source
optabgen_output = debtab.d optab.d cdxxx.d elxxx.d fltables.d tytab.d

$G/optabgen: $C/optabgen.d $C/cc.d $C/oper.d $(HOST_DMD_PATH)
	$(HOST_DMD_RUN) -of$@ $(DFLAGS) $(MODEL_FLAG) $(BACK_MV) $<
	$G/optabgen
	mv $(optabgen_output) $G

optabgen_files = $(addprefix $G/, $(optabgen_output))
$(optabgen_files): optabgen.out
.INTERMEDIATE: optabgen.out
optabgen.out : $G/optabgen

######## VERSION
########################################################################
# The version file should be updated on every build
# However, the version check script only touches the VERSION file if it
# actually has changed.

$G/version_check: ../config.d $(HOST_DMD_PATH)
	@echo "  (HOST_DMD_RUN)  $<  $<"
	$(HOST_DMD_RUN) $< -of$@

$G/VERSION: $G/version_check ../VERSION FORCE
	@$< $G ../VERSION $(SYSCONFDIR)

$G/SYSCONFDIR.imp: $G/VERSION

FORCE: ;

# Generic rules for all source files
########################################################################
# Search the directory $C for .c-files when using implicit pattern
# matching below.
#vpath %.c $C

-include $(DEPS)

$(G_OBJS): $G/%.o: $C/%.c $(optabgen_files) $(SRC_MAKE)
	@echo "  (CC)  BACK_OBJS  $<"
	$(CXX) -c -o$@ $(CXXFLAGS) $(BACK_FLAGS) $(MMD) $<

$(G_DOBJS): $G/%.o: $C/%.d $(optabgen_files) posix.mak $(HOST_DMD_PATH)
	@echo "  (HOST_DMD_RUN)  BACK_DOBJS  $<"
	$(HOST_DMD_RUN) -c -of$@ $(DFLAGS) $(MODEL_FLAG) $(BACK_BETTERC) $(BACK_DFLAGS) $<

################################################################################
# Generate the man pages
################################################################################

DMD_MAN_PAGE = $(GENERATED)/docs/man1/dmd.1

$(DMD_MAN_PAGE): dmd/cli.d
	${MAKE} -C ../docs DMD=$(HOST_DMD_PATH) build

man: $(DMD_MAN_PAGE)

######################################################

install: all $(DMD_MAN_PAGE)
	$(eval bin_dir=$(if $(filter $(OS),osx), bin, bin$(MODEL)))
	mkdir -p $(INSTALL_DIR)/$(OS)/$(bin_dir)
	cp $G/dmd $(INSTALL_DIR)/$(OS)/$(bin_dir)/dmd
	cp ../ini/$(OS)/$(bin_dir)/dmd.conf $(INSTALL_DIR)/$(OS)/$(bin_dir)/dmd.conf
	cp $D/boostlicense.txt $(INSTALL_DIR)/dmd-boostlicense.txt

######################################################

checkwhitespace: $(HOST_DMD_PATH) $(TOOLS_DIR)/checkwhitespace.d
	CC="$(HOST_CXX)" $(HOST_DMD_RUN) -run $(TOOLS_DIR)/checkwhitespace.d $(SRC) $(GLUE_SRC) $(ROOT_SRCS)

$(TOOLS_DIR)/checkwhitespace.d:
	git clone --depth=1 ${GIT_HOME}/tools $(TOOLS_DIR)

######################################################
# DScanner
######################################################

style: dscanner

$(DSCANNER_DIR):
	git clone https://github.com/dlang-community/Dscanner $@
	git -C $@ checkout $(DSCANNER_HASH)
	git -C $@ submodule update --init --recursive

$(DSCANNER_DIR)/dsc: $(HOST_DMD_PATH) | $(DSCANNER_DIR)
	# debug build is faster, but disable 'missing import' messages (missing core from druntime)
	sed 's/dparse_verbose/StdLoggerDisableWarning/' $(DSCANNER_DIR)/makefile > $(DSCANNER_DIR)/dscanner_makefile_tmp
	mv $(DSCANNER_DIR)/dscanner_makefile_tmp $(DSCANNER_DIR)/makefile
	DC=$(HOST_DMD_PATH) $(MAKE) -C $(DSCANNER_DIR) githash debug

# runs static code analysis with Dscanner
dscanner: $(DSCANNER_DIR)/dsc
	@echo "Running DScanner"
	$(DSCANNER_DIR)/dsc --config .dscanner.ini --styleCheck dmd -I.

######################################################

$G/cxxfrontend.o: $G/%.o: tests/%.c $(SRC) $(ROOT_SRC)
	$(CXX) -c -o$@ $(CXXFLAGS) $(DMD_FLAGS) $(MMD) $<

$G/cxx-unittest: $G/cxxfrontend.o $(DMD_SRCS) $(ROOT_SRCS) $G/lexer.a $(G_OBJS) $(G_DOBJS) $(STRING_IMPORT_FILES) $(HOST_DMD_PATH)
	CC=$(HOST_CXX) $(HOST_DMD_RUN) -of$@ $(MODEL_FLAG) -vtls -J$G -J$(RES) -L-lstdc++ $(DFLAGS) -version=NoMain $(filter-out $(STRING_IMPORT_FILES) $(HOST_DMD_PATH),$^)

cxx-unittest: $G/cxx-unittest
	$<

######################################################

zip:
	-rm -f dmdsrc.zip
	zip dmdsrc $(SRC) $(ROOT_SRCS) $(GLUE_SRC) $(BACK_SRC) $(TK_SRC)

######################################################

gitzip:
	git archive --format=zip HEAD > $(ZIPFILE)

################################################################################
# DDoc documentation generation
################################################################################

# BEGIN fallbacks for old variable names
# should be removed after https://github.com/dlang/dlang.org/pull/1581
# has been pulled
DOCSRC=../dlang.org
STDDOC=$(DOCFMT)
DOC_OUTPUT_DIR=$(DOCDIR)
# END fallbacks

# DDoc html generation - this is very similar to the way the documentation for
# Phobos is built
ifneq ($(DOCSRC),)

# list all files for which documentation should be generated, use sort to remove duplicates
SRC_DOCUMENTABLES = $(sort $(ROOT_SRCS) $(DMD_SRCS) $(LEXER_SRCS) $(LEXER_ROOT) $(PARSER_SRCS) \
                           $D/frontend.d)

D2HTML=$(foreach p,$1,$(if $(subst package.d,,$(notdir $p)),$(subst /,_,$(subst .d,.html,$p)),$(subst /,_,$(subst /package.d,.html,$p))))
HTMLS=$(addprefix $(DOC_OUTPUT_DIR)/, \
	$(call D2HTML, $(SRC_DOCUMENTABLES)))

# For each module, define a rule e.g.:
# ../web/phobos/dmd_mars.html : dmd/mars.d $(STDDOC) ; ...
$(foreach p,$(SRC_DOCUMENTABLES),$(eval \
$(DOC_OUTPUT_DIR)/$(call D2HTML,$p) : $p $(STDDOC) $(DMD) ;\
  $(DMD) -o- $(MODEL_FLAG) -J$G -J$(RES) -c -w -Dd$(DOCSRC) -Idmd\
  $(DFLAGS) project.ddoc $(STDDOC) -Df$$@ $$<))

$(DOC_OUTPUT_DIR) :
	mkdir -p $@

html: $(HTMLS) project.ddoc | $(DOC_OUTPUT_DIR)
endif

######################################################

.DELETE_ON_ERROR: # GNU Make directive (delete output files on error)
