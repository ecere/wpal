.PHONY: all objdir cleantarget clean realclean distclean

# CORE VARIABLES

MODULE := wpal
VERSION := 0.0.1
CONFIG := release
ifndef COMPILER
COMPILER := default
endif

TARGET_TYPE = sharedlib

# FLAGS

ECFLAGS =
ifndef DEBIAN_PACKAGE
CFLAGS =
LDFLAGS =
endif
PRJ_CFLAGS =
CECFLAGS =
OFLAGS =
LIBS =

ifdef DEBUG
NOSTRIP := y
endif

CONSOLE = -mwindows

# INCLUDES

WPAL_ABSPATH := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

ifndef EC_SDK_SRC
EC_SDK_SRC := $(WPAL_ABSPATH)../eC
endif

_CF_DIR = $(EC_SDK_SRC)/
include $(_CF_DIR)crossplatform.mk
include $(_CF_DIR)default.cf

# POST-INCLUDES VARIABLES

OBJ = obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX)/

RES = res/

TARGET_NAME := wpal

TARGET = obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX)/$(LP)$(TARGET_NAME)$(OUT)

_ECSOURCES = \
	$(if $(OSX_TARGET),src/drivers/NCursesInterface.ec,) \
	$(if $(WINDOWS_TARGET),src/drivers/Win32Interface.ec,) \
	$(if $(WINDOWS_TARGET),src/drivers/Win32ConsoleInterface.ec,) \
	$(if $(or $(LINUX_TARGET),$(OSX_TARGET)),src/drivers/XInterface.ec,) \
	src/Anchor.ec \
	src/ClipBoard.ec \
	src/Cursor.ec \
	src/GuiApplication.ec \
	src/Interface.ec \
	src/Key.ec \
	src/Timer.ec \
	src/RootWindow.ec

ECSOURCES = $(call shwspace,$(_ECSOURCES))

_COBJECTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(C),$(notdir $(_ECSOURCES))))

_SYMBOLS = $(addprefix $(OBJ),$(patsubst %.ec,%$(S),$(notdir $(_ECSOURCES))))

_IMPORTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(I),$(notdir $(_ECSOURCES))))

_ECOBJECTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(O),$(notdir $(_ECSOURCES))))

_BOWLS = $(addprefix $(OBJ),$(patsubst %.ec,%$(B),$(notdir $(_ECSOURCES))))

COBJECTS = $(call shwspace,$(_COBJECTS))

SYMBOLS = $(call shwspace,$(_SYMBOLS))

IMPORTS = $(call shwspace,$(_IMPORTS))

ECOBJECTS = $(call shwspace,$(_ECOBJECTS))

BOWLS = $(call shwspace,$(_BOWLS))

OBJECTS = $(ECOBJECTS) $(OBJ)$(MODULE).main$(O)

SOURCES = $(ECSOURCES)

RESOURCES = \
	locale/es.mo \
	locale/hu.mo \
	locale/mr.mo \
	locale/nl.mo \
	locale/pt_BR.mo \
	locale/ru.mo \
	locale/zh_CN.mo

ifdef USE_RESOURCES_EAR
RESOURCES_EAR = $(OBJ)resources.ear
else
RESOURCES_EAR = $(RESOURCES)
endif

LIBS += $(SHAREDLIB) $(EXECUTABLE) $(LINKOPT)

ifndef STATIC_LIBRARY_TARGET
LIBS += \
	$(call _L,ecrt)
endif

PRJ_CFLAGS += \
	 $(if $(OSX_TARGET), \
			 -I$(SYSROOT)/usr/X11/include \
			 -I/usr/X11R6/include,) \
	 $(if $(DEBUG), -g, -O2 -ffast-math) $(FPIC) -Wall -DREPOSITORY_VERSION="\"$(REPOSITORY_VER)\"" \
			 -I/usr/X11R6/include

ECFLAGS += -module $(MODULE)
ECFLAGS += \
	 -defaultns wpal

# PLATFORM-SPECIFIC OPTIONS

ifdef WINDOWS_TARGET

OFLAGS += \
	$(if $(EC_SDK_SRC)/obj/$(PLATFORM)$(COMPILER_SUFFIX)/bin,-L$(call quote_path,$(EC_SDK_SRC)/obj/$(PLATFORM)$(COMPILER_SUFFIX)/bin),) \
	-static-libgcc


