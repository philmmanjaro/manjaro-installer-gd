GODOT ?= /usr/bin/godot
GODOT_VERSION ?= $(shell godot --version | grep -o '[0-9].*[0-9]')
GODOT_RELEASE ?= $(shell godot --version | rev | cut -d '.' -f2 | rev)
GODOT_REVISION := $(GODOT_VERSION).$(GODOT_RELEASE)
EXPORT_TEMPLATE := $(HOME)/.local/share/godot/export_templates/$(GODOT_REVISION)/linux_debug.x86_64
EXPORT_TEMPLATE_URL ?= https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-$(GODOT_RELEASE)/Godot_v$(GODOT_VERSION)-$(GODOT_RELEASE)_export_templates.tpz

ALL_GDSCRIPT := $(shell find ./ -name '*.gd')
ALL_SCENES := $(shell find ./ -name '*.tscn')
ALL_RESOURCES := $(shell find ./ -regex  '.*\(tres\|svg\|png\)$$')
PROJECT_FILES := $(ALL_GDSCRIPT) $(ALL_SCENES) $(ALL_RESOURCES)


##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


.PHONY: build
build: build/manjaro-installer.x86_64 ## Build and export the project
build/manjaro-installer.x86_64: $(PROJECT_FILES) $(EXPORT_TEMPLATE)
	mkdir -p build
	$(GODOT) --headless --export-debug "Linux/X11"


.PHONY: edit
edit: ## Open the project in the Godot editor
	$(GODOT) --editor --single-window .


.PHONY: clean
clean: ## Remove build artifacts
	rm -rf build
	rm -rf .godot


$(EXPORT_TEMPLATE):
	@echo "$(EXPORT_TEMPLATE)"
	mkdir -p $(HOME)/.local/share/godot/export_templates
	@echo "Downloading export templates"
	wget $(EXPORT_TEMPLATE_URL) -O $(HOME)/.local/share/godot/export_templates/templates.zip
	@echo "Extracting export templates"
	unzip $(HOME)/.local/share/godot/export_templates/templates.zip -d $(HOME)/.local/share/godot/export_templates/
	rm $(HOME)/.local/share/godot/export_templates/templates.zip
	mv $(HOME)/.local/share/godot/export_templates/templates $(@D)
