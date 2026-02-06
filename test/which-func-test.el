;;; which-func-test.el --- tests for Ink which-function integration  -*- lexical-binding: t; -*-

(require 'ert)
(require 'which-func)
(require 'ink-mode)

(defconst ink-test--which-func-sample
  "== start ==
* (first_choice) Intro choice
= branch
+ (branch_choice) Branch choice
Text in branch
")

(ert-deftest ink-which-function-uses-imenu-with-labels ()
  (with-temp-buffer
    (insert ink-test--which-func-sample)
    (ink-mode)
    (goto-char (point-min))
    (search-forward "Text in branch")
    (should (equal (which-function) "start.branch.branch_choice"))))

(ert-deftest ink-which-function-can-ignore-labels ()
  (with-temp-buffer
    (insert ink-test--which-func-sample)
    (let ((ink-imenu-include-labels nil))
      (ink-mode)
      (goto-char (point-min))
      (search-forward "Text in branch")
      (should (equal (which-function) "start.branch")))))

(ert-deftest ink-which-function-does-not-treat-constants-as-defuns ()
  (with-temp-buffer
    (insert "CONST PHASE_EARLY = 0\n"
            "CONST PHASE_MIDDLE = 1\n\n"
            "=== function forest_phase() ===\n"
            "~ return PHASE_EARLY\n")
    (ink-mode)
    (goto-char (point-min))
    (search-forward "CONST PHASE_MIDDLE")
    (beginning-of-line)
    (should (equal (add-log-current-defun) nil))
    (should (equal (which-function) nil))))

(provide 'which-func-test)
;;; which-func-test.el ends here
