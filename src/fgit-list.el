;;; fgit-list.el --- Maintain a list of Git repositories

;; ************************************************************************ ;;
;;  File:       fgit-list.el                                                ;;
;;  Author:     F. Georges - fgeorges.org - h2o.consulting                  ;;
;;  Date:       2018-10-28                                                  ;;
;;  Tags:                                                                   ;;
;;      Copyright (c) 2018 Florent Georges (see end of file.)               ;;
;; ------------------------------------------------------------------------ ;;
;;
;;; Package info:
;;
;; Package-Requires: ((magit "2.1"))
;; Keywords: git tools magit
;; Homepage: https://github.com/fgeorges/emacs-flib
;;
;;; Commentary:
;;
;; Maintain a list of Git repositories.
;;
;; Given a list of Git repositories from your system, you can display them with
;; their status: is there anything to commit, any commit to pull, is the branch
;; behind its upstream?  If you work on many repositories at once, this allows
;; you to identify which repositories need action at a glance.  In your .emacs,
;; make sure that you load the library, and that you configure the list of your
;; repositories:
;;
;;     (load-library "fgit-list")
;;     (setq fgit:repositories
;;           '(((:path . "/home/me/projects/elisp/foobar/")  (:fetch . t))
;;             ((:path . "/home/me/projects/elisp/somelib/"))
;;             ((:path . "/home/me/projects/git/fourtytwo/") (:fetch . t))))

;;; Code:

