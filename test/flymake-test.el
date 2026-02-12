;;; flymake-test.el --- tests for the ink-mode Flymake backend  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'ink-mode)

(ert-deftest ink-flymake-parse-error-line ()
  (should (equal
           (ink--flymake-parse-line "ERROR: 'Main.ink' line 12: Unexpected symbol")
           '(:file "Main.ink" :line 12 :type :error :msg "Unexpected symbol"))))

(ert-deftest ink-flymake-parse-warning-line ()
  (should (equal
           (ink--flymake-parse-line "WARNING: 'Main.ink' line 3: Something is odd")
           '(:file "Main.ink" :line 3 :type :warning :msg "Something is odd"))))

(ert-deftest ink-flymake-parse-todo-line ()
  (should (equal
           (ink--flymake-parse-line "TODO: 'Main.ink' line 2: Something is odd")
           '(:file "Main.ink" :line 2 :type :note :msg "Something is odd"))))

(ert-deftest ink-flymake-missing-compiler-reports-empty-diagnostics ()
  (with-temp-buffer
    (ink-mode)
    (let (reported warning-shown)
      (cl-letf (((symbol-function 'ink--inklecate-executable) (lambda () nil))
                ((symbol-function 'warn)
                 (lambda (&rest _args)
                   (setq warning-shown t)))
                ((symbol-function 'make-process)
                 (lambda (&rest _args)
                   (ert-fail "Flymake should not spawn process when compiler is missing"))))
        (ink-flymake-inklecate (lambda (diags) (setq reported diags)))
        (should (equal reported nil))
        (should warning-shown)))))

(ert-deftest ink-flymake-unsaved-buffer-reports-empty-diagnostics ()
  (with-temp-buffer
    (insert "== start ==\n")
    (ink-mode)
    (let (reported)
      (cl-letf (((symbol-function 'ink--inklecate-executable) (lambda () "/bin/true"))
                ((symbol-function 'make-process)
                 (lambda (&rest _args)
                   (ert-fail "Flymake should not spawn process for unsaved buffers"))))
        (ink-flymake-inklecate (lambda (diags) (setq reported diags)))
        (should (equal reported nil))))))

(provide 'flymake-test)
;;; flymake-test.el ends here
