# RootHide Theos lives at ~/theos on the development Mac. `THEOS=` is kept
# overridable so the project can be rebuilt on another machine.
THEOS ?= $(HOME)/theos
TARGET := iphone:clang:26.0:15.0
THEOS_PACKAGE_SCHEME := roothide
ARCHS := arm64 arm64e

ifeq ($(wildcard $(THEOS)/makefiles/common.mk),)
$(error RootHide Theos was not found at '$(THEOS)'. Install RootHide Theos or invoke make with THEOS=/path/to/theos)
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := AudioWatch

AudioWatch_FILES := AppMain.m AppDelegate.m SceneDelegate.m \
	AWRootViewController.m AWFolderBrowserViewController.m AWActivityViewController.m \
	AWComponents.m AWTheme.m AWConfig.m AWPasswordStore.m AWDaemonClient.m AWShared.m
AudioWatch_FRAMEWORKS := UIKit Foundation Security SystemConfiguration
AudioWatch_CFLAGS := -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.modulecache -Wno-deprecated-declarations -Wno-unused-parameter
AudioWatch_CODESIGN_FLAGS := -Sentitlements.plist
AudioWatch_RESOURCE_DIRS := Resources

TOOL_NAME := AudioWatchDaemon

AudioWatchDaemon_FILES := AWDaemon.m AWDirectoryWatcher.m AWUploader.m AWWebDAVClient.m AWShared.m
AudioWatchDaemon_FRAMEWORKS := Foundation SystemConfiguration Security
AudioWatchDaemon_CFLAGS := -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.modulecache -Wno-deprecated-declarations -Wno-unused-parameter
AudioWatchDaemon_CODESIGN_FLAGS := -Sdaemon.entitlements.plist
AudioWatchDaemon_INSTALL_PATH := /usr/local/libexec

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/LaunchDaemons/com.liseng.audiowatch.daemon.plist "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/"$(ECHO_END)
