EMACS ?= emacs

.PHONY: test compile clean

test:
	$(EMACS) -Q --batch \
	  -L . \
	  -l pangram.el \
	  -l pangram-test.el \
	  -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch \
	  -L . \
	  --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile pangram.el

clean:
	rm -f *.elc
