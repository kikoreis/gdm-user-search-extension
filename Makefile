UUID = gdm-user-search@kiko-gnome.async.com.br
SRC_DIR = $(UUID)
ZIP = $(UUID).shell-extension.zip
PO_DIR = po
LOCALE_DIR = $(SRC_DIR)/locale

.PHONY: all
all: build

.PHONY: pot
pot:
	cd $(SRC_DIR) && xgettext --from-code=UTF-8 \
		--package-name=gdm-user-search \
		--package-version=1.0 \
		--copyright-holder='Kiko Reis' \
		--output=../$(PO_DIR)/$(UUID).pot \
		extension.js

.PHONY: update-po
update-po: pot
	for po in $(PO_DIR)/*.po; do \
		msgmerge --update $$po $(PO_DIR)/$(UUID).pot; \
	done

.PHONY: mo
mo:
	mkdir -p $(LOCALE_DIR)
	for po in $(PO_DIR)/*.po; do \
		lang=$$(basename $$po .po); \
		mkdir -p $(LOCALE_DIR)/$$lang/LC_MESSAGES; \
		msgfmt $$po -o $(LOCALE_DIR)/$$lang/LC_MESSAGES/$(UUID).mo; \
	done

.PHONY: build
build: mo
	cd $(SRC_DIR) && zip -qr ../$(ZIP) ./*

.PHONY: install
install: build
	@echo "Run sudo ./install.sh to install system-wide for GDM"
	@echo "Or extract $(ZIP) to ~/.local/share/gnome-shell/extensions/ for user session"

.PHONY: clean
clean:
	rm -rf $(LOCALE_DIR)
	rm -f $(ZIP)
