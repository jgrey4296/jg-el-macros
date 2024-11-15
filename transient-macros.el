;;; transient.el -*- lexical-binding: t; -*-
(eval-when-compile
  (require 'cl-lib)
  (require 'transient)
  )

(defconst fmt-as-bool-pair '("T" . "F"))

(defvar transient-quit!
  [
   ""
   [("q" "Quit Local" transient-quit-one)]
   [("Q" "Quit Global" transient-quit-all)]
   [("|" "Quit" transient-quit-all)]
   ]
  " Reusable simple quit for transients "
  )

(defclass transient-macro--group (transient-prefix)
  ((description :initarg :description :initform nil))
  "Prefix Subclassed to hold a description"
  )


(cl-defmethod transient-format-description :before ((obj transient-macro--group))
  "Format the description by calling the next method.  If the result
is nil, then use \"(BUG: no description)\" as the description.
If the OBJ's `key' is currently unreachable, then apply the face
`transient-unreachable' to the complete string."
  (or (funcall (oref obj description))
      (propertize "(JG BUG: no description)" 'face 'error))
)

;;;###autoload
(defun transient-title-mode-formatter (name mode key)
  (format "%s%s : %s"
          (make-string (max 0 (- 3 (length key))) 32)
          (fmt-as-bool! mode)
          name
          )
  )

;;;###autoload
(defun transient-title-var-formatter (name val key)
  (format "%s%s : %s"
          (make-string (max 0 (- 3 (length key))) 32)
          (fmt-as-bool! val)
          name
          )
  )


;;;###autoload
(defun fmt-as-bool! (arg)
  " pass in a value, convert it to one of the values in `fmt-as-bool-pair` "
  (if arg (car fmt-as-bool-pair) (cdr fmt-as-bool-pair))
  )

;;;###autoload
(defun transient-args! ()
  " utility for easily getting all current transient args "
      (transient-args transient-current-command)
  )

;;;###autoload
(defun transient-args? (&optional key)
  "utility for easily testing the args in transient"
  (member (if (symbolp key) (symbol-name key) key) (transient-args transient-current-command))
  )

;;;###autoload
(defun transient-init! (arg)
  " utility for simply setting a transient init value "
  (-partial #'(lambda (val obj)
                (oset obj value val))
            arg)
  )

;;;###autoload
(defmacro transient-make-mode-toggle! (mode &optional desc key heading mode-var)
  " Macro to define a transient suffix for toggling a mode easier "
  (let* ((fullname (intern (format "transient-macro-toggle-%s" (symbol-name mode))))
         (name (let ((str (or desc (symbol-name mode))))
                 (when heading
                   (put-text-property 0 (length str) 'face 'transient-heading str))
                 str))
        (desc-fn `(lambda () (transient-title-mode-formatter ,name ,(or mode-var mode) ,key)))
        )
    `(progn
       (defvar ,(or mode-var mode) nil)
       (transient-define-suffix ,fullname ()
               :transient t
               ,@(when key (list :key key))
               :description ,desc-fn
               (interactive)
               (,mode 'toggle)
               )
       (quote ,fullname)
       )
     )
  )

;;;###autoload
(defmacro transient-make-var-toggle! (name var &optional desc key)
  " Macro to define a transient suffix for toggling a bool variable "
  (let* ((fullname (intern (format "transient-macro-toggle-%s" (symbol-name name))))
         (desc-fn `(lambda () (transient-title-var-formatter ,(or desc (symbol-name name)) ,var ,key)))
         )
    `(progn
       (defvar ,var nil)
       (transient-define-suffix ,fullname ()
         :transient t
         :description ,desc-fn
         ,@(when key (list :key key))
         (interactive)
         (setq ,var (not ,var))
         )
       (quote ,fullname)
       )
    )
)

;;;###autoload
(cl-defmacro transient-make-call! (name key fmt &body body)
  " create a transient suffix of `name`
with a string or format call, which executes the body
 "
  (let ((fullname (intern (format "transient-macro-call-%s" (if (stringp name) name
                                                           (symbol-name name)))))
        (transient (if (plist-member body :transient) (plist-get body :transient) t))
        (no-curr-buff (if (plist-member body :no-curr) (plist-get body :no-curr) nil))
        )
    (while (keywordp (car body))
      (pop body) (pop body))
    `(progn
       (transient-define-suffix ,fullname ()
         :transient ,transient
         ,@(when key (list :key key))
         :description (lambda () ,fmt)
         (interactive)
         ,@(if no-curr-buff
               body
             `((with-current-buffer (or transient--original-buffer (current-buffer))
                ,@body
                )))
         )
       (quote ,fullname)
       )
    )
  )

;;;###autoload
(cl-defmacro transient-make-int-call! (name key fmt &body body)
  " create a transient suffix of `name`
with a string or format call, interactively calls the fn symbol in body
 "
  (let ((fullname (intern (format "transient-macro-call-%s" (if (stringp name) name
                                                           (symbol-name name)))))
        (transient (if (plist-member body :transient) (plist-get body :transient) t))
        )
    (while (keywordp (car body))
      (pop body) (pop body))
    `(progn
       (transient-define-suffix ,fullname ()
         :transient ,transient
         ,@(when key (list :key key))
         :description (lambda () ,fmt)
         (interactive)
         (with-current-buffer (or transient--original-buffer (current-buffer))
           (call-interactively ,@body)
           )
         )
       (quote ,fullname)
       )
    )
  )

;;;###autoload
(cl-defmacro transient-make-subgroup! (name bind docstring &body body &key (desc nil) &allow-other-keys)
  " Make prefix subgroup bound to const `name`, as the triple (keybind descr prefix-call),
which can then be included in other transient-prefixes as just `name`
with text properties to mark it so
'
 "
  (let ((prefix (gensym))
        (docfn (gensym))
        (doc (pcase (or desc (symbol-name name))
               ((and str (pred stringp))
                (put-text-property 0 (length str) 'face 'transient-heading str)
                str)
               ((and fn (pred functionp))
                `(let ((result (funcall ,fn)))
                   (put-text-property 0 (length result) 'face 'transient-heading result)
                   result
                   ))
               ))
        )
    (when (keywordp (car body))
      (pop body) (pop body)
      )
    `(progn
       (transient-define-prefix ,prefix ()
         ,docstring
         ,@body
         transient-quit!
         )
       (defun ,docfn nil ,doc)
       (defconst ,name (list ,bind  (quote ,docfn) (quote ,prefix)))
       (quote ,name)
       )
    )
  )

(provide 'transient-macros)
