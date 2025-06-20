;;; mediawiki-el-search.el --- Some additional search functions for mediawiki.el

;; Copyright 2026 - Twitchy Ears

;; Author: Twitchy Ears https://github.com/twitchy-ears/
;; URL: https://github.com/twitchy-ears/mediawiki-el-search
;; Version: 0.1
;; Package-Requires ((emacs "30.1"))
;; Keywords: mediawiki wikipedia network wiki

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; History
;;
;; 2026-06-21 - initial version

;;; Commentary:

;; Additional to mediawiki.el from https://github.com/hexmode/mediawiki-el

;; (use-package mediawiki)
;; (use-package mediawiki-el-search)

;; Call M-x mediawiki-search-for-titles-to-buffer and then
;; mediawiki-open-page-at-point on each result.

(require 'cl-seq)

(defun mediawiki-api-call-json (sitename action &optional args)
  "Wrapper for making an API call to SITENAME.
ACTION is the API action.  ARGS is a list of arguments.

This returns a hashtable of hashtables most likely and parses that from
 a JSON blob returned from mediawiki.

You should be using `mediawiki-api-call' for most things."
  (mediawiki-debug-line (format "\n\n----\nFor %s (action=%s):\n\n %s\n" sitename action
                                (mm-url-encode-multipart-form-data
                                 (delq nil args) "==")))
  (let* ((raw (url-http-post (mediawiki-make-api-url sitename)
                             (append args (list (cons "format" "json")
                                                (cons "action" action)))))
         ;; (result (json-parse-string raw :object-type 'alist :array-type 'list)))
         (result (json-parse-string raw)))
    
    (unless result
      (error "There was an error parsing the result of the API call"))

    (unless (gethash action result)
      (error "There was an error, no key containing the action '%s'" action))

    result))


;; Cribbed from mediawiki-edit and mediawiki-get
(defun mediawiki-search (sitename what pattern &optional offset results)
  "Search for pages on a mediawiki and return a list of hashes of results

sitename should be a textual sitename associated with a mediawiki-mode site.

what should be a string, one of 'nearmatch', 'text', 'title', if nil set to 'title'

pattern should be the text string you're searching for

offset is for continuing a search

results is accumulating results of a search

see: https://www.mediawiki.org/wiki/API:Search for more

It will return a list of hashes containing the following keys:
ns, title, pageid, size, wordcount, timestamp"

  ;; Log in if we're not already
  (unless (mediawiki-logged-in-p sitename)
    (mediawiki-do-login sitename))

  (when (not what)
    (setq what "title"))

  (when (not results)
    (setq results (list)))

  ;; (message "Results currently: %d" (length results))

  (if offset
      (if (stringp offset)
          (setq offset (string-to-number offset)))
    (setq offset 0))
  

  (let* ((api-args (list (cons "list" (mediawiki-api-param "search"))
                         (cons "srwhat" (mediawiki-api-param what))
                         (cons "srsearch" (mediawiki-api-param pattern))
                         (cons "srprop" (mediawiki-api-param "size|wordcount|timestamp"))
                         (cons "srlimit" (mediawiki-api-param 10))
                         (cons "sroffset" (mediawiki-api-param offset))))
  
         (result (mediawiki-api-call-json sitename
                                          "query"
                                          api-args)))

    ;; (message "Called with api-args '%s'" api-args)
    ;; (maphash (lambda (key val) (message "res: '%s' => '%s'" key val)) result)

    (let* ((cont (gethash "continue" result))
           (sroffset (if cont (gethash "sroffset" cont)))
           (query (gethash "query" result))
           (searchinfo (if query
                           (gethash "searchinfo" query)))
           (search-data (if query
                            (gethash "search" query))))

      ;; (when cont
      ;;  (message "CONT '%s'" cont))

      (when search-data
        ;; (message "search-data '%s'" search-data)
        (mapc (lambda (x)
                ;; (message "Appending '%s'" x)
                (setq results (append results (list x))))
              search-data))

      ;; (message "Appending '%s' to '%s'" query results)
      ;; (setq results (append results (list query)))
    
      ;; If we're not batchcomplete then recurse to accumulate
      (if (or (not (equal "" (gethash "batchcomplete" result)))
              (not sroffset))

          (progn 
            ;; (message "Final results count '%d'" (length results))
            (cl-remove-duplicates results :test (lambda (x y)
                                                  (equal (gethash "title" x)
                                                         (gethash "title" y)))))

        ;; Otherwise recurse
        (progn 
          ;; (message "Recursing to %s" sroffset)
          (mediawiki-search sitename what pattern sroffset results))))))
      

(defun mediawiki-search-for-titles (sitename pattern)
  "Searches mediawiki 'sitename' for pages whos titles include 'pattern'

Returns a list of page titles"
  (interactive)
  (let ((res (mapcar (lambda (x) (gethash "title" x))
                     (mediawiki-search sitename "title" pattern))))
    res))


(defun mediawiki-search-for-titles-by-text (sitename pattern)
  "Searches mediawiki 'sitename' for pages whos text includes 'pattern'

Returns a list of page titles"
  (interactive)
  (let ((res (mapcar (lambda (x) (gethash "title" x))
                     (mediawiki-search sitename "text" pattern))))
    res))

(defun mediawiki-search-for-titles-to-buffer (&optional sitename pattern)
  "Searches mediawiki 'sitename' for pages whos title includes 'pattern'

Creates a buffer called *mediawiki-pages* containing these within [[name]] blocks

This is so you can mediawiki-open-page-at-point on them"
  (interactive)

  (unless sitename
    (setq sitename 
          (if mediawiki-site
              mediawiki-site
            (mediawiki-prompt-for-site))))

  (unless pattern
    (setq pattern (read-from-minibuffer "page title contains: " nil))) ;; 'my-history)

  (if (or (not sitename)
          (not pattern))
      (error "One of sitename (%s) and pattern (%s) unset" sitename pattern))
     
  (let* ((bufname "*mediawiki-pages*")
         (buf (progn
                (if (get-buffer bufname)
                    (kill-buffer bufname))
                (get-buffer-create bufname)))
         (res (mediawiki-search sitename "title" pattern)))
    
    (with-current-buffer buf
      (erase-buffer)
      (goto-char (point-min))
      (mapcar (lambda (x)
                (let ((title (gethash "title" x))
                      (wordcount (gethash "wordcount" x))
                      (timestamp (gethash "timestamp" x)))
                (insert (format "[[%s]] (wordcount: %d / date: %s)\n" title wordcount timestamp))))
              (sort res :key (lambda (x) (gethash "title" x))))
      (goto-char (point-min)))

    (pop-to-buffer buf)))

(provide 'mediawiki-el-search)