;; TODO: Use defcustom instead.
(defvar fgit:repositories ()
  "The list of all Git repositories on this system.

This is a list of alists, one per repo.  Each alist must have an entry `:path',
and can have an entry `:fetch'.  The former is the path to the Git repo, the
latter is whether it is allowed to perform a fetch before looking at the repo,
to be able to detect whether the branch is behind upstream.

Example:

    '(((:path . \"/home/me/projects/elisp/foobar/\") (:fetch . t))
      ((:path . \"/home/me/projects/git/fourtytwo/\")))

To find all repos on a system, one of the following commands might help you (on
Unix-like systems):

> locate applypatch-msg | grep --color .git/hooks/applypatch-msg
> find /home/me/ -name 'applypatch-ms*' | grep --color .git/hooks/applypatch-msg")

(defvar fgit:fetch-by-default nil
  "Whether to fetch for all repositories.

When set to `t', it is aquivalent to set `(:fetch . t)' on all repos in
`fgit:repositories'.")

(defconst fgit:buffer-name "*fgit-repositories*")

(defface fgit:clean
  '((((class color) (background light)) :foreground "#5ac85a" :weight bold)
    (((class color) (background  dark)) :foreground "#4d994d" :weight bold))
  "Face for clean repos.")

(defface fgit:dirty
 '((((class color) (background light)) :foreground "#ff4545" :weight bold)
   (((class color) (background  dark)) :foreground "#b26767" :weight bold))
  "Face for dirty repos.")

(defface fgit:section
  '((((class color) (background light)) :foreground "#a28339")
    (((class color) (background  dark)) :foreground "#beb068"))
  "Face for sub sections.")

(defface fgit:repo-name
  '((t :inherit (bold)))
  "Face for repo paths.")

(defface fgit:repo-path
  '()
  "Face for repo paths.")

(defun fgit:insert (str face)
  (when str
    (insert (propertize str 'face face))))

(defun fgit:insert-repo (repo)
  (if (not (string-match "^\\(.*[/\\]\\)\\([^/\\]+\\)\\([/\\]\\)?$" repo))
      (fgit:insert repo 'fgit:repo-name)
    (fgit:insert (match-string 1 repo) 'fgit:repo-path)
    (fgit:insert (match-string 2 repo) 'fgit:repo-name)
    (fgit:insert (match-string 3 repo) 'fgit:repo-path)))

(defun fgit:start-magit-at (point)
  (interactive "d")
  (let ((repo (get-char-property point :fgit:repo)))
    (when (not repo)
      (error "No repo at: %d" point))
    (magit-status repo)))

(defun fgit:overlay-at (point)
  (let ((overlays (overlays-at point))
        found)
    (dolist (ol overlays)
      (when (overlay-get ol :fgit:repo)
        (when found
          (error "More than one overlay with prop :fgit:repo at %d" point))
        (setq found ol)))
    found))

(defun fgit:toggle-folding (point)
  (interactive "d")
  (let ((ol (fgit:overlay-at point)))
    (when (not ol)
      (error "No overlay with prop :fgit:repo at %d" point))
    (let ((folded (overlay-get ol :fgit:folded)))
      (goto-char (overlay-start ol))
      (if folded
          (outline-show-subtree)
        (outline-hide-subtree))
      (overlay-put ol :fgit:folded (not folded)))))

(defun fgit:pop-buffer ()
  (let ((buffer (get-buffer fgit:buffer-name)))
    (if buffer
        (progn
          (pop-to-buffer buffer)
          (read-only-mode 0)
          (erase-buffer))
      (setq buffer (get-buffer-create fgit:buffer-name))
      (pop-to-buffer buffer)
      ;; it seems that `outline-minor-mode' tries to access the local map before
      ;; it is set (`local-set-key' would have avoided that, had they used it)
      (unless (current-local-map)
        (use-local-map (make-sparse-keymap)))
      (outline-minor-mode 1)
      (toggle-truncate-lines 1)
      (local-set-key (kbd "q")     'bury-buffer)
      (local-set-key (kbd "RET")   'fgit:start-magit-at)
      (local-set-key (kbd "<tab>") 'fgit:toggle-folding))
    buffer))

(defun fgit:git-to-string (repo options)
  (let ((default-directory repo))
    (shell-command-to-string (concat "git " options))))

(defun fgit:repo-file-status (line)
  (let ((index (elt line 0))
        (fs    (elt line 1))
        (file  (substring line 3)))
    (when (and (= (elt file 0) ?\") (= (elt file (- (length file) 1)) ?\"))
      (setq file (substring file 1 -1)))
    ;; both <spc>, or none <spc> and both different
    (cond ((and (=  index ? ) (=  fs ? ))
           (error "Both index and FS statuses are <space>"))
          ((and (/= index ? ) (/= fs ? ) (/= index fs))
           (error "None of index and FS statuses are <space>, yet they are different"))
          ((/= index ? )
           (cons index file))
          ((/= fs ? )
           (cons fs file))
          (t
           (error "Logic error, cannot happen!")))))

(defun fgit:repo-commit-status (line)
  (let ((arrow  (elt line 0))
        (commit (substring line 1)))
    (when (and (/= arrow ?<) (/= arrow ?>))
      (error "Arrow is neither < or >: %s" line))
    (cons arrow commit)))

(defun fgit:current-upstream (repo)
  (let ((output (fgit:git-to-string repo "rev-parse --abbrev-ref @{upstream}")))
    (if (not (string-prefix-p "fatal: " output))
        (substring output 0 -1) ; remove end of line
      (let* ((output  (fgit:git-to-string repo "rev-parse --abbrev-ref HEAD"))
             ;; TODO: "origin" should be in a "default variable", overridable in
             ;; the repo alist itself...
             (branch  (concat "origin/" (substring output 0 -1))) ; remove end of line
             (options (concat "rev-list --left-right " branch "..." branch))
             (output  (fgit:git-to-string repo options)))
        (unless (string-prefix-p "fatal: " output)
          branch)))))

(defun fgit:repo-status (repo)
  (let (ahead behind modified deleted unknown)
    (let ((upstream (fgit:current-upstream repo)))
      (when upstream
        (let* ((options (concat "rev-list --left-right ..." upstream))
               (commits (fgit:git-to-string repo options)))
          (dolist (line (split-string commits "\n"))
            (when (> (length line) 0)
              (let* ((res    (fgit:repo-commit-status line))
                     (arrow  (car res))
                     (commit (cdr res)))
                (cond ((= arrow ?<) (push commit ahead))
                      ((= arrow ?>) (push commit behind))
                      (t
                       (error "Unknown porcelain commit arrow: '%c'" arrow)))))))))
    (let ((output (fgit:git-to-string repo "status --porcelain")))
      (dolist (line (split-string output "\n"))
        (when (> (length line) 0)
          (let* ((file   (fgit:repo-file-status line))
                 (status (car file))
                 (path   (cdr file)))
            (cond ((= status ?M) (push path modified))
                  ((= status ?D) (push path deleted))
                  ((= status ??) (push path unknown))
                  (t
                   (error "Unknown porcelain file status: '%c'" status)))))))
    (list
     (cons :ahead    ahead)
     (cons :behind   behind)
     (cons :modified modified)
     (cons :deleted  deleted)
     (cons :unknown  unknown))))

(defun fgit:check-repos (arg)
  "Check the status of all the Git repositories on the system.

The repositories are those in `fgit:repositories'.  Invoked with a universal
argument (aka `C-u'), it performs a `git fetch' before checking each repo.
Display the result in a temporary buffer."
  (interactive "P")
  (let ((dofetch (and arg (yes-or-no-p "Do fetch? "))))
    (fgit:pop-buffer)
    (insert "List all Git repositories on this system, and whether they are clean or not.\n")
    (insert "- TAB: show/hide details of a non-clean (or \"dirty\") repo\n")
    (insert "- RET: on a repository, opens Magit (the status screen)\n")
    (insert "- q: bury the buffer\n")
    (insert "\n")
    (dolist (repo fgit:repositories)
      (when (stringp repo)
        (setq repo (list (cons :path repo))))
      (let ((path  (cdr (assq :path  repo)))
            (fetch (cdr (assq :fetch repo))))
        (when (and dofetch (or fetch fgit:fetch-by-default))
          (fgit:git-to-string path "fetch"))
        (let* ((status   (fgit:repo-status path))
               (ahead    (cdr (assq :ahead    status)))
               (behind   (cdr (assq :behind   status)))
               (modified (cdr (assq :modified status)))
               (deleted  (cdr (assq :deleted  status)))
               (unknown  (cdr (assq :unknown  status)))
               (isahead  (> (length ahead)    0))
               (isbehind (> (length behind)   0))
               (hasmod   (> (length modified) 0))
               (hasdel   (> (length deleted)  0))
               (hasunk   (> (length unknown)  0))
               (start    (point)))
          (cond ((not (or hasmod hasdel hasunk isahead isbehind))
                 (fgit:insert "* " 'fgit:clean)
                 (fgit:insert-repo path)
                 (insert (make-string (max 2 (- 70 (length path))) ? ))
                 (fgit:insert "clean" 'fgit:clean)
                 (insert "\n"))
                (t
                 (fgit:insert "* " 'fgit:dirty)
                 (fgit:insert-repo path)
                 (insert (make-string (max 2 (- 70 (length path))) ? ))
                 (fgit:insert "dirty" 'fgit:dirty)
                 (insert "\n")
                 (when isahead
                   (fgit:insert "** ahead" 'fgit:section)
                   (insert "\n" (int-to-string (length ahead)) " commit(s) ahead\n"))
                 (when isbehind
                   (fgit:insert "** behind" 'fgit:section)
                   (insert "\n" (int-to-string (length behind)) " commit(s) behind\n"))
                 (when hasmod
                   (fgit:insert "** modified" 'fgit:section)
                   (insert "\n")
                   (dolist (file modified)
                     (insert file "\n")))
                 (when hasdel
                   (fgit:insert "** deleted" 'fgit:section)
                   (insert "\n")
                   (dolist (file deleted)
                     (insert file "\n")))
                 (when hasunk
                   (fgit:insert "** unknown" 'fgit:section)
                   (insert "\n")
                   (dolist (file unknown)
                     (insert file "\n")))))
          (let ((ol (make-overlay start (point))))
            (overlay-put ol :fgit:repo   path)
            (overlay-put ol :fgit:folded t))))
      (redisplay))
    ;; collapse all repos
    (outline-hide-sublevels 1)
    (read-only-mode 1)))


;; ------------------------------------------------------------------------ ;;
;;  DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS COMMENT.               ;;
;;                                                                          ;;
;;  The contents of this file are subject to the Apache License Version     ;;
;;  2.0 (the "License"); you may not use this file except in compliance     ;;
;;  with the License. You may obtain a copy of the License at               ;;
;;  http://www.apache.org/licenses/.                                        ;;
;;                                                                          ;;
;;  Software distributed under the License is distributed on an "AS IS"     ;;
;;  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied.  See    ;;
;;  the License for the specific language governing rights and limitations  ;;
;;  under the License.                                                      ;;
;;                                                                          ;;
;;  The Original Code is: all this file.                                    ;;
;;                                                                          ;;
;;  The Initial Developer of the Original Code is Florent Georges.          ;;
;;                                                                          ;;
;;  Contributor(s): none.                                                   ;;
;; ------------------------------------------------------------------------ ;;