ifndef STATIC_LIBRARY_TARGET
LIBS += \
	$(call _L,dxguid) \
	$(call _L,dinput) \
	$(call _L,winmm) \
	$(call _L,kernel32) \
	$(call _L,user32) \
	$(call _L,mpr) \
	$(call _L,advapi32) \
	$(call _L,shell32) \
	$(call _L,imm32)
endif

else
OFLAGS += \
	$(if $(EC_SDK_SRC)/obj/$(PLATFORM)$(COMPILER_SUFFIX)/lib,-L$(call quote_path,$(EC_SDK_SRC)/obj/$(PLATFORM)$(COMPILER_SUFFIX)/lib),)

ifdef LINUX_TARGET

ifndef STATIC_LIBRARY_TARGET
OFLAGS += \
	 -L$(call quote_path,/usr/X11R6/lib)
LIBS += \
	$(call _L,X11) \
	$(call _L,m)
endif

else
ifdef OSX_TARGET

ifndef STATIC_LIBRARY_TARGET
OFLAGS += \
	 -L$(call quote_path,$(SYSROOT)/usr/X11/lib) \
	 -L$(call quote_path,/usr/X11R6/lib)
LIBS += \
	$(call _L,curses) \
	$(call _L,pthread) \
	$(call _L,X11) \
	$(call _L,Xext)
endif

endif
endif
endif

CFLAGS += \
	 -mmmx -msse -msse2 -msse3

OFLAGS += \
	 -Wl,--wrap=fcntl64

CECFLAGS += -cpp $(_CPP)

# TARGETS

all: objdir $(TARGET)

objdir:
	$(if $(wildcard $(OBJ)),,$(call mkdir,$(OBJ)))
	$(if $(ECERE_SDK_SRC),$(if $(wildcard $(call escspace,$(ECERE_SDK_SRC)/crossplatform.mk)),,@$(call echo,Ecere SDK Source Warning: The value of ECERE_SDK_SRC is pointing to an incorrect ($(ECERE_SDK_SRC)) location.)),)
	$(if $(ECERE_SDK_SRC),,$(if $(ECP_DEBUG)$(ECC_DEBUG)$(ECS_DEBUG),@$(call echo,ECC Debug Warning: Please define ECERE_SDK_SRC before using ECP_DEBUG, ECC_DEBUG or ECS_DEBUG),))

$(OBJ)$(MODULE).main.ec: $(SYMBOLS) $(COBJECTS)
	@$(call rm,$(OBJ)symbols.lst)
	@$(call touch,$(OBJ)symbols.lst)
	$(call addtolistfile,$(SYMBOLS),$(OBJ)symbols.lst)
	$(call addtolistfile,$(IMPORTS),$(OBJ)symbols.lst)
	$(ECS) $(ARCH_FLAGS) $(ECSLIBOPT) @$(OBJ)symbols.lst -symbols obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX) -o $(call quote_path,$@)

$(OBJ)$(MODULE).main.c: $(OBJ)$(MODULE).main.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(OBJ)$(MODULE).main.ec -o $(OBJ)$(MODULE).main.sym -symbols $(OBJ)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(OBJ)$(MODULE).main.ec -o $(call quote_path,$@) -symbols $(OBJ)

ifdef USE_RESOURCES_EAR
$(RESOURCES_EAR): $(RESOURCES) | objdir
	$(EAR) aw$(EARFLAGS) $(RESOURCES_EAR) locale/es.mo locale/hu.mo locale/mr.mo locale/nl.mo locale/pt_BR.mo locale/ru.mo locale/zh_CN.mo "locale"
endif

$(SYMBOLS): | objdir
$(OBJECTS): | objdir
$(TARGET): $(SOURCES) $(RESOURCES_EAR) $(SYMBOLS) $(OBJECTS) | objdir
	@$(call rm,$(OBJ)objects.lst)
	@$(call touch,$(OBJ)objects.lst)
	$(call addtolistfile,$(OBJ)$(MODULE).main$(O),$(OBJ)objects.lst)
	$(call addtolistfile,$(ECOBJECTS),$(OBJ)objects.lst)
ifndef STATIC_LIBRARY_TARGET
	$(LD) $(OFLAGS) @$(OBJ)objects.lst $(LIBS) -o $(TARGET) $(INSTALLNAME) $(SONAME)
