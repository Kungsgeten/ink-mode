EASK ?= eask
ELISP_FILES = ink-mode.el

.PHONY: deps lint package-lint checkdoc compile test

lint: checkdoc compile package-lint

deps:
	$(EASK) install-deps

package-lint:
	$(EASK) lint package $(ELISP_FILES)

checkdoc:
	$(EASK) lint checkdoc $(ELISP_FILES)

compile:
	$(EASK) compile $(ELISP_FILES)

test:
	$(EASK) test ert-runner
