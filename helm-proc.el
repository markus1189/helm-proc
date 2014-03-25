;;; helm-proc.el --- Helm interface for managing system processes

;; Copyright (C) 2014 Markus Hauck

;; Author: Markus Hauck <markus1189@gmail.com>
;; Maintainer: Markus Hauck <markus1189@gmail.com>
;; Keywords: helm
;; Version: 0.0.1
;; Package-requires: ((helm "1.6.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This package provides a helm source `helm-source-proc' and a
;; configured helm `helm-proc'.  It is meant to be used to manage
;; emacs-external unix processes.
;;
;; With `helm-proc' a helm session is launched and you can perform
;; various helm actions on processes like sending signals, changing to
;; the corresponding /proc dir, attach strace...
;;
;; Example:
;;
;; Call `helm-proc' and:
;; type 'firefox'
;; => lists all processes named firefox or with firefox in args
;; press RET to send TERM signal
;;  or
;; press TAB for list of possible actions

;;; Code:
(require 'helm)
(require 'proced)

(defgroup helm-proc nil
  "Manage system processes with helm."
  :group 'helm)

(defcustom helm-proc-polite-delay 10
  "Number of seconds to wait when politely killing a process."
  :type 'number
  :group 'helm-proc)

(defcustom helm-proc-retrieve-pid-function 'helm-proc-system-pgrep
  "Function to retrieve a list of pids matching a pattern given as argument."
  :group 'helm-proc
  :type '(choice
          (function-item :tag "pgrep" :value helm-proc-system-pgrep)
          (function :tag "Custom function")))

(defcustom helm-proc-strace-buffer-name "*helm-proc-strace*"
  "Used as the buffer name for the output of strace when used by helm-proc."
  :type 'string
  :group 'helm-proc)

(defcustom helm-proc-strace-process-name "helm-proc-strace"
  "Used as the name for the strace process started by helm-proc."
  :type 'string
  :group 'helm-proc)

(defcustom helm-proc-strace-executable "strace"
  "Name of the strace executable."
  :type 'string
  :group 'helm-proc
  :type '(choice
          (string :tag "strace" :value "strace")
          (string :tag "ltrace" :value "ltrace")
          (string :tag "Custom executable")))

(defcustom helm-proc-strace-seconds 10
  "Number of seconds to collect strace data before process is killed."
  :type 'number
  :group 'helm-proc)

(defun helm-proc-candidates ()
  "Generate the candidate list for the current `helm-pattern'.
Then format elements for display in helm."
  (loop for candidate in (helm-proc-search helm-pattern)
        collect (helm-proc-format-candidate-for-display candidate)))

(defun helm-proc-system-pgrep (pattern)
  "Use external pgrep command to retrieve list of pids matching PATTERN."
  (loop for result in (split-string
                       (shell-command-to-string
                        (format "pgrep -f %s" pattern)) "\n")
        unless (string= "" result)
        collect (string-to-number result)))

(defun helm-proc-search (pattern)
  "Call `helm-proc-retrieve-pid-function' with PATTERN.
Return a list of pids as result."
  (funcall helm-proc-retrieve-pid-function pattern))

(defun helm-proc--resident-set-size (pid)
  (with-temp-buffer
         (insert-file-contents-literally (format "/proc/%s/status" pid))
         (goto-char (point-min))
         (search-forward "VmRSS:" nil t)
         (forward-word)
         (file-size-human-readable
          (* (string-to-number (word-at-point)) 1024)
          'iec)))

(defun helm-proc-format-candidate-for-display (pid)
  "Format PID for display in helm."
  (if (not pid) nil
    (let* ((attr-alist
            (cdar (proced-process-attributes `(,pid))))
           (command (assoc-default 'comm attr-alist))
           (args (assoc-default 'args attr-alist))
           (time (proced-format-time (assoc-default 'time attr-alist)))
           (state (assoc-default 'state attr-alist))
           (nice (assoc-default 'nice attr-alist))
           (user (assoc-default 'user attr-alist))
           (mem (helm-proc--resident-set-size pid))
           (display (format
                     "%s %s\nTime: '%s' State: '%s' Nice: '%s' User: '%s' Mem: %s\nArgs: '%s'"
                     pid
                     command
                     time
                     state
                     nice
                     user
                     mem
                     args)))
      (cons display pid))))

(defun helm-proc-action-copy-pid (pid)
  "Copy PID."
  (kill-new (format "%s" pid)))

(defun helm-proc-action-term (pid)
  "Send TERM to PID."
  (signal-process pid 'INT))

(defun helm-proc-action-kill (pid)
  "Send KILL to PID."
  (signal-process pid 'KILL))

(defun helm-proc-action-stop (pid)
  "Send STOP to PID to stop the process."
  (signal-process pid 'STOP))

(defun helm-proc-action-continue (pid)
  "Send CONT to PID to continue the process if stopped."
  (signal-process pid 'CONT))

(defun helm-proc-action-polite-kill (pid)
  "Send TERM to PID, wait for `helm-proc-polite-delay' seconds, then send KILL."
  (helm-proc-action-term pid)
  (run-with-timer helm-proc-polite-delay nil 'helm-proc-action-kill pid))

(defun helm-proc-action-find-dir (pid)
  "Open the /proc dir for PID."
  (find-file (format "/proc/%s/" pid)))

(defun helm-proc-action-timed-strace (pid)
  "Attach strace to PID, collect output `helm-proc-strace-seconds'."
  (and (start-process-shell-command
        helm-proc-strace-process-name
        helm-proc-strace-buffer-name
        (concat "echo " (shell-quote-argument (read-passwd "Sudo Password: "))
                (format " | sudo -S strace -p %s" pid)))
       (switch-to-buffer helm-proc-strace-buffer-name)
       (run-with-timer
        helm-proc-strace-seconds
        nil
        (lambda ()
          (kill-process
           (get-process helm-proc-strace-process-name))))))

(defvar helm-source-proc
  '((name . "Processes")
    (volatile)
    (requires-pattern . 2)
    (multiline)
    (match . ((lambda (x) t)))
    (action . (("Send TERM" . helm-proc-action-term)
               ("Copy the pid" . helm-proc-action-copy-pid)
               ("Send TERM, wait then KILL" . helm-proc-action-polite-kill)
               ("Just KILL" . helm-proc-action-kill)
               ("Stop process" . helm-proc-action-stop)
               ("Continue if stopped" . helm-proc-action-continue)
               ("Open corresponding /proc dir" . helm-proc-action-find-dir)
               ("Call strace to attach with time limit" . helm-proc-action-timed-strace)))
    (candidates . helm-proc-candidates)))

;;;###autoload
(defun helm-proc ()
  "Preconfigured helm for processes."
  (interactive)
  (helm :sources '(helm-source-proc)))

(provide 'helm-proc)
;;; helm-proc.el ends here