ifndef NOSTRIP
	$(STRIP) $(STRIPOPT) $(TARGET)
endif
ifndef USE_RESOURCES_EAR
	$(EAR) aw$(EARFLAGS) $(TARGET) locale/es.mo locale/hu.mo locale/mr.mo locale/nl.mo locale/pt_BR.mo locale/ru.mo locale/zh_CN.mo "locale"
endif
else
ifdef WINDOWS_HOST
	$(AR) rcs $(TARGET) @$(OBJ)objects.lst $(LIBS)
else
	$(AR) rcs $(TARGET) $(OBJECTS) $(LIBS)
endif
endif
ifdef SHARED_LIBRARY_TARGET
ifdef LINUX_TARGET
ifdef LINUX_HOST
	$(if $(basename $(VER)),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(OBJ)$(LP)$(MODULE)$(SO)$(basename $(VER)),)
	$(if $(VER),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(OBJ)$(LP)$(MODULE)$(SO),)
endif
endif
endif
#	$(call mkdir,../$(SODESTDIR))
#	$(call cp,$(TARGET),../$(SODESTDIR))

install:
	$(call cp,$(TARGET),"$(DESTLIBDIR)/")
	$(if $(WINDOWS_HOST),,ln -sf $(LP)$(MODULE)$(SOV) $(DESTLIBDIR)/$(LP)$(MODULE)$(SO).0)
	$(if $(WINDOWS_HOST),,ln -sf $(LP)$(MODULE)$(SOV) $(DESTLIBDIR)/$(LP)$(MODULE)$(SO))

# SYMBOL RULES

ifneq ($(OSX_TARGET),)
$(OBJ)NCursesInterface.sym: src/drivers/NCursesInterface.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/drivers/NCursesInterface.ec) -o $(call quote_path,$@)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32Interface.sym: src/drivers/Win32Interface.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/drivers/Win32Interface.ec) -o $(call quote_path,$@)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32ConsoleInterface.sym: src/drivers/Win32ConsoleInterface.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/drivers/Win32ConsoleInterface.ec) -o $(call quote_path,$@)
endif

ifneq ($(or $(LINUX_TARGET),$(OSX_TARGET)),)
$(OBJ)XInterface.sym: src/drivers/XInterface.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/drivers/XInterface.ec) -o $(call quote_path,$@)
endif

$(OBJ)Anchor.sym: src/Anchor.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/Anchor.ec) -o $(call quote_path,$@)

$(OBJ)ClipBoard.sym: src/ClipBoard.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/ClipBoard.ec) -o $(call quote_path,$@)

$(OBJ)Cursor.sym: src/Cursor.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/Cursor.ec) -o $(call quote_path,$@)

$(OBJ)GuiApplication.sym: src/GuiApplication.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/GuiApplication.ec) -o $(call quote_path,$@)

$(OBJ)Interface.sym: src/Interface.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/Interface.ec) -o $(call quote_path,$@)

$(OBJ)Key.sym: src/Key.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/Key.ec) -o $(call quote_path,$@)

$(OBJ)Timer.sym: src/Timer.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/Timer.ec) -o $(call quote_path,$@)

$(OBJ)RootWindow.sym: src/RootWindow.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,src/RootWindow.ec) -o $(call quote_path,$@)

# C OBJECT RULES

ifneq ($(OSX_TARGET),)
$(OBJ)NCursesInterface.c: src/drivers/NCursesInterface.ec $(OBJ)NCursesInterface.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/drivers/NCursesInterface.ec) -o $(call quote_path,$@) -symbols $(OBJ)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32Interface.c: src/drivers/Win32Interface.ec $(OBJ)Win32Interface.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/drivers/Win32Interface.ec) -o $(call quote_path,$@) -symbols $(OBJ)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32ConsoleInterface.c: src/drivers/Win32ConsoleInterface.ec $(OBJ)Win32ConsoleInterface.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/drivers/Win32ConsoleInterface.ec) -o $(call quote_path,$@) -symbols $(OBJ)
endif

ifneq ($(or $(LINUX_TARGET),$(OSX_TARGET)),)
$(OBJ)XInterface.c: src/drivers/XInterface.ec $(OBJ)XInterface.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/drivers/XInterface.ec) -o $(call quote_path,$@) -symbols $(OBJ)
endif

