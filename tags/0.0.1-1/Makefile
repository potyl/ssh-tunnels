BUILD_NAME=$(shell cat debian/control | grep 'Package' | sed 's/Package: //')
BUILD_VERSION=$(shell cat debian/changelog | head -n 1 | perl -pe 's/^.*\((.*)\).*\Z/\1/')

SVN_REPO=$(shell svn info | grep -E '^URL: ' | cut -f2 -d' ' | sed -e 's%/trunk%%')

TARGET_FOLDER=target
TARGET_DOC=$(TARGET_FOLDER)/doc

PREFIX=/usr
DESTDIR=$(TARGET_FOLDER)/install
INSTALL_FOLDER=$(DESTDIR)$(PREFIX)

# Used to generate an unsigned version of the debian package
# Usage: make deb-package DPKG="-us -uc"
DPKG=


.PHONY: info
info:
	@echo "BUILD_NAME    = $(BUILD_NAME)"
	@echo "BUILD_VERSION = $(BUILD_VERSION)"
	@echo "BUILD_NAME    = $(BUILD_NAME)"
	@echo "SVN_REPO      = $(SVN_REPO)"


.PHONY: build
build:
	@echo "Building the executables"
	dsss build


.PHONY: test
test:
	@echo "Building the executables"
	dsss build --test unittests


.PHONY: install
install: build
	@echo "Copy the executables"
	install -d $(INSTALL_FOLDER)/bin/
	install $(BUILD_NAME)-cli $(INSTALL_FOLDER)/bin/
	install $(BUILD_NAME)-gtk $(INSTALL_FOLDER)/bin/

	@echo "Copy the .glade file"
	install -d $(INSTALL_FOLDER)/share/$(BUILD_NAME)/
	install --mode=644 resources/$(BUILD_NAME).glade $(INSTALL_FOLDER)/share/$(BUILD_NAME)/

	@echo "Copy the .desktop file"
	install -d $(INSTALL_FOLDER)/share/applications/
	install --mode=644 resources/$(BUILD_NAME).desktop $(INSTALL_FOLDER)/share/applications/
	perl -i -pe "s,%PREFIX%,$(PREFIX),g; s,%BUILD_NAME%,$(BUILD_NAME),g;" $(INSTALL_FOLDER)/share/applications/$(BUILD_NAME).desktop

	@echo "Copy the icons"
	install -d $(INSTALL_FOLDER)/share/$(BUILD_NAME)/icons
	install --mode=644 resources/$(BUILD_NAME).png $(INSTALL_FOLDER)/share/$(BUILD_NAME)/


.PHONY: debian-package
debian-package: install
	@echo "Creating Debian package"
	mkdir -p $(TARGET_FOLDER)/debian/
	dpkg-buildpackage -b $(DPKG) -rfakeroot
	mv ../$(BUILD_NAME)_*.* $(TARGET_FOLDER)/debian/


.PHONY: tag
tag:
	@echo "Tagging repository"
	# Remove existing tag
	-svn rm -m "Retagging version $(BUILD_VERSION)" $(SVN_REPO)/tags/$(BUILD_VERSION)
	svn cp -m "Tag for version $(BUILD_VERSION)" $(SVN_REPO)/trunk $(SVN_REPO)/tags/$(BUILD_VERSION)


.PHONY: clean
clean:
	@echo "Cleanup"
	-dsss clean
	-rm -rf $(TARGET_FOLDER)/
	-rm -f  $(BUILD_NAME)-gtk $(BUILD_NAME)-cli libDD-unittests.a test_DD-unittests
	-rm -rf dsss_imports dsss.last
	-rm -rf debian/files debian/$(BUILD_NAME)
