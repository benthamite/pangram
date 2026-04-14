;;; pangram-test.el --- Tests for pangram.el -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT test suite for the Pangram AI content detection package.
;; All HTTP calls are mocked so no network access is required.

;;; Code:

(require 'ert)
(require 'pangram)
(require 'cl-lib)

;;;;; Helpers

(defun pangram-test--make-http-buffer (status-line headers body)
  "Return a temp buffer simulating an HTTP response.
STATUS-LINE is the HTTP status line, HEADERS is a string of
headers, and BODY is the response body string."
  (let ((buf (generate-new-buffer " *pangram-test-http*")))
    (with-current-buffer buf
      (insert status-line "\n" headers "\n\n" body))
    buf))

(defun pangram-test--sample-response ()
  "Return an alist mimicking a successful Pangram API response."
  '((headline . "Mostly AI")
    (fraction_ai . 0.7)
    (fraction_ai_assisted . 0.2)
    (fraction_human . 0.1)
    (windows . [((label . "AI Generated")
                 (start_index . 0)
                 (end_index . 10)
                 (ai_assistance_score . 0.95)
                 (confidence . "high"))
                ((label . "Human")
                 (start_index . 10)
                 (end_index . 20)
                 (ai_assistance_score . 0.05)
                 (confidence . "high"))])))

;;;;; pangram--escape-unicode-char

(ert-deftest pangram-test-escape-unicode-char-bmp ()
  "Escape a Basic Multilingual Plane character as \\uXXXX."
  (should (equal (pangram--escape-unicode-char ?A) "\\u0041"))
  (should (equal (pangram--escape-unicode-char #x00E9) "\\u00E9")))

(ert-deftest pangram-test-escape-unicode-char-surrogate-pair ()
  "Escape a character outside the BMP as a surrogate pair."
  (let ((result (pangram--escape-unicode-char #x1F600)))
    (should (equal result "\\uD83D\\uDE00"))))

;;;;; pangram--encode-request-body

(ert-deftest pangram-test-encode-request-body-ascii ()
  "Encode an ASCII-only string as JSON."
  (let ((result (pangram--encode-request-body "hello")))
    (should (string-match-p "\"text\"" result))
    (should (string-match-p "hello" result))))

(ert-deftest pangram-test-encode-request-body-non-ascii ()
  "Escape non-ASCII characters to \\uXXXX sequences."
  (let ((result (pangram--encode-request-body "caf\u00e9")))
    (should (string-match-p "\\\\u00E9" result))
    (should-not (multibyte-string-p
                 (encode-coding-string result 'ascii)))))

;;;;; pangram--label-face

(ert-deftest pangram-test-label-face-ai-generated ()
  "Return `pangram-ai' for AI-Generated labels."
  (should (eq (pangram--label-face "AI Generated") 'pangram-ai))
  (should (eq (pangram--label-face "AI-Generated") 'pangram-ai)))

(ert-deftest pangram-test-label-face-human ()
  "Return nil for Human labels."
  (should-not (pangram--label-face "Human")))

(ert-deftest pangram-test-label-face-assisted ()
  "Return `pangram-ai-assisted' for other non-nil labels."
  (should (eq (pangram--label-face "AI Assisted") 'pangram-ai-assisted))
  (should (eq (pangram--label-face "Mixed") 'pangram-ai-assisted)))

(ert-deftest pangram-test-label-face-nil ()
  "Return nil when LABEL is nil."
  (should-not (pangram--label-face nil)))

;;;;; pangram--check-http-status

(ert-deftest pangram-test-check-http-status-200 ()
  "Accept a 200 status code without error."
  (let ((buf (pangram-test--make-http-buffer
              "HTTP/1.1 200 OK" "Content-Type: application/json" "")))
    (unwind-protect
        (with-current-buffer buf
          (pangram--check-http-status))
      (kill-buffer buf))))

(ert-deftest pangram-test-check-http-status-500 ()
  "Signal an error for a 500 status code."
  (let ((buf (pangram-test--make-http-buffer
              "HTTP/1.1 500 Internal Server Error"
              "Content-Type: text/plain" "")))
    (unwind-protect
        (with-current-buffer buf
          (should-error (pangram--check-http-status) :type 'error))
      (kill-buffer buf))))

(ert-deftest pangram-test-check-http-status-malformed ()
  "Signal an error for a response with no HTTP status line."
  (let ((buf (generate-new-buffer " *pangram-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "garbage data\n\n{}")
          (should-error (pangram--check-http-status) :type 'error))
      (kill-buffer buf))))

;;;;; pangram--parse-response

(ert-deftest pangram-test-parse-response-valid-json ()
  "Parse a valid JSON body from an HTTP response buffer."
  (let ((buf (pangram-test--make-http-buffer
              "HTTP/1.1 200 OK"
              "Content-Type: application/json"
              "{\"headline\":\"AI\"}")))
    (unwind-protect
        (with-current-buffer buf
          (let ((result (pangram--parse-response)))
            (should (equal (alist-get 'headline result) "AI"))))
      (kill-buffer buf))))

(ert-deftest pangram-test-parse-response-malformed-json ()
  "Signal an error when the body is not valid JSON."
  (let ((buf (pangram-test--make-http-buffer
              "HTTP/1.1 200 OK"
              "Content-Type: application/json"
              "not json at all")))
    (unwind-protect
        (with-current-buffer buf
          (should-error (pangram--parse-response) :type 'error))
      (kill-buffer buf))))

(ert-deftest pangram-test-parse-response-no-header-boundary ()
  "Signal an error when there is no blank line separating headers."
  (let ((buf (generate-new-buffer " *pangram-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "HTTP/1.1 200 OK\nContent-Type: app/json\n{}")
          (should-error (pangram--parse-response) :type 'error))
      (kill-buffer buf))))

;;;;; pangram--handle-response

(ert-deftest pangram-test-handle-response-applies-overlays ()
  "Apply overlays to the source buffer from a well-formed response."
  (let ((buf (generate-new-buffer " *pangram-test-source*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (insert (make-string 20 ?x)))
          (pangram--handle-response
           (pangram-test--sample-response) buf 1)
          (with-current-buffer buf
            (let ((ovs (seq-filter
                        (lambda (ov) (overlay-get ov 'pangram))
                        (overlays-in (point-min) (point-max)))))
              (should (= (length ovs) 1))
              (let ((ov (car ovs)))
                (should (eq (overlay-get ov 'face) 'pangram-ai))))))
      (kill-buffer buf))))

(ert-deftest pangram-test-handle-response-dead-buffer ()
  "Handle a killed source buffer gracefully without error."
  (let ((buf (generate-new-buffer " *pangram-test-dead*")))
    (kill-buffer buf)
    (pangram--handle-response
     (pangram-test--sample-response) buf 1)))

(ert-deftest pangram-test-handle-response-no-windows ()
  "Handle a response with no windows field without error."
  (let ((buf (generate-new-buffer " *pangram-test-source*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (insert "some text"))
          (pangram--handle-response
           '((headline . "Clean") (fraction_ai . 0)
             (fraction_ai_assisted . 0) (fraction_human . 1.0))
           buf 1)
          (with-current-buffer buf
            (let ((ovs (seq-filter
                        (lambda (ov) (overlay-get ov 'pangram))
                        (overlays-in (point-min) (point-max)))))
              (should (= (length ovs) 0)))))
      (kill-buffer buf))))

;;;;; pangram--make-overlay

(ert-deftest pangram-test-make-overlay-properties ()
  "Create an overlay with correct face and help-echo."
  (let ((buf (generate-new-buffer " *pangram-test-ov*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (make-string 20 ?y))
          (let ((window '((label . "AI Generated")
                          (start_index . 0) (end_index . 5)
                          (ai_assistance_score . 0.9)
                          (confidence . "high"))))
            (pangram--make-overlay window 1 'pangram-ai)
            (let ((ovs (seq-filter
                        (lambda (ov) (overlay-get ov 'pangram))
                        (overlays-in (point-min) (point-max)))))
              (should (= (length ovs) 1))
              (let ((ov (car ovs)))
                (should (eq (overlay-get ov 'face) 'pangram-ai))
                (should (string-match-p "AI Generated"
                                        (overlay-get ov 'help-echo)))
                (should (string-match-p "0\\.90"
                                        (overlay-get ov 'help-echo)))))))
      (kill-buffer buf))))

;;;;; pangram--apply-overlays

(ert-deftest pangram-test-apply-overlays-skips-human ()
  "Skip human-labeled windows when applying overlays."
  (let ((buf (generate-new-buffer " *pangram-test-apply*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (make-string 30 ?z))
          (let ((windows [((label . "Human")
                           (start_index . 0) (end_index . 10)
                           (ai_assistance_score . 0.01)
                           (confidence . "high"))
                          ((label . "AI Generated")
                           (start_index . 10) (end_index . 20)
                           (ai_assistance_score . 0.95)
                           (confidence . "high"))]))
            (pangram--apply-overlays windows 1)
            (let ((ovs (seq-filter
                        (lambda (ov) (overlay-get ov 'pangram))
                        (overlays-in (point-min) (point-max)))))
              (should (= (length ovs) 1)))))
      (kill-buffer buf))))

;;;;; pangram-clear

(ert-deftest pangram-test-clear-removes-overlays ()
  "Remove all pangram overlays from the buffer."
  (let ((buf (generate-new-buffer " *pangram-test-clear*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (make-string 10 ?a))
          (let ((ov (make-overlay 1 5)))
            (overlay-put ov 'pangram t)
            (overlay-put ov 'face 'pangram-ai))
          (should (= (length (seq-filter
                              (lambda (ov) (overlay-get ov 'pangram))
                              (overlays-in (point-min) (point-max))))
                     1))
          (pangram-clear)
          (should (= (length (seq-filter
                              (lambda (ov) (overlay-get ov 'pangram))
                              (overlays-in (point-min) (point-max))))
                     0)))
      (kill-buffer buf))))

;;;;; pangram-detect

(ert-deftest pangram-test-detect-empty-text ()
  "Signal a user-error when the buffer text is empty or whitespace."
  (let ((buf (generate-new-buffer " *pangram-test-empty*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "   \n\t  ")
          (should-error (pangram-detect) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest pangram-test-detect-calls-api ()
  "Verify that `pangram-detect' sends text to the API callback."
  (let ((captured-text nil)
        (buf (generate-new-buffer " *pangram-test-detect*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Test content for detection")
          (cl-letf (((symbol-function 'pangram--get-api-key)
                     (lambda () "fake-key"))
                    ((symbol-function 'pangram--api-call)
                     (lambda (text _callback)
                       (setq captured-text text))))
            (pangram-detect)
            (should (equal captured-text "Test content for detection"))))
      (kill-buffer buf))))

;;;;; pangram--api-call (mocked url-retrieve)

(ert-deftest pangram-test-api-call-success ()
  "Invoke CALLBACK with parsed JSON on a successful API response."
  (let ((result nil))
    (cl-letf (((symbol-function 'pangram--get-api-key)
               (lambda () "test-key"))
              ((symbol-function 'url-retrieve)
               (lambda (_url callback cbargs &rest _)
                 (let ((resp-buf (pangram-test--make-http-buffer
                                  "HTTP/1.1 200 OK"
                                  "Content-Type: application/json"
                                  "{\"headline\":\"Clean\"}")))
                   (with-current-buffer resp-buf
                     (apply callback nil cbargs))))))
      (pangram--api-call "some text"
                         (lambda (data) (setq result data)))
      (should (equal (alist-get 'headline result) "Clean")))))

(ert-deftest pangram-test-api-call-http-error ()
  "Display an error message when the API returns a non-2xx status."
  (let ((msg nil))
    (cl-letf (((symbol-function 'pangram--get-api-key)
               (lambda () "test-key"))
              ((symbol-function 'url-retrieve)
               (lambda (_url callback cbargs &rest _)
                 (let ((resp-buf (pangram-test--make-http-buffer
                                  "HTTP/1.1 403 Forbidden"
                                  "Content-Type: text/plain"
                                  "Unauthorized")))
                   (with-current-buffer resp-buf
                     (apply callback nil cbargs)))))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq msg (apply #'format fmt args)))))
      (pangram--api-call "text" #'ignore)
      (should (string-match-p "403" msg)))))

(ert-deftest pangram-test-api-call-network-error ()
  "Display an error message when url-retrieve reports a status error."
  (let ((msg nil))
    (cl-letf (((symbol-function 'pangram--get-api-key)
               (lambda () "test-key"))
              ((symbol-function 'url-retrieve)
               (lambda (_url callback cbargs &rest _)
                 (let ((buf (generate-new-buffer " *pangram-test*")))
                   (with-current-buffer buf
                     (apply callback
                            (list :error '(error connection-failed))
                            cbargs)))))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq msg (apply #'format fmt args)))))
      (pangram--api-call "text" #'ignore)
      (should (string-match-p "error" msg)))))

(provide 'pangram-test)

;;; pangram-test.el ends here