$(OBJ)Anchor.c: src/Anchor.ec $(OBJ)Anchor.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/Anchor.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)ClipBoard.c: src/ClipBoard.ec $(OBJ)ClipBoard.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/ClipBoard.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Cursor.c: src/Cursor.ec $(OBJ)Cursor.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/Cursor.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)GuiApplication.c: src/GuiApplication.ec $(OBJ)GuiApplication.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/GuiApplication.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Interface.c: src/Interface.ec $(OBJ)Interface.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/Interface.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Key.c: src/Key.ec $(OBJ)Key.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/Key.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Timer.c: src/Timer.ec $(OBJ)Timer.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/Timer.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)RootWindow.c: src/RootWindow.ec $(OBJ)RootWindow.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,src/RootWindow.ec) -o $(call quote_path,$@) -symbols $(OBJ)

# OBJECT RULES

ifneq ($(OSX_TARGET),)
$(OBJ)NCursesInterface$(O): $(OBJ)NCursesInterface.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)NCursesInterface.c) -o $(call quote_path,$@)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32Interface$(O): $(OBJ)Win32Interface.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Win32Interface.c) -o $(call quote_path,$@)
endif

ifneq ($(WINDOWS_TARGET),)
$(OBJ)Win32ConsoleInterface$(O): $(OBJ)Win32ConsoleInterface.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Win32ConsoleInterface.c) -o $(call quote_path,$@)
endif

ifneq ($(or $(LINUX_TARGET),$(OSX_TARGET)),)
$(OBJ)XInterface$(O): $(OBJ)XInterface.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)XInterface.c) -o $(call quote_path,$@)
endif

$(OBJ)Anchor$(O): $(OBJ)Anchor.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Anchor.c) -o $(call quote_path,$@)

$(OBJ)ClipBoard$(O): $(OBJ)ClipBoard.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)ClipBoard.c) -o $(call quote_path,$@)

$(OBJ)Cursor$(O): $(OBJ)Cursor.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Cursor.c) -o $(call quote_path,$@)

$(OBJ)GuiApplication$(O): $(OBJ)GuiApplication.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)GuiApplication.c) -o $(call quote_path,$@)

$(OBJ)Interface$(O): $(OBJ)Interface.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Interface.c) -o $(call quote_path,$@)

$(OBJ)Key$(O): $(OBJ)Key.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Key.c) -o $(call quote_path,$@)

$(OBJ)Timer$(O): $(OBJ)Timer.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Timer.c) -o $(call quote_path,$@)

$(OBJ)RootWindow$(O): $(OBJ)RootWindow.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)RootWindow.c) -o $(call quote_path,$@)

$(OBJ)$(MODULE).main$(O): $(OBJ)$(MODULE).main.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(OBJ)$(MODULE).main.c -o $(call quote_path,$@)

cleantarget:
	$(call rm,$(OBJ)$(MODULE).main$(O) $(OBJ)$(MODULE).main.c $(OBJ)$(MODULE).main.ec $(OBJ)$(MODULE).main$(I) $(OBJ)$(MODULE).main$(S))
	$(call rm,$(OBJ)symbols.lst)
	$(call rm,$(OBJ)objects.lst)
	$(call rm,$(TARGET))
ifdef SHARED_LIBRARY_TARGET
ifdef LINUX_TARGET
ifdef LINUX_HOST
	$(call rm,$(OBJ)$(LP)$(MODULE)$(SO)$(basename $(VER)))
	$(call rm,$(OBJ)$(LP)$(MODULE)$(SO))
endif
endif
endif

clean: cleantarget
	$(call rm,$(_OBJECTS))
	$(call rm,$(_ECOBJECTS))
	$(call rm,$(_COBJECTS))
	$(call rm,$(_BOWLS))
	$(call rm,$(_IMPORTS))
	$(call rm,$(_SYMBOLS))
ifdef USE_RESOURCES_EAR
	$(call rm,$(RESOURCES_EAR))
endif

realclean: cleantarget
	$(call rmr,$(OBJ))

distclean: cleantarget
	$(call rmr,obj/)
	$(call rmr,.configs/)
	$(call rm,*.ews)
	$(call rm,*.Makefile)
