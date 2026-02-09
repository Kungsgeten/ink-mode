;;; font-lock-test.el --- tests for Ink font-lock highlighting  -*- lexical-binding: t; -*-

(require 'ert)
(require 'ink-mode)

;; NOTE: Need this to silence the compiler when ert-font-lock is not
;; available.
(declare-function ert-font-lock-test-string "ert-font-lock" (test-string mode))

(ert-deftest ink-font-lock-highlights-function-header-parts ()
  (skip-when (not (require 'ert-font-lock nil t)))
  (skip-unless (fboundp 'ert-font-lock-test-string))
  (ert-font-lock-test-string
   "
=== function forest_phase(arg) ===
// <- ink-shadow-face
//  ^ font-lock-keyword-face
//           ^ ink-knot-face
//                       ^ font-lock-variable-name-face
"
   'ink-mode))

(ert-deftest ink-font-lock-highlights-diverts-and-includes ()
  (skip-when (not (require 'ert-font-lock nil t)))
  (skip-unless (fboundp 'ert-font-lock-test-string))
  (ert-font-lock-test-string
   "
-> ending
// <- ink-arrow-face
//  ^ ink-link-face
INCLUDE chapter.ink
// <- font-lock-keyword-face
//      ^ ink-link-face
"
   'ink-mode))

(ert-deftest ink-font-lock-highlights-choices-labels-and-brackets ()
  (skip-when (not (require 'ert-font-lock nil t)))
  (skip-unless (fboundp 'ert-font-lock-test-string))
  (ert-font-lock-test-string
   "
* (choice_label) [Option text]
// <- font-lock-type-face
//  ^ font-lock-variable-name-face
//                 ^ ink-bracket-face
"
   'ink-mode))

(ert-deftest ink-font-lock-highlights-tags-glue-and-var-decls ()
  (skip-when (not (require 'ert-font-lock nil t)))
  (skip-unless (fboundp 'ert-font-lock-test-string))
  (ert-font-lock-test-string
   "
Plain text #tag
//         ^ ink-tag-face
<>
// <- ink-shadow-face
VAR score = 0
// <- font-lock-keyword-face
//    ^ font-lock-variable-name-face
"
   'ink-mode))

(provide 'font-lock-test)
;;; font-lock-test.el ends here
