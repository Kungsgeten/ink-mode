;;; indentation-test.el --- tests for Ink indentation behavior  -*- lexical-binding: t; -*-

(require 'ert)
(require 'ink-mode)

(ert-deftest ink-indent-handles-nested-choices-and-gathers ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* top\n** deep\ntext\n- gather\ntext\n"
            nil nil)
           "== start ==\n  * top\n    * * deep\n        text\n- gather\n  text\n")))

(ert-deftest ink-indent-handles-braced-conditions ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n{ cond:\n- yes:\ntext\n- no:\nother\n}\nafter\n"
            nil nil)
           "== start ==\n{ cond:\n- yes:\n  text\n- no:\n  other\n}\nafter\n")))

(ert-deftest ink-indent-aligns-comment-and-todo-lines-with-following-content ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* choice\n// comment\nTODO: later\ntext\n"
            nil nil)
           "== start ==\n  * choice\n    // comment\n    TODO: later\n    text\n")))

(ert-deftest ink-indent-aligns-multiline-comments-with-following-content ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n/* block\ninside\n*/\n* choice\ntext\n"
            nil nil)
           "== start ==\n  /* block\n  inside\n  */\n  * choice\n    text\n")))

(ert-deftest ink-indent-handles-trailing-newline-after-comment-content ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* choice\n// comment\ntext\n"
            nil nil)
           "== start ==\n  * choice\n    // comment\n    text\n")))

(ert-deftest ink-indent-choice-markers-use-tabs-by-default ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* * [opt]\n"
            t nil)
           (concat "== start ==\n\t\t*\t*\t[opt]\n"))))

(ert-deftest ink-indent-choice-markers-use-spaces-when-configured ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* * [opt]\n"
            nil t)
           "== start ==\n    * * [opt]\n")))

(ert-deftest ink-indent-choice-diverts-keep-the-arrow-adjacent ()
  (should (equal
           (ink-test--indent-string
            "== start ==\n* -> somewhere\n"
            t nil)
           (concat "== start ==\n\t*\t-> somewhere\n"))))

(provide 'indentation-test)
;;; indentation-test.el ends here
