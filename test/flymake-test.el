;;; flymake-test.el --- tests for the ink-mode Flymake backend  -*- lexical-binding: t; -*-
(require 'ert)
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

(provide 'flymake-test)
;;; flymake-test.el ends here
