;;; ink-mode.el --- Major mode for writing interactive fiction in Ink -*- lexical-binding: t -*-

;; Copyright (C) 2016-2020 Erik Sjöstrand, Damien Picard, and
;; ink-mode contributors (see the commit log for details).

;; Author: Erik Sjöstrand
;;         Damien Picard
;; Maintainer: Damien Picard
;; URL: https://github.com/Kungsgeten/ink-mode
;; Version: 0.3.2
;; Keywords: languages, wp, hypermedia
;; Package-Requires: ((emacs "29.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; `ink-mode' provides syntax highlighting and indentation for
;; the Ink scripting language, developed by Inkle Studios.

;; Other features are: divert autocompletion and links to headers and
;; labels; an `ink-play' command to playtest your story from Emacs
;; (bound to C-c C-c by default); an outline similar to org-mode's;
;; error reporting using flymake; a collection of YASnippet snippets.

;;; Code:

(require 'comint)
(require 'thingatpt)
(require 'imenu)
(require 'outline)
(require 'subr-x)
(require 'easymenu)
(require 'flymake)
(require 'cl-lib)
(require 'rx)

(defgroup ink nil
  "Major mode for writing interactive fiction in Ink."
  :link '(url-link :tag "GitHub" "https://github.com/Kungsgeten/ink-mode")
  :link '(info-link "(WritingWithInk)")
  :group 'languages)

(defgroup ink-faces nil
  "Faces for the Ink interactive fiction language."
  :link '(custom-group-link "ink")
  :group 'ink
  :group 'faces)

(defvar-keymap ink-mode-map
  :doc "Keymap for `ink-mode'."
  "C-c C-c" #'ink-play
  "C-c C-p" #'ink-play-knot
  "C-c C-o" #'ink-follow-link-at-point
  "C-c C-h" #'ink-display-manual)

(defvar-keymap ink-mode-mouse-map
  :doc "Mouse map for clickable ink links."
  ;; This makes it look clickable
  "<follow-link>" 'mouse-face
  "<mouse-2>" #'ink-follow-link-at-point)

(easy-menu-define ink-mode-menu ink-mode-map
  "Menu for `ink-mode'."
  '("Ink"
    ["Run game from start" ink-play]
    ["Run game from knot or stitch" ink-play-knot]
    "---"
    ["Follow link at point" ink-follow-link-at-point]))

(defconst ink-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; // starts a comment
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23" st)
    ;; End of line ends a comment
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?\" ".   " st)
    (modify-syntax-entry ?\( ".   " st)
    (modify-syntax-entry ?\) ".   " st)
    (modify-syntax-entry ?\[ ".   " st)
    (modify-syntax-entry ?\] ".   " st)
    (modify-syntax-entry ?0 ".   " st)
    (modify-syntax-entry ?1 ".   " st)
    (modify-syntax-entry ?2 ".   " st)
    (modify-syntax-entry ?3 ".   " st)
    (modify-syntax-entry ?4 ".   " st)
    (modify-syntax-entry ?5 ".   " st)
    (modify-syntax-entry ?6 ".   " st)
    (modify-syntax-entry ?7 ".   " st)
    (modify-syntax-entry ?8 ".   " st)
    (modify-syntax-entry ?9 ".   " st)
    st)
  "Syntax table used while in `ink-mode'.")


;;; Regular Expressions

(defconst ink-regex-header
  "^\\s-*\\(?1:=+\\)\\s-*\\(?2:\\(?:function\\)?\\)\\s-*\\(?3:[[:alnum:]_]+\\)\\s-*\\(?4:\\(?:([^)]*)\\)?\\)\\s-*\\(?5:=*\\)"
  "Regexp identifying Ink headers.
Group 1 matches the equal signs preceding the title.
Group 2 matches the function keyword.
Group 3 matches the header title.
Group 4 matches the function arguments.
Group 5 matches the optional equal signs following the header.")

(defconst ink-regex-label
  "^\\(?:\\s-*[*+\\-]\\)+\\s-*\\(?1:(\\(?2:[[:alnum:]_]+\\))\\)"
  "Regexp identifying Ink labels.
Group 1 matches a label including parentheses.
Group 2 matches a label excluding parentheses.")

(defconst ink-regex-divert
  "\\(?1:->\\|<-\\)\\(?3:\\s-*\\)\\(?2:[[:alnum:]_.]*\\)"
  "Regexp identifying Ink diverts.
Group 1 matches an left or right arrow.
Group 2 matches a link text.
Group 3 matches the spaces inbetween.")

(defconst ink-regex-include
  "^\\s-*\\(?1:INCLUDE\\)\\s-*\\(?2:.*?\\)\\s-*$"
  "Regexp identifying Ink includes.
Group 1 matches an INCLUDE keyword
Group 2 matches a link text")

(defconst ink-regex-comment
  ;; "^\\s-*\\(TODO\\|//\\|.*?/\\*\\|.*?\\*/\\)"
  "^\\s-*\\(TODO\\|//\\)"
  "Regexp identifying Ink comments.")


;;; Compiler lookup

(defcustom ink-inklecate-command "inklecate"
  "Command used to invoke inklecate.
Absolute path or a program used looked up in variable `exec-path'."
  :group 'ink
  :type '(choice (const :tag "inklecate (looked up in PATH)" "inklecate")
                 (string :tag "Path or command name")))

(defcustom ink-imenu-include-labels t
  "If non-nil, include labels in the imenu index."
  :group 'ink
  :type 'boolean)

(defun ink--inklecate-executable ()
  "Return absolute path to inklecate or nil.
Resolve the `ink-inklecate-command'.  Should be used whenever inklecate
is invoked."
  (when-let* ((cmd ink-inklecate-command))
    (or
     ;; Resolve absolute paths.
     (and (file-name-absolute-p cmd) (file-executable-p cmd) cmd)
     ;; Or check PATH.
     (executable-find cmd))))


;;; Link following

(defun ink-follow-link-at-point ()
  "Open the current link.
Determine whether it leads to a header or to an included file by
matching regexps."
  (interactive "@")
  (let ((found-link nil))
    (cond ((thing-at-point-looking-at ink-regex-divert)
           (ink-follow-header-or-label-link)
           (setq found-link t))
          ((thing-at-point-looking-at ink-regex-include)
           (ink-follow-file-link)
           (setq found-link t))
          ((not found-link)
           (user-error "No links")))))

(defun ink-find-header (title)
  "Find a header (knot or stitch) matching TITLE in the buffer.
Return its position."
  (let (position)
    (save-excursion
      (goto-char (point-min))
      (while (and (not position)
                  (re-search-forward ink-regex-header (buffer-end 1) t))
        (when (string-equal (ink-get-knot-name) title)
          (setq position (point))))
      position)))

(defun ink-find-label (title-list &optional start end)
  "Find a label matching TITLE-LIST in the buffer.
Return its position.
TITLE-LIST consists of one to three elements, giving four possibilities:
\(label stitch knot\)
\(label stitch\)
\(label knot\)
\(label\)
START and END can specify the range in which
to search."
  ;; reverse title list to get label first
  (setq title-list (reverse title-list))
  (let (position
        (start (if start start (point-min)))
        (end   (if end end (point-max))))
    (save-excursion
      (goto-char start)
      (while (and (not position)
                  (re-search-forward ink-regex-label end t))
        ;; do different checks depending on title list length
        (cond ((and (not position)
                    (= 3 (length title-list))
                    ;; three elements: compare all three
                    (equal (ink-get-label-name) title-list))
               (setq position (point)))
              ((and (not position)
                    (= 2 (length title-list))
                    ;; two elements: compare first and (second or third) elements
                    (and
                     (equal (nth 0 (ink-get-label-name)) (nth 0 title-list))
                     (or
                      (equal (nth 1 (ink-get-label-name)) (nth 1 title-list))
                      (equal (nth 2 (ink-get-label-name)) (nth 1 title-list)))))
               (setq position (point)))
              ((and (not position)
                    (= 1 (length title-list))
                    ;; one element: compare only label
                    (equal (nth 0 (ink-get-label-name)) (nth 0 title-list)))
               (setq position (point))))))
    position))

(defun ink-follow-header-or-label-link ()
  "Go to the header or label matching the link at point."
  (let (position
        title title-list
        knot-name
        stitch-start stitch-end
        knot-start knot-end)
    (font-lock-ensure)
    (setq title (string-trim-right (match-string-no-properties 2) "\\."))
    (if (string-match-p "^\\(\\END\\|DONE\\)" title)
        (user-error "%s is not a real link" title)
      (progn
        (save-excursion
          ;; get knot and stitch names and start / end positions
          (when (ignore-errors (outline-back-to-heading t))
            (if (= (ink-outline-level) 2)
                ;; In stitch
                (progn
                  (setq stitch-start (point))
                  (save-excursion
                    (ink-end-of-subtree t)
                    (setq stitch-end (point)))
                  (ignore-errors (outline-up-heading 1))
                  (setq knot-name (ink-get-knot-name))
                  (setq knot-start (point))
                  (save-excursion
                    (ink-end-of-subtree t)
                    (setq knot-end (point))))
              ;; In knot
              (setq knot-name (ink-get-knot-name))
              (setq knot-start (point))
              (save-excursion
                (ink-end-of-subtree t)
                (setq knot-end (point))))))

        ;; Look for header
        (setq position (ink-find-header title))
        ;; Look for stitch with that name in current knot:
        (if (not position)
            (setq position (ink-find-header (concat knot-name "." title))))

        ;; Look for labels:
        (setq title-list (split-string title "\\."))
        (unless position
          (cond ((or (= 1 (length title-list))
                     (= 2 (length title-list)))
                 ;; Title has one or two element;
                 ;; look in order in stitch, knot and outside
                 (if (and (not position)
                          stitch-start)
                     (setq position
                           (ink-find-label title-list stitch-start stitch-end)))
                 (if (and (not position)
                          knot-start)
                     (setq position
                           (ink-find-label title-list knot-start knot-end)))
                 (if (not position)
                     (setq position
                           (ink-find-label title-list))))

                ;; Title has three elements;
                ;; look as knot.stitch.label in whole buffer
                ((and (not position)
                      (= 3 (length title-list)))
                 (setq position (ink-find-label title-list)))))

        (if position (progn
                       (message "Jumping to %s" title)
                       (goto-char position)
                       (ignore-errors (outline-show-subtree)))
          (user-error "Link `%s' not found.  Is it in another file?" title))))))

(defun ink-follow-file-link ()
  "Find file matching the link at point."
  (let (file-name)
    (setq file-name (match-string-no-properties 2))
    (setq file-name (concat (file-name-directory
                             (buffer-file-name))
                            file-name))
    (find-file file-name)
    (message "Visiting %s" file-name)))


;;; Faces

(defface ink-shadow-face
  '((t (:inherit shadow)))
  "Face for Ink headers and glue."
  :group 'ink-faces)

(defface ink-knot-face
  '((t (:inherit font-lock-function-name-face)))
  "Face for Ink knots: == * ==."
  :group 'ink-faces)

(defface ink-stitch-face
  '((t (:inherit 'ink-knot-face)))
  "Face for Ink stitches: = *."
  :group 'ink-faces)

(defface ink-link-face
  '((t (:inherit link)))
  "Face for Ink divert links."
  :group 'ink-faces)

(defface ink-arrow-face
  '((t (:inherit font-lock-builtin-face)))
  "Face for Ink divert arrows."
  :group 'ink-faces)

(defface ink-tag-face
  '((t (:inherit font-lock-doc-face)))
  "Face for Ink tags: ()."
  :group 'ink-faces)

(defface ink-bracket-face
  '((t (:inherit italic)))
  "Face for Ink brackets: []."
  :group 'ink-faces)


;;; Highlighting

(defun ink-fontify-diverts (last)
  "Add text properties to next divert from point to LAST."
  (when (re-search-forward ink-regex-divert last t)
    (ink-fontify-links
     ;; Arrow part
     (list 'face 'ink-arrow-face
           'rear-nonsticky t
           'font-lock-multiline t))
    t))

(defun ink-fontify-includes (last)
  "Add text properties to next include from point to LAST."
  (when (re-search-forward ink-regex-include last t)
    (ink-fontify-links
     ;; INCLUDE part
     (list 'face 'font-lock-keyword-face
           'rear-nonsticky t
           'font-lock-multiline t))
    t))

(defun ink-fontify-links (pre-part)
  "Add text properties to link.
Use the PRE-PART list as properties to fontify the part preceding
the link, whether it be an arrow for diverts, or the INCLUDE
keyword."
  (let* ((link-start (match-beginning 2))
         (link-end (match-end 2))
         (title (string-trim-right (match-string-no-properties 2) "\\."))
         ;; Link part (without face)
         (lp (list 'keymap ink-mode-mouse-map
                   'mouse-face 'highlight
                   'font-lock-multiline t
                   'help-echo (if title title ""))))
    (when (match-end 1)
      (add-text-properties (match-beginning 1) (match-end 1) pre-part))
    (when link-start
      (add-text-properties link-start link-end lp)
      (add-face-text-property link-start link-end
                              'ink-link-face 'append))
    t))

(defvar ink-font-lock-keywords
  `(
    ;; TODO-style comments
    ("^\\s-*\\(TODO.*\\)" . font-lock-comment-face)

    ;; Knots
    (,ink-regex-header
     (1 'ink-shadow-face)
     (2 font-lock-keyword-face)
     (3 'ink-knot-face)
     (4 font-lock-variable-name-face)
     (5 'ink-shadow-face))

    ;; Diverts, threads and tunnels
    (ink-fontify-diverts)

    ;; Labels
    (,ink-regex-label 1 font-lock-variable-name-face)

    ;; Choices
    ("^\\s-*\\([*+]\\s-*\\)+" . font-lock-type-face)

    ;; Gathers
    ("^\\s-*\\(\\(?:\\s-*-\\)+\\)\\(?:[^>]\\|$\\)" 1 font-lock-type-face)

    ;; Keywords at beginning of line
    ("^\\s-*\\(VAR\\|CONST\\|LIST\\)" . font-lock-keyword-face)

    ;; Includes
    (ink-fontify-includes)

    ;; Vars, constants and lists
    ("^\\s-*\\(?:VAR\\|CONST\\|LIST\\)\\s-+\\([[:word:]_]+\\)" 1
     font-lock-variable-name-face)

    ;; Conditions
    ("{.*?\\(:\\).*?}" 1 font-lock-constant-face)

    ;; Alternatives
    ("\\(?:^\\|[^\\\\]\\)\\([{|}]+\\)" 1 font-lock-constant-face)

    ;; Code lines
    ("\\(^\\s-*~\\)" (0 font-lock-type-face)
     ("\\_<\\(?:return\\|temp\\|ref\\)\\_>" nil nil (0 font-lock-keyword-face))
     ("\\(\".*?\"\\)" nil nil (0 font-lock-string-face))
     ("\\([[:word:]_]+\\)(.*)" nil nil (1 font-lock-function-name-face))
     ("\\_<\\(?1:.*?\\)\\s-*\\(?2:=\\)\\_>" nil nil
      (1 font-lock-variable-name-face))
     ("\\_<\\(SEED_RANDOM\\|RANDOM\\|CHOICE_COUNT\\|TURNS\\|TURNS_SINCE\\|INT\\|FLOOR\\|FLOAT\\)\\_>" nil nil (0 font-lock-builtin-face)))

    ;; Tags
    ("\\(?:^\\|[^\\\\]\\)\\(#.*\\)$" 1 'ink-tag-face)

    ;; Glue
    ("\\(^\\s-*<>\\|<>\\s-*$\\)" . 'ink-shadow-face)

    ;; Brackets
    ("^\\(?:\\s-*[*+]\\).*\\(\\[.*\\]\\)" 1 'ink-bracket-face)))


;;; Indentation

(defcustom ink-indent-choices-with-spaces nil
  "If non-nil, force using spaces between choices and gathers.
You'd get something like:

  -   I looked at Monsieur Fogg
      *   ... and I could contain myself no longer.
          \\='What is the purpose of our journey, Monsieur?\\='
          \\='A wager,\\=' he replied.
          * *   \\='A wager!\\='[] I returned.
                He nodded.
              * * *   \\='But surely that is foolishness!\\='

Otherwise, use the setting of `indent-tabs-mode', which may give:

  -   I looked at Monsieur Fogg
      *   ... and I could contain myself no longer.
          \\='What is the purpose of our journey, Monsieur?\\='
          \\='A wager,\\=' he replied.
          *   *   \\='A wager!\\='[] I returned.
                  He nodded.
              *   *   *   \\='But surely that is foolishness!\\='"
  :group 'ink
  :type 'boolean)

(defun ink-indent-line ()
  "Indent current line of Ink code."
  (save-excursion
    (indent-line-to (max 0 (ink-calculate-indentation)))
    (ink-indent-choices))
  (let* ((actual-indentation
          (save-excursion
            (goto-char (line-beginning-position))
            (search-forward-regexp "[^[:space:]]")
            (- (point) 1)))
         (follow-indentation-p
          ;; Check if point is within indentation.
          (>= actual-indentation
              (point))))
    (when follow-indentation-p (back-to-indentation))))

(defun ink-count-choices ()
  "Return the number of choices or gather markers on the current line."
  (interactive)
  (let ((choices 0))
    (save-excursion
      (beginning-of-line)
      (re-search-forward
       "\\(?1:\\(?:[*+-]\\s-*\\)+?\\)\\s-*\\(?:->\\)?\\s-*\\([^*+-]\\|$\\)"
       (line-end-position) t)
      (if (match-beginning 0)
          (setq choices (count-matches "\\([*+-]\\)" (line-beginning-position) (match-end 1)))))
    choices))

(defun ink-get-tab-string ()
  "Get the string to insert as tabs depending on `indent-tabs-mode'."
  (if indent-tabs-mode
      "\t"
    (make-string (max 0 (- tab-width 1)) ? )))

(defun ink-indent-choices ()
  "Indent choice and gather markers by adding spacing between symbols."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (and (looking-at "^\\s-*[*+\\-]")
               ;; (not (looking-at "^\\s-*-.*:")) ;; Conditions
               (not (looking-at ".*\\*/"))) ;; Comments
      (let (found-not-choice found-divert replacement-string)
        (while (and (not found-not-choice)
                    (re-search-forward
                     "\\(?1:[*+\\-]\\)\\(?2:\\s-*\\)"
                     (line-end-position) t))
          (save-match-data
            (cond ((looking-at ">")
                   (setq found-divert t)
                   (setq found-not-choice t))
                  ((looking-at "[^*+\\-]")
                   (setq found-not-choice t))))
          (unless found-divert
            (setq replacement-string
                  (cond (ink-indent-choices-with-spaces
                         (if found-not-choice
                             (ink-get-tab-string)
                           " "))
                        (indent-tabs-mode
                         "\t")
                        (t
                         (ink-get-tab-string))))
            ;; Compare string to be replaced with replacement, and do
            ;; it only if different. This avoid making changes which
            ;; disable auto-complete.
            (when (not (equal replacement-string (match-string-no-properties 2)))
              (replace-match replacement-string nil nil nil 2))))))))

(defun ink-calculate-bracket-difference ()
  "Count the difference between opening and closing brackets."
  (-
   (count-matches
    "\\({\\)"
    (line-beginning-position)
    (line-end-position))
   (count-matches
    "\\(}\\)"
    (line-beginning-position)
    (line-end-position))))

(defun ink-calculate-indentation ()
  "Find indent level at point."
  (let (indented
        (bracket-difference 0)
        (indentation-list (list))
        (indentation 0)
        start-pos on-last-line
        comment-start comment-end)

    (save-excursion
      ;; Indent comments as the first non-comment line below
      (beginning-of-line)

      ;; Don't indent empty lines
      (if (looking-at "^\\s-*$")
          (setq indented t))

      (while (and (not indented)
                  (or
                   (looking-at "^\\s-*$")
                   (looking-at "^\\s-*//")
                   (looking-at "^\\s-*TODO")))
        (forward-line 1)
        (if (re-search-forward "^\\s-*[^[:space:]]+.*$" nil t)
            ;; Stay on the matched line; match may include trailing newline.
            (goto-char (match-beginning 0))
          ;; Reached EOF with only comments/whitespace.
          (setq indented t)))

      (setq start-pos (point))

      ;; Multiline comments
      (save-excursion
        (cond ((looking-at ".*\\(?1:/\\*\\)")
               ;; Comment starting at line
               (setq comment-start (line-beginning-position))
               (setq start-pos (line-beginning-position)))
              ((re-search-backward "/\\*" nil t)
               ;; Comment before
               (setq comment-start (line-beginning-position))))
        (when (and comment-start
                   (re-search-forward "\\*/" nil t))
          ;; Find end of comment
          (setq comment-end (point))
          (when (and (> comment-end start-pos)
                     (= comment-start
                        (progn (re-search-backward "/\\*" nil t)
                               (line-beginning-position))))
            ;; Inside comment: the end we found is not that of a
            ;; later comment. Advance to next non-empty, non-comment
            ;; line.
            (goto-char comment-end)
            (forward-line 1)
            (let ((found-next-line t))
              (while (and found-next-line
                          (or (looking-at "^\\s-*$")
                              (looking-at "^\\s-*//")
                              (looking-at "^\\s-*TODO")))
                (forward-line 1)
                (if (re-search-forward "^\\s-*[^[:space:]]+.*$" nil t)
                    ;; Same as above: keep point on the matched line.
                    (goto-char (match-beginning 0))
                  (setq found-next-line nil)
                  ;; Stop scanning when the comment tail reaches EOF.
                  (goto-char (point-max)))))
            (setq start-pos (point)))))

      ;; Go back to header or buffer start
      (or
       (ignore-errors (outline-back-to-heading t))
       (goto-char (point-min)))

      (while (and (not indented)
                  (not on-last-line))
        ;; Go forward one line until exit condition: on starting line
        (when (= (point)
                 start-pos)
          (setq on-last-line t))

        ;; Calculate the difference betweeen the numbers of opening
        ;; and closing brackets
        (when (looking-at ".*[{}]")
          (setq bracket-difference (ink-calculate-bracket-difference)))

        (cond
         ;; At header; only useful for multiline comments,
         ;; which look down
         ((looking-at ink-regex-header)
          (setq indentation-list '()))

         ;; Conditions inside brackets - ...:
         ((and (looking-at "^\\s-*-.*:\\s-*")
               (or
                (memq 'bracket indentation-list)
                (memq 'bracket-cond indentation-list)))
          ;; Pop until previous bracket
          (while (not (or (eq 'bracket (nth 0 indentation-list))
                          (eq 'bracket-cond (nth 0 indentation-list))))
            (pop indentation-list))
          (cond
           ;; If inside bracket with condition, keep same indentation
           ((eq 'bracket-cond (nth 0 indentation-list))
            (pop indentation-list)
            (unless on-last-line
              (push 'bracket-cond indentation-list)))
           ;; If inside simple bracket, add one indentation
           ((eq 'bracket (nth 0 indentation-list))
            (unless on-last-line
              (push 'cond indentation-list)))))

         ;; Choices * +
         ((looking-at "^\\s-*[*+]")
          ;; (not (looking-at ".*?\\*/"))) ;; comments
          (while (or (eq 'choice (nth 0 indentation-list))
                     (eq 'gather (nth 0 indentation-list)))
            (pop indentation-list))
          (setq indentation-list (nconc (make-list (ink-count-choices) 'choice)
                                        indentation-list)))

         ;; Gathers -
         ((and (looking-at "^\\s-*\\(-[^>]\\|-$\\)")
               (not (looking-at ".*?\\*/"))) ;; comments
          (while (or (eq 'choice (nth 0 indentation-list))
                     (eq 'gather (nth 0 indentation-list)))
            (pop indentation-list))
          (setq indentation-list (nconc (make-list (ink-count-choices) 'gather)
                                        indentation-list)))

         ;; Increase indent on opening bracket with condition
         ((and
           (> bracket-difference 0)
           (looking-at "^\\s-*{\\s-*.*?:"))
          (unless on-last-line
            (push 'bracket-cond indentation-list)))

         ;; Decrease indent on closing bracket
         ((and (looking-at ".*[{}]")
               (< bracket-difference 0))
          (while (and (not (or (eq 'bracket (nth 0 indentation-list))
                               (eq 'bracket-cond (nth 0 indentation-list))))
                      (> (length indentation-list) 0))
            (pop indentation-list))
          (when (> (length indentation-list) 0)
            (pop indentation-list))))

        ;; Increase indent on opening bracket
        (when (and
               (looking-at ".*{")
               (> bracket-difference 0)
               (not (looking-at "^\\s-*{.*?:")) ;; already addressed
               (not on-last-line))
          (push 'bracket indentation-list))

        (forward-line 1))

      ;; Add up indentations from list
      (goto-char start-pos)
      ;; Reverse list, because each level may depend on the
      ;; previous ones
      (setq indentation-list (reverse indentation-list))
      (let (element value)
        ;; pop each level in turn, then accumulate the indentation
        ;; depending on element type
        (while (> (length indentation-list) 0)
          (setq element (pop indentation-list))
          (cond
           ((eq element 'choice)
            (if (looking-at "^\\s-*[*+]") ;; on choice line
                (setq value tab-width)
              (if ink-indent-choices-with-spaces
                  (setq value (ink-calculate-choice-indentation
                               element indentation-list indentation))
                (setq value (* 2 tab-width)))))

           ((eq element 'gather)
            (if (looking-at "^\\s-*\\(-[^>]\\|-$\\)") ;; on gather line
                (setq value tab-width)
              (if ink-indent-choices-with-spaces
                  (setq value (ink-calculate-choice-indentation
                               element indentation-list indentation))
                (setq value (* 2 tab-width))))
            ;; Cancel last gather, to unindent once
            (when (not (eq element
                           (nth 0 indentation-list)))
              (setq value (- value tab-width))))

           ((eq element 'bracket)
            (setq value tab-width))
           ((eq element 'bracket-cond)
            (setq value tab-width))
           ((eq element 'cond)
            (setq value tab-width)))
          (when value
            (setq indentation (+ indentation value))))))
    indentation))

(defun ink-calculate-choice-indentation (element indentation-list indentation)
  "Return the number of columns to indent choice and gather markers.
This depends on previous indentation, and settings.  ELEMENT is
the current element in the INDENTATION-LIST for the lign to
indent.  INDENTATION is the current sum."
  (let (value)
    (if ink-indent-choices-with-spaces
        (if (eq element (nth 0 indentation-list))
            ;; all but last elements
            (setq value (+ 2 tab-width))
          ;; last element
          (if indent-tabs-mode
              ;; find the closest tab, depending on current
              ;; indentation
              (setq value
                    (- (* tab-width
                          (ceiling (/ (+ 2.0 tab-width
                                         indentation)
                                      tab-width)))
                       indentation))
            (setq value (* 2 tab-width))))
      (setq value (* 2 tab-width)))
    value))


;;; Ink-play

(defvar-keymap ink-play-mode-map
  :doc "Keymap for `ink-play' mode.
`ink-play' and `ink-play-knot' in this mode will re-run the last
`ink-play' and `ink-play-knot' commands in the same buffer."
  "C-c C-h" #'ink-display-manual
  "C-c C-c" #'ink-play
  "C-c C-p" #'ink-play-knot)

(define-derived-mode ink-play-mode comint-mode "Ink-Play"
  "Major mode for `ink-play'.
Derives from `comint-mode', adds a few ink bindings."
  (add-hook 'comint-preoutput-filter-functions #'ink-comint-filter-output nil t))

(defvar-local ink-comint-do-filter nil)

(defun ink-play-knot ()
  "Play the current ink buffer from the knot or stitch at point."
  (interactive)
  (ink-play t))

(defvar ink-last-played-file-name nil
  "Last known file name that was run.")
(defvar ink-last-played-knot nil
  "Last known knot name that was run .")

(defun ink-play (&optional go-to-knot)
  "Play the current ink buffer.
If the GO-TO-KNOT optional argument is non-nil, start at the knot
or stitch at point.  In that case we issue \"-> knot.stitch\" to
the process, and suppress the beginning output using the comint
output filter."
  (interactive "P")
  (let* (;; check this ahead of (set-buffer)
         (in-ink-play-buffer (equal major-mode 'ink-play-mode))

         ;; if our buffer isn't referring to a real file (eg. *Ink*),
         ;; use the cached last-file-name
         (file-name (if in-ink-play-buffer ink-last-played-file-name
                      (buffer-file-name)))

         ;; needs to run before set-buffer call
         (knot-name (when go-to-knot
                      (if in-ink-play-buffer
                          ;; return the last played knot
                          ink-last-played-knot
                        ;; return a knot name if found, nil otherwise
                        (let ((kn (ink-get-knot-name)))
                          (unless (string-empty-p kn) kn)))))

         (ink-buffer
          (if (or
               ;; our process is already running, so this ink-play
               ;; should just execute inklecate
               (comint-check-proc "*Ink*")
               ;; OR we are already in the *Ink* buffer, but the process
               ;; has finished, so kick it off again
               in-ink-play-buffer)
              (progn
                (comint-exec "*Ink*" "Ink" (ink--inklecate-executable)
                             nil `("-p" ,file-name))
                "*Ink*")
            ;; no *Ink* buffer yet, need to create it
            (progn
              (let ((new-buffer
                     (make-comint "Ink" (ink--inklecate-executable) nil
                                  "-p" (buffer-file-name))))
                (set-buffer new-buffer)
                (ink-play-mode)
                new-buffer)))))

    ;; update the last ink-file/knot attempted (to support 'replaying')
    (setq ink-last-played-file-name file-name)
    ;; conditionally update to preserve knot-name across 'full' replays,
    ;; which would otherwise clear it
    (when knot-name
      (setq ink-last-played-knot knot-name))

    ;; only switch window if we're not already focused
    (unless in-ink-play-buffer
      (switch-to-buffer-other-window ink-buffer))

    (comint-clear-buffer)
    (if (and go-to-knot knot-name)
        (progn
          (setq ink-comint-do-filter t)
          (message (concat "Running " knot-name "..."))
          (comint-send-string (get-process "Ink")
                              (concat "-> " knot-name "\n"))
          (comint-delete-output)
          (comint-clear-buffer))
      (setq ink-comint-do-filter nil))
    (message "Running Ink...")))

(defun ink-filter-output-line (line)
  "Filter single line of text from Inklecate's output.
The filter is active only on starting play.  It outputs all
errors, warnings and infos appearing in LINE, and discards the
rest."
  (let ((result ""))
    (if ink-comint-do-filter
        (cond ((string-match-p "^\\(ERROR:\\|WARNING:\\|TODO:\\)" line)
               (setq result (concat line "\n")))
              ((string-match-p "\\?>" line)
               (setq result (concat (substring line 3) "\n"))
               (setq ink-comint-do-filter nil))
              ((not result)
               (setq result "")))
      (setq result (concat line "\n")))
    result))

(defun ink-comint-filter-output (output)
  "Comint output filter for `ink-play'.
This whole filter is just so that the first output of comint
doesn't print before the first important line when starting
directly at a knot... OUTPUT is the output to be filtered."
  (if ink-comint-do-filter
      (setq output (mapconcat #'ink-filter-output-line (split-string output "\n") "")))
  output)


;;; Error checking with Flymake

(defun ink--flymake-type-from-tag (tag)
  "Map compiler error TAG to Flymake warning types."
  (pcase (upcase tag)
    ("ERROR" :error)
    ("WARNING" :warning)
    ("TODO" :note)
    ;; NOTE: shouldn't happen as we use a regexp to catch all options
    (_ (error "Uknown error tag"))))

(defun ink--flymake-parse-line (line)
  "Parse a single inklecate output LINE.
Return a plist (:file :line :type :msg) or nil."
  (when (string-match
         ;; Error tag here should match the ones in
         ;; `ink--flymake-type-from-tag'.
         (rx bol
             ;; Tag
             (group (or "ERROR" "WARNING" "TODO")) ":" (* space)
             ;; File
             (? "'") (group (+ (not (any "'")))) (? "'")
             ;; Line
             (* space) "line" (+ space) (group (+ digit)) ":" (* space)
             ;; End of line
             (group (* any)) eol)
         line)
    (list :file (match-string 2 line)
          :line (string-to-number (match-string 3 line))
          :type (ink--flymake-type-from-tag (match-string 1 line))
          :msg  (string-trim (match-string 4 line)))))

(defun ink--flymake-parse-output (output)
  "Parse inklecate OUTPUT into a list of plists."
  (delq nil (mapcar #'ink--flymake-parse-line (split-string output "\n" t))))

(defun ink--flymake-same-file-p (a b default-dir)
  "Non-nil if files A and B refer to the same file (best-effort).
A or B may be relative; DEFAULT-DIR is used to resolve."
  (let ((aa (expand-file-name a default-dir))
        (bb (expand-file-name b default-dir)))
    (or (file-equal-p aa bb)
        ;; Some inklecate outputs only basenames; keep this as a fallback.
        (string-equal (file-name-nondirectory aa)
                      (file-name-nondirectory bb)))))

(defun ink--flymake-items-to-diagnostics (items source-buf temp-file default-dir)
  "Convert parsed ITEMS into Flymake diagnostics for SOURCE-BUF.
TEMP-FILE - temporary file used to run the checks.  DEFAULT-DIR -
directory used to run the check."
  (let (diags)
    (dolist (it items)
      (let* ((f (plist-get it :file))
             (line (or (plist-get it :line) 1))
             (type (or (plist-get it :type) :warning))
             (msg (or (plist-get it :msg) "")))
        (when (ink--flymake-same-file-p f temp-file default-dir)
          (pcase-let ((`(,beg . ,end) (flymake-diag-region source-buf line)))
            (push (flymake-make-diagnostic source-buf beg end type msg) diags)))))
    diags))

(defvar-local ink--flymake-proc nil)
(defvar-local ink--flymake-missing-compiler-warned nil)

;;; TODO: Also report errors in INCLUDE'd files.
(defun ink-flymake-inklecate (report-fn &rest _args)
  "Flymake backend for Ink using inklecate.
REPORT-FN - Flymake diagnostics reporting function."
  (let* ((source (current-buffer))
         (executable (ink--inklecate-executable))
         (source-file (buffer-file-name source)))
    (cond
     ;; Missing compiler: fail soft.
     ((not executable)
      (unless ink--flymake-missing-compiler-warned
        (warn "ink-mode Flymake disabled: cannot find `%s'; set `ink-inklecate-command'."
              ink-inklecate-command)
        (setq ink--flymake-missing-compiler-warned t))
      (funcall report-fn nil))

     ;; Unsaved buffers: no stable base path for INCLUDE resolution.
     ((not source-file)
      (funcall report-fn nil))

     (t
      ;; Compiler is back; allow future warnings if it disappears.
      (setq ink--flymake-missing-compiler-warned nil)

      ;; Process stuck?
      (when (process-live-p ink--flymake-proc)
        (kill-process ink--flymake-proc))

      (let* ((default-dir (file-name-directory source-file))
             ;; Tmp source file in same dir so INCLUDE relative paths
             ;; work.
             (temp-ink (make-temp-file
                        (expand-file-name
                         (concat (file-name-base source-file) "-flymake-")
                         default-dir)
                        nil ".ink"))

             ;; Dump stdout somewhere.
             (cmd (append (list executable
                                "-o" (or null-device (make-temp-name "NUL")))
                          (list temp-ink))))

        ;; Write to a temporary file.
        (save-restriction
          (widen)
          (write-region (point-min) (point-max) temp-ink nil 'silent))

        ;; Launch the process.
        (setq ink--flymake-proc
              (make-process
               :name "ink-flymake"
               :noquery t
               :buffer (generate-new-buffer " *ink-flymake*")
               :command cmd
               :sentinel
               (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (unwind-protect
                       (when (and (buffer-live-p source)
                                  (eq proc ink--flymake-proc))
                         ;; buffer string -> parse -> diags -> report.
                         (funcall
                          report-fn
                          (thread-first
                            (with-current-buffer (process-buffer proc)
                              (buffer-string))
                            (ink--flymake-parse-output)
                            (ink--flymake-items-to-diagnostics
                             source temp-ink default-dir))))
                     ;; Cleanup on exit/failure.
                     (ignore-errors (delete-file temp-ink))
                     (kill-buffer (process-buffer proc))))))))))))


;;; Outline

(defun ink-end-of-subtree (&optional invisible-OK)
  "Move to the end of the current subtree.
Only visible heading lines are considered, unless INVISIBLE-OK is
non-nil.
Derived from `markdown-end-of-subtree', derived from `org-end-of-subtree'."
  (outline-back-to-heading invisible-OK)
  (let ((first t)
        (level (ink-outline-level)))
    (while (and (not (eobp))
                (or first (> (ink-outline-level) level)))
      (setq first nil)
      (outline-next-heading))
    (if (memq (preceding-char) '(?\n ?\^M))
        (progn
          ;; Go to end of line before heading
          (forward-char -1)
          (if (memq (preceding-char) '(?\n ?\^M))
              ;; leave blank line before heading
              (forward-char -1)))))
  (point))

(defun ink-get-knot-name ()
  "Return the name of the knot at point, or knot.stitch if in stitch."
  (save-excursion
    (let ((knot-name ""))
      (when (ignore-errors (outline-back-to-heading t))
        (re-search-forward ink-regex-header)
        (setq knot-name (match-string-no-properties 3))
        (if (= (ink-outline-level) 2)
            ;; Currently in stitch, go up to look at knot
            (progn
              (ignore-errors (outline-up-heading 1))
              (re-search-forward ink-regex-header)
              (setq knot-name
                    (concat (match-string-no-properties 3) "."
                            knot-name))))
        knot-name))))

(defun ink-get-label-name ()
  "Return the name of the label at point.
Can also be knot.label if in knot, or knot.stitch.label if in
stitch."
  (save-excursion
    (beginning-of-line)
    (let (
          knot-name
          (title-list (list)))
      (re-search-forward ink-regex-label (line-end-position) t)
      (setq title-list (list (match-string-no-properties 2)))
      (setq knot-name (ink-get-knot-name))
      (if (and knot-name title-list)
          (setq title-list (append title-list (reverse (split-string knot-name "\\.")))))
      title-list)))

(defun ink-outline-level ()
  "Return the depth to which a statement is nested in the outline."
  (if (> (length (match-string-no-properties 1)) 1) 1 2))


;;; Symbols

(defun ink--collect-symbols ()
  "Return parsed symbols from the current buffer.
Each result entry is a plist with `:kind', `:name', `:position'
and `:completion-targets' keys."
  (let (symbols)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (beginning-of-line)
        (cond
         ((looking-at ink-regex-header)
          (when-let* ((kind (if (= (ink-outline-level) 1) 'knot 'stitch))
                      (short-name (match-string-no-properties 3))
                      (full-name (ink-get-knot-name)))
            (push (list :kind kind
                        :name full-name
                        :position (line-beginning-position)
                        :completion-targets (delete-dups (list short-name full-name)))
                  symbols)))
         ((looking-at ink-regex-label)
          (when-let* ((label-parts (ink-get-label-name))
                      (short-name (car label-parts))
                      (full-name (mapconcat #'identity (reverse label-parts) ".")))
            (push (list :kind 'label
                        :name full-name
                        :position (line-beginning-position)
                        :completion-targets (delete-dups (list short-name full-name)))
                  symbols))))
        (forward-line 1)))
    (nreverse symbols)))

(defun ink--imenu-create-index ()
  "Return imenu index for the current Ink buffer."
  (let (knots stitches labels)
    (dolist (symbol (ink--collect-symbols))
      (let ((entry (cons (plist-get symbol :name)
                         (plist-get symbol :position))))
        (pcase (plist-get symbol :kind)
          ('knot (push entry knots))
          ('stitch (push entry stitches))
          ('label (push entry labels)))))
    (setq knots (nreverse knots))
    (setq stitches (nreverse stitches))
    (setq labels (nreverse labels))
    (delq nil (list (and knots (cons "Knots" knots))
                    (and stitches (cons "Stitches" stitches))
                    (and ink-imenu-include-labels labels (cons "Labels" labels))))))

(defun ink--current-symbol-name ()
  "Return current Ink symbol name at point, or nil if unknown.
When `ink-imenu-include-labels' is non-nil, labels can be returned."
  (let ((pos (point))
        name)
    (dolist (symbol (ink--collect-symbols))
      (let ((kind (plist-get symbol :kind)))
        (when (and (<= (plist-get symbol :position) pos)
                   (or (not (eq kind 'label))
                       ink-imenu-include-labels))
          (setq name (plist-get symbol :name)))))
    name))


;;; Autocomplete

(defun ink-get-headers-and-labels ()
  "Return divert completion targets for headers and labels."
  (let ((headers-labels (list "END" "DONE")))
    (dolist (symbol (ink--collect-symbols))
      (dolist (target (plist-get symbol :completion-targets))
        (push target headers-labels)))
    (sort (delete-dups headers-labels) #'string<)))

(defun ink-completion-at-point ()
  "Return completion table for entity at point.
Completion is only provided for diverts."
  (when (and (thing-at-point-looking-at ink-regex-divert)
             (<= (match-beginning 3)
                 (point)))
    (when (> (match-beginning 2)
             (point))
      (goto-char (match-end 2)))
    (list (match-beginning 2) (match-end 2)
          (completion-table-dynamic
           (lambda (_) (ink-get-headers-and-labels))))))


;; Snippets -- taken from pony-mode.el

(defcustom ink-snippet-dir (expand-file-name
                            (concat (file-name-directory (or load-file-name default-directory))
                                    "./snippets"))
  "Directory in which to locate Yasnippet snippets for Ink Mode."
  :group 'ink
  :type 'string)

;;;###autoload
(defun ink-load-snippets()
  "Manually load snippets if yasnippet installed and `ink-snippet-dir' is set.
This command is explicit and can be used to reload bundled snippets."
  (interactive)
  (when ink-snippet-dir
    (cond
     ((fboundp 'yas-load-directory)
      (yas-load-directory ink-snippet-dir))
     ((fboundp 'yas/load-directory)
      (yas/load-directory ink-snippet-dir))
     (t
      (user-error
       "YASnippet is not loaded yet; Ink snippets were not loaded")))))


;;; Help

(defun ink-display-manual ()
  "Display the Writing With Ink manual."
  (interactive)
  (info-display-manual "WritingWithInk"))


;;; Mode Definition

;;;###autoload
(define-derived-mode ink-mode prog-mode "Ink"
  "Major mode for the Ink interactive fiction scripting language."

  ;; Syntax
  (setq-local comment-start "// ")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local comment-use-syntax t)
  (setq-local comment-end "")
  (setq-local comment-auto-fill-only-comments t)
  (setq-local font-lock-defaults '(ink-font-lock-keywords))

  ;; Indent
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local indent-line-function #'ink-indent-line)

  ;; Complete
  (setq-local completion-cycle-threshold t)
  (add-hook 'completion-at-point-functions
            #'ink-completion-at-point nil 'local)

  ;; Outline
  (setq-local outline-regexp ink-regex-header)
  (setq-local outline-level #'ink-outline-level)

  ;; Imenu
  (setq-local imenu-create-index-function #'ink--imenu-create-index)
  (add-hook 'which-func-functions #'ink--current-symbol-name nil 'local)
  (setq-local add-log-current-defun-function #'ink--current-symbol-name)

  ;; Flymake
  (add-hook 'flymake-diagnostic-functions 'ink-flymake-inklecate nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.ink\\'" . ink-mode))

(provide 'ink-mode)
;;; ink-mode.el ends here
