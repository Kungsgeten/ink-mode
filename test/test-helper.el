;;; test-helper.el --- shared helpers for ink-mode tests  -*- lexical-binding: t; -*-

(require 'ink-mode)

(defun ink-test--indent-string (input &optional indent-tabs choice-spaces)
  "Return INPUT after indenting it in `ink-mode'."
  (with-temp-buffer
    (insert input)
    (ink-mode)
    (setq-local tab-width 2)
    (setq-local indent-tabs-mode indent-tabs)
    (setq-local ink-indent-choices-with-spaces choice-spaces)
    (let ((inhibit-message t))
      (indent-region (point-min) (point-max)))
    (buffer-string)))

(defun ink-test--line-position (line)
  "Return beginning position of LINE in current buffer."
  (save-excursion
    (goto-char (point-min))
    (should (search-forward line nil t))
    (line-beginning-position)))

(provide 'test-helper)
;;; test-helper.el ends here
