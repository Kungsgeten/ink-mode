;;; imenu-test.el --- tests for Ink symbol collection and imenu  -*- lexical-binding: t; -*-

(require 'ert)
(require 'ink-mode)

(defconst ink-test--sample-buffer
  "== start ==
* (first_choice) Intro choice
= branch
+ (branch_choice) Branch choice
== end ==
* (end_choice) End choice
")

(ert-deftest ink-collect-symbols-parses-headers-and-labels ()
  (with-temp-buffer
    (insert ink-test--sample-buffer)
    (ink-mode)
    (let ((symbols (ink--collect-symbols)))
      (should (equal
               (mapcar (lambda (entry)
                         (list (plist-get entry :kind)
                               (plist-get entry :name)))
                       symbols)
               '((knot "start")
                 (label "start.first_choice")
                 (stitch "start.branch")
                 (label "start.branch.branch_choice")
                 (knot "end")
                 (label "end.end_choice"))))
      (should (= (plist-get (nth 0 symbols) :position)
                 (ink-test--line-position "== start ==")))
      (should (= (plist-get (nth 2 symbols) :position)
                 (ink-test--line-position "= branch"))))))

(ert-deftest ink-imenu-index-includes-configured-symbol-kinds ()
  (with-temp-buffer
    (insert ink-test--sample-buffer)
    (ink-mode)
    (let* ((index (ink--imenu-create-index))
           (knots (cdr (assoc "Knots" index)))
           (stitches (cdr (assoc "Stitches" index)))
           (labels (cdr (assoc "Labels" index)))
           (completion-targets (ink-get-headers-and-labels)))
      (should (equal (mapcar #'car knots)
                     '("start" "end")))
      (should (equal (mapcar #'car stitches)
                     '("start.branch")))
      (should (equal (mapcar #'car labels)
                     '("start.first_choice"
                       "start.branch.branch_choice"
                       "end.end_choice")))
      (should (= (cdr (assoc "start.branch" stitches))
                 (ink-test--line-position "= branch")))
      (should (= (cdr (assoc "end.end_choice" labels))
                 (ink-test--line-position "* (end_choice) End choice")))
      (dolist (entry (append knots stitches labels))
        (should (member (car entry) completion-targets))))))

(ert-deftest ink-imenu-index-can-hide-labels ()
  (with-temp-buffer
    (insert ink-test--sample-buffer)
    (ink-mode)
    (let ((ink-imenu-include-labels nil))
      (should (equal (mapcar #'car (ink--imenu-create-index))
                     '("Knots" "Stitches"))))))

(provide 'imenu-test)
;;; imenu-test.el ends here
