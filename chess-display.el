;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Code shared by all chess displays
;;
;; $Revision$

;;; Code:

(require 'chess-game)
(require 'chess-var)
(require 'chess-algebraic)
(require 'chess-fen)

(defgroup chess-display nil
  "Common code used by chess displays."
  :group 'chess)

(defcustom chess-display-use-faces t
  "If non-nil, provide colored faces for ASCII displays."
  :type 'boolean
  :group 'chess-display)

(defface chess-display-black-face
  '((((class color) (background light)) (:foreground "Green"))
    (((class color) (background dark)) (:foreground "Green"))
    (t (:bold t)))
  "*The face used for black pieces on the ASCII display."
  :group 'chess-display)

(defface chess-display-white-face
  '((((class color) (background light)) (:foreground "Yellow"))
    (((class color) (background dark)) (:foreground "Yellow"))
    (t (:bold t)))
  "*The face used for white pieces on the ASCII display."
  :group 'chess-display)

(defface chess-display-highlight-face
  '((((class color) (background light)) (:background "#add8e6"))
    (((class color) (background dark)) (:background "#add8e6")))
  "Face to use for highlighting pieces that have been selected."
  :group 'chess-display)

;;; Code:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; User interface
;;

(defvar chess-display-style)
(defvar chess-display-game)
(defvar chess-display-variation)
(defvar chess-display-index)
(defvar chess-display-ply)
(defvar chess-display-position)
(defvar chess-display-perspective)
(defvar chess-display-main-p nil)
(defvar chess-display-event-handler nil)
(defvar chess-display-no-popup nil)
(defvar chess-display-edit-mode nil)
(defvar chess-display-mode-line "")

(make-variable-buffer-local 'chess-display-style)
(make-variable-buffer-local 'chess-display-game)
(make-variable-buffer-local 'chess-display-variation)
(make-variable-buffer-local 'chess-display-index)
(make-variable-buffer-local 'chess-display-ply)
(make-variable-buffer-local 'chess-display-position)
(make-variable-buffer-local 'chess-display-perspective)
(make-variable-buffer-local 'chess-display-main-p)
(make-variable-buffer-local 'chess-display-event-handler)
(make-variable-buffer-local 'chess-display-no-popup)
(make-variable-buffer-local 'chess-display-edit-mode)
(make-variable-buffer-local 'chess-display-mode-line)

(defmacro chess-with-current-buffer (buffer &rest body)
  `(let ((buf ,buffer))
     (if buf
	 (with-current-buffer buf
	   ,@body)
       ,@body)))

(defun chess-display-create (style perspective)
  "Create a chess display, for displaying chess objects."
  (let* ((name (symbol-name style))
	 (handler (intern-soft (concat name "-handler"))))
    (unless handler
      (error "There is no such chessboard display style '%s'" name))
    (with-current-buffer (generate-new-buffer "*Chessboard*")
      (chess-display-mode)
      (funcall handler 'initialize)
      (setq chess-display-style style
	    chess-display-perspective perspective
	    chess-display-event-handler handler)
      (add-hook 'kill-buffer-hook 'chess-display-quit nil t)
      (current-buffer))))

(defun chess-display-clone (display style perspective)
  (let ((new-display (chess-display-create style perspective)))
    (with-current-buffer display
      (cond
       (chess-display-game
	(chess-display-set-game new-display chess-display-game))
       (chess-display-variation
	(chess-display-set-variation new-display chess-display-variation))
       (chess-display-ply
	(chess-display-set-ply new-display chess-display-ply))
       (chess-display-position
	(chess-display-set-game new-display chess-display-position))))
    ;; the display will have already been updated by the `set-' calls,
    ;; it's just not visible yet
    (chess-display-popup new-display)
    new-display))

(defsubst chess-display-style (display)
  (chess-with-current-buffer display
    chess-display-style))

(defsubst chess-display-perspective (display)
  (chess-with-current-buffer display
    chess-display-perspective))

(defun chess-display-set-perspective* (display perspective)
  (chess-with-current-buffer display
    (setq chess-display-perspective perspective)
    (erase-buffer)))			; force a complete redraw

(defun chess-display-set-perspective (display perspective)
  (chess-with-current-buffer display
    (chess-display-set-perspective* nil perspective)
    (chess-display-update nil)))

(defsubst chess-display-main-p (display)
  (chess-with-current-buffer display
    chess-display-main-p))

(defun chess-display-set-main (display)
  (chess-with-current-buffer display
    (setq chess-display-main-p t)))

(defun chess-display-clear-main (display)
  (chess-with-current-buffer display
    (setq chess-display-main-p nil)))


(defun chess-display-set-position (display position &optional search-func)
  "Set the display position.
Note that when a single position is being displayed, out of context of
a game, the user's move will cause a new variation to be created,
without a game object.
If the position is merely edited, it will change the POSITION object
that was passed in."
  (chess-with-current-buffer display
    (if chess-display-game
	(chess-display-detach-game nil))
    (setq chess-display-game nil
	  chess-display-variation nil
	  chess-display-index nil
	  chess-display-ply nil
	  chess-display-position position)
    (chess-display-update nil t)))

(defun chess-display-position (display)
  "Return the position currently viewed."
  (chess-with-current-buffer display
    (or (and chess-display-game
	     (chess-game-pos chess-display-game chess-display-index))
	(and chess-display-variation
	     (chess-var-pos chess-display-variation chess-display-index))
	(and chess-display-ply
	     (chess-ply-next-pos chess-display-ply))
	chess-display-position)))

(defun chess-display-set-ply (display ply)
  "Set the display ply.
This differs from a position display, only in that the algebraic form
of the move made to the reach the displayed position will be shown in
the modeline."
  (chess-with-current-buffer display
    (if chess-display-game
	(chess-display-detach-game nil))
    (setq chess-display-game nil
	  chess-display-variation nil
	  chess-display-index nil
	  chess-display-ply ply
	  chess-display-position nil)
    (chess-display-update display t)))

(defun chess-display-ply (display)
  (chess-with-current-buffer display
    (or (and chess-display-game
	     (chess-game-ply chess-display-game chess-display-index))
	(and chess-display-variation
	     (chess-var-ply chess-display-variation chess-display-index))
	chess-display-ply)))

(defun chess-display-set-variation (display variation &optional index)
  "Set the display variation.
This will cause the first ply in the variation to be displayed, with
the user able to scroll back and forth through the moves in the
variation.  Any moves made on the board will extend/change the
variation that was passed in."
  (chess-with-current-buffer display
    (if chess-display-game
	(chess-display-detach-game nil))
    (setq chess-display-game nil
	  chess-display-variation variation
	  chess-display-index (chess-var-index variation)
	  chess-display-ply nil
	  chess-display-position nil)
    (chess-display-update nil t)))

(defun chess-display-variation (display)
  (chess-with-current-buffer display
    (or (and chess-display-game
	     (chess-game-main-var chess-display-game))
	chess-display-variation)))

(defun chess-display-set-game (display game &optional index)
  "Set the display game.
This will cause the first ply in the game's main variation to be
displayed.  Also, information about the game is shown in the
modeline."
  (chess-with-current-buffer display
    (if chess-display-game
	(chess-display-detach-game nil))
    (setq chess-display-game game
	  chess-display-variation nil
	  chess-display-index (chess-game-index game)
	  chess-display-ply nil
	  chess-display-position nil)
    (if game
	(chess-game-add-hook game 'chess-display-event-handler display))
    (chess-display-update nil t)))

(defun chess-display-copy-game (display game)
  (chess-with-current-buffer display
    (setq chess-display-index (chess-game-index game))
    (if (null chess-display-game)
	(chess-display-set-game nil game)
      (chess-game-set-tags chess-display-game (chess-game-tags game))
      ;; this call triggers `setup-game' for us
      (chess-game-set-plies chess-display-game
			    (chess-game-plies game)))))

(defun chess-display-set-start-position (display &optional position my-color)
  (chess-with-current-buffer display
    (let ((game (chess-display-game nil)))
      (if (null game)
	  (chess-display-set-position nil (or position
					      chess-starting-position))
	(if position
	    (progn
	      (chess-game-set-start-position game position)
	      (chess-game-set-data game 'my-color my-color))
	  (chess-game-set-start-position game chess-starting-position)
	  (chess-game-set-data game 'my-color t))))))

(defun chess-display-detach-game (display)
  "Set the display game.
This will cause the first ply in the game's main variation to be
displayed.  Also, information about the game is shown in the
modeline."
  (chess-with-current-buffer display
    (if chess-display-game
	(chess-game-remove-hook chess-display-game
				'chess-display-event-handler
				(or display (current-buffer))))))

(defsubst chess-display-game (display)
  (chess-with-current-buffer display
    chess-display-game))

(defun chess-display-set-index* (display index)
  (chess-with-current-buffer display
    (unless chess-display-index
      (error "There is no game or variation currently being displayed."))
    (unless (or (not (integerp index))
		(< index 0)
		(> index (if chess-display-game
			     (chess-game-index chess-display-game)
			   (chess-var-index chess-display-variation))))
      (setq chess-display-index index))))

(defun chess-display-set-index (display index)
  (chess-with-current-buffer display
    (chess-display-set-index* nil index)
    (chess-display-update nil)))

(defsubst chess-display-index (display)
  (chess-with-current-buffer display
    chess-display-index))

(defun chess-display-update (display &optional popup)
  "Update the chessboard DISPLAY.  POPUP too, if that arg is non-nil."
  (chess-with-current-buffer display
    (funcall chess-display-event-handler 'draw
	     (chess-display-position nil)
	     (chess-display-perspective nil))
    (chess-display-set-modeline)
    (if (and popup (not chess-display-no-popup)
	     (chess-display-main-p nil))
	(chess-display-popup nil))))

(defun chess-display-move (display ply)
  "Move a piece on DISPLAY, by applying the given PLY.
The position of PLY must match the currently displayed position.
If only START is given, it must be in algebraic move notation."
  (chess-with-current-buffer display
    (cond
     (chess-display-game
      ;; jww (2002-03-28): This should beget a variation within the
      ;; game, or alter the game, just as SCID allows
      (if (= (chess-display-index nil)
	     (chess-game-index chess-display-game))
	  (chess-game-move chess-display-game ply)
	(error "What to do here??  NYI")))
     (chess-display-variation
      (chess-var-move chess-display-variation ply)
      (chess-display-set-index* nil (chess-var-index
				     chess-display-variation)))
     (chess-display-ply
      (setq chess-display-ply ply))
     (chess-display-position		; an ordinary position
      (setq chess-display-position (chess-ply-next-pos ply))))
    (chess-display-update nil)))

(defun chess-display-highlight (display &rest args)
  "Highlight the square at INDEX on the current position.
The given highlighting MODE is used, or the default if the style you
are displaying with doesn't support that mode.  `selected' is a mode
that is supported by most displays, and is the default mode."
  (chess-with-current-buffer display
    (let ((mode :selected))
      (dolist (arg args)
	(if (symbolp arg)
	    (setq mode arg)
	  (funcall chess-display-event-handler
		   'highlight arg mode))))))

(defun chess-display-popup (display)
  "Popup the given DISPLAY, so that it's visible to the user."
  (chess-with-current-buffer display
    (funcall chess-display-event-handler 'popup)))

(defun chess-display-enable-popup (display)
  "Popup the given DISPLAY, so that it's visible to the user."
  (chess-with-current-buffer display
    (setq chess-display-no-popup nil)))

(defun chess-display-disable-popup (display)
  "Popup the given DISPLAY, so that it's visible to the user."
  (chess-with-current-buffer display
    (setq chess-display-no-popup t)))

(defun chess-display-destroy (display)
  "Destroy a chess display object, killing all of its buffers."
  (let ((buf (or display (current-buffer))))
    (when (buffer-live-p buf)
      (chess-display-event-handler (chess-display-game nil)
				   buf 'destroy)
      (with-current-buffer buf
	(remove-hook 'kill-buffer-hook 'chess-display-quit t))
      (kill-buffer buf))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Event handler
;;

(defcustom chess-display-momentous-events
  '(orient setup-game pass move game-over resign)
  "Events that will cause the 'main' display to popup."
  :type '(repeat symbol)
  :group 'chess-display)

(defcustom chess-display-boring-events
  '(set-data set-tags set-tag draw abort undo shutdown)
  "Events which will not even cause a refresh of the display."
  :type '(repeat symbol)
  :group 'chess-display)

(defun chess-display-event-handler (game display event &rest args)
  "This display module presents a standard chessboard.
See `chess-display-type' for the different kinds of displays."
  (unless (memq event chess-display-boring-events)
    (with-current-buffer display
      (cond
       ((eq event 'shutdown)
	(chess-display-destroy nil))

       ((eq event 'destroy)
	(chess-display-detach-game nil))

       ((eq event 'pass)
	(let ((my-color (chess-game-data game 'my-color)))
	  (chess-game-set-data game 'my-color (not my-color))
	  (chess-display-set-perspective* nil (not my-color))))

       ((eq event 'orient)
	;; Set the display's perspective to whichever color I'm
	;; playing; also set the index just to be sure
	(chess-display-set-index* nil (chess-game-index game))
	(chess-display-set-perspective*
	 nil (chess-game-data game 'my-color))))

      (if (memq event '(orient setup-game move game-over resign))
	  (chess-display-set-index* nil (chess-game-index game)))

      (unless (eq event 'shutdown)
	(chess-display-update
	 nil (memq event chess-display-momentous-events))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; chess-display-mode
;;

(defvar chess-display-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map)
    (set-keymap-parent map nil)

    (define-key map [(control ?i)] 'chess-display-invert)
    (define-key map [tab] 'chess-display-invert)

    (define-key map [? ] 'chess-display-pass)
    (define-key map [??] 'describe-mode)
    (define-key map [?@] 'chess-display-remote)
    (define-key map [?A] 'chess-display-abort)
    (define-key map [?B] 'chess-display-list-buffers)
    (define-key map [?C] 'chess-display-duplicate)
    (define-key map [?D] 'chess-display-draw)
    (define-key map [?E] 'chess-display-edit-board)
    (define-key map [?F] 'chess-display-set-from-fen)
    (define-key map [?I] 'chess-display-invert)
    ;;(define-key map [?M] 'chess-display-manual-move)
    (define-key map [?M] 'chess-display-match)
    (define-key map [?N] 'chess-display-abort)
    (define-key map [?R] 'chess-display-resign)
    (define-key map [?S] 'chess-display-shuffle)
    (define-key map [?U] 'chess-display-undo)
    (define-key map [?X] 'chess-display-quit)

    (define-key map [?<] 'chess-display-move-first)
    (define-key map [?,] 'chess-display-move-backward)
    (define-key map [(meta ?<)] 'chess-display-move-first)
    (define-key map [?>] 'chess-display-move-last)
    (define-key map [?.] 'chess-display-move-forward)
    (define-key map [(meta ?>)] 'chess-display-move-last)

    (define-key map [(meta ?w)] 'chess-display-kill-board)
    (define-key map [(control ?y)] 'chess-display-yank-board)

    (define-key map [(control ?l)] 'chess-display-redraw)

    (dolist (key '(?a ?b ?c ?d ?e ?f ?g ?h
		      ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8
		      ?r ?n ?b ?q ?k ?o))
      (define-key map (vector key) 'chess-keyboard-shortcut))
    (define-key map [backspace] 'chess-keyboard-shortcut-delete)
    (define-key map [?x] 'ignore)

    (define-key map [(control ?m)] 'chess-display-select-piece)
    (define-key map [return] 'chess-display-select-piece)
    (cond
     ((featurep 'xemacs)
      (define-key map [(button1)] 'chess-display-mouse-select-piece)
      (define-key map [(button2)] 'chess-display-mouse-select-piece))
     (t
      (define-key map [mouse-1] 'chess-display-mouse-select-piece)
      (define-key map [mouse-2] 'chess-display-mouse-select-piece)))

    (define-key map [menu-bar files] 'undefined)
    (define-key map [menu-bar edit] 'undefined)
    (define-key map [menu-bar options] 'undefined)
    (define-key map [menu-bar buffer] 'undefined)
    (define-key map [menu-bar tools] 'undefined)
    (define-key map [menu-bar help-menu] 'undefined)

    map)
  "The mode map used in a chessboard display buffer.")

(defvar chess-display-move-menu nil)
(unless chess-display-move-menu
  (easy-menu-define
    chess-display-move-menu chess-display-mode-map ""
    '("History"
      ["First" chess-display-move-first t]
      ["Previous" chess-display-move-backward t]
      ["Next" chess-display-move-forward t]
      ["Last" chess-display-move-last t])))

(defun chess-display-redraw ()
  "Just redraw the current display."
  (interactive)
  (erase-buffer)
  (chess-display-update nil))

(defun chess-display-mode ()
  "A mode for displaying and interacting with a chessboard.
The key bindings available in this mode are:
\\{chess-display-mode-map}"
  (interactive)
  (setq major-mode 'chess-display-mode mode-name "Chessboard")
  (use-local-map chess-display-mode-map)
  (buffer-disable-undo)
  (setq buffer-auto-save-file-name nil
	mode-line-format 'chess-display-mode-line))

(defun chess-display-set-modeline ()
  "Set the modeline to reflect the current game position."
  (let ((color (chess-pos-side-to-move (chess-display-position nil)))
	(index (chess-display-index nil))
	ply)
    (if (null index)
	(setq chess-display-mode-line
	      (if color "  White to move" "  Black to move"))
      (if (and index (= index 0))
	  (setq chess-display-mode-line
		(format "   %s   START" (if color "White" "Black")))
	(cond
	 (chess-display-ply
	  (setq ply chess-display-ply))
	 (chess-display-game
	  (setq ply (chess-game-ply chess-display-game (1- index))))
	 (chess-display-variation
	  (setq ply (chess-var-ply chess-display-variation (1- index)))))
	(if ply
	    (setq chess-display-mode-line
		  (concat
		   (let ((final (chess-ply-final-p ply)))
		     (cond
		      ((eq final :checkmate)
		       "  CHECKMATE")
		      ((eq final :resign)
		       "  RESIGNED")
		      ((eq final :stalemate)
		       "  STALEMATE")
		      ((eq final :draw)
		       "  DRAWN")
		      (t
		       (concat "  " (if color "White" "Black")))))
		   (if index
		       (concat "   " (int-to-string
				      (if (> index 1)
					  (/ index 2) (1+ (/ index 2))))))
		   (if ply
		       (concat ". " (if color "... ")
			       (or (chess-ply-to-algebraic ply)
				   "???"))))))))))

(defsubst chess-display-active-p ()
  "Return non-nil if the displayed chessboard reflects an active game.
Basically, it means we are playing, not editing or reviewing."
  (and chess-display-game
       (= (chess-display-index nil)
	  (chess-game-index chess-display-game))
       (not (chess-game-over-p chess-display-game))
       (not chess-display-edit-mode)))

(defun chess-display-invert ()
  "Invert the perspective of the current chess board."
  (interactive)
  (chess-display-set-perspective nil (not (chess-display-perspective nil))))

(defun chess-display-set-from-fen (fen)
  "Send the current board configuration to the user."
  (interactive "sSet from FEN string: ")
  (chess-display-set-position nil (chess-fen-to-pos fen)))

(defun chess-display-kill-board (&optional arg)
  "Send the current board configuration to the user."
  (interactive "P")
  (let ((x-select-enable-clipboard t))
    (if (and arg chess-display-game)
	(kill-new (with-temp-buffer
		    (chess-game-to-pgn (chess-display-game nil))
		    (buffer-string)))
      (kill-new (chess-pos-to-fen (chess-display-position nil))))))

(defun chess-display-yank-board ()
  "Send the current board configuration to the user."
  (interactive)
  (let ((x-select-enable-clipboard t)
	(display (current-buffer))
	(text (current-kill 0)))
    (with-temp-buffer
      (insert text)
      (goto-char (point-max))
      (while (and (bolp) (not (bobp)))
	(delete-backward-char 1))
      (goto-char (point-min))
      (cond
       ((search-forward "[Event" nil t)
	(goto-char (match-beginning 0))
	(chess-display-copy-game display (chess-pgn-to-game)))
       ((looking-at (concat chess-algebraic-regexp "$"))
	(let ((move (buffer-string)))
	  (with-current-buffer display
	    (chess-display-manual-move move))))
       (t
	(with-current-buffer display
	  (chess-display-set-from-fen (buffer-string))))))))

(defun chess-display-set-piece ()
  "Set the piece under point to command character, or space for clear."
  (interactive)
  (unless (chess-display-active-p)
    (chess-pos-set-piece (chess-display-position nil)
			 (get-text-property (point) 'chess-coord)
			 last-command-char)
    (chess-display-update nil)))

(defun chess-display-quit ()
  "Quit the current game."
  (interactive)
  (if (and chess-display-main-p
	   chess-display-game)
      (chess-game-run-hooks chess-display-game 'shutdown)
    (chess-display-destroy nil)))

(defun chess-display-manual-move (move)
  "Move a piece manually, using chess notation."
  (interactive
   (list (read-string
	  (format "%s(%d): "
		  (if (chess-pos-side-to-move (chess-display-position nil))
		      "White" "Black")
		  (1+ (/ (or (chess-display-index nil) 0) 2))))))
  (let ((ply (chess-algebraic-to-ply (chess-display-position nil) move)))
    (unless ply
      (error "Illegal move notation: %s" move))
    (chess-display-move nil ply)))

(defun chess-display-remote (display)
  (interactive "sDisplay this game on X server: ")
  (require 'chess-images)
  (let ((chess-images-separate-frame display))
    (chess-display-clone (current-buffer) 'chess-images
			 (chess-display-perspective nil))))

(defun chess-display-duplicate (style)
  (interactive
   (list (concat "chess-"
		 (read-from-minibuffer
		  "Create new display using style: "
		  (substring (symbol-name (chess-display-style nil))
			     0 (length "chess-"))))))
  (chess-display-clone (current-buffer) (intern-soft style)
		       (chess-display-perspective nil)))

(defun chess-display-pass ()
  "Pass the move to your opponent.  Only valid on the first move."
  (interactive)
  (if (and (chess-display-active-p)
	   (= 0 (chess-display-index nil)))
      (chess-game-run-hooks chess-display-game 'pass)
    (ding)))

(defun chess-display-shuffle ()
  "Generate a shuffled opening position."
  (interactive)
  (require 'chess-random)
  (if (and (chess-display-active-p)
	   (= 0 (chess-display-index nil)))
      (chess-game-set-start-position chess-display-game
				     (chess-fischer-random-position))
    (ding)))

(defun chess-display-match (whom)
  "Resign the current game."
  (interactive "sWhom do you wish to play? ")
  (chess-game-run-hooks chess-display-game 'match whom))

(defun chess-display-resign ()
  "Resign the current game."
  (interactive)
  (if (chess-display-active-p)
      (progn
	(chess-game-end (chess-display-game nil) :resign)
	(chess-game-run-hooks chess-display-game 'resign))
    (ding)))

(defun chess-display-abort ()
  "Abort the current game."
  (interactive)
  (if (chess-display-active-p)
      (chess-game-run-hooks chess-display-game 'abort)
    (ding)))

(defun chess-display-draw ()
  "Offer to draw the current game."
  (interactive)
  (if (chess-display-active-p)
      (progn
	(message "You offer a draw")
	(chess-game-run-hooks chess-display-game 'draw))
    (ding)))

(defun chess-display-undo (count)
  "Abort the current game."
  (interactive "P")
  (if (chess-display-active-p)
      (progn
	;; we can't call `chess-game-undo' directly, because not all
	;; engines will accept it right away!  So we just signal the
	;; desire to undo
	(setq count
	      (if count
		  (prefix-numeric-value count)
		(if (eq (chess-pos-side-to-move
			 (chess-display-position nil))
			(chess-game-data chess-display-game 'my-color))
		    2 1)))
	(chess-game-run-hooks chess-display-game 'undo count))
    (ding)))

(defun chess-display-list-buffers ()
  "List all buffers related to this display's current game."
  (interactive)
  (when chess-display-game
    (let ((buffer-list-func (symbol-function 'buffer-list)))
      (unwind-protect
	  (let ((chess-game chess-display-game)
		(lb-command (lookup-key ctl-x-map [(control ?b)]))
		(ibuffer-maybe-show-regexps nil))
	    (fset 'buffer-list
		  (function
		   (lambda ()
		     (delq nil
			   (mapcar (function
				    (lambda (cell)
				      (and (bufferp (cdr cell))
					   (buffer-live-p (cdr cell))
					   (cdr cell))))
				   (chess-game-hooks chess-game))))))
	    (call-interactively lb-command))
	(fset 'buffer-list buffer-list-func)))))

(defun chess-display-set-current (dir)
  "Change the currently displayed board.
Direction may be - or +, to move forward or back, or t or nil to jump
to the end or beginning."
  (let ((index (cond ((eq dir ?-) (1- chess-display-index))
		     ((eq dir ?+) (1+ chess-display-index))
		     ((eq dir t) nil)
		     ((eq dir nil) 0))))
    (chess-display-set-index
     nil (or index
	     (if chess-display-game
		 (chess-game-index chess-display-game)
	       (chess-var-index chess-display-variation))))
    (unless (chess-display-active-p)
      (message "Use '>' to return to the current position"))))

(defun chess-display-move-backward ()
  (interactive)
  (if chess-display-index
      (chess-display-set-current ?-)))

(defun chess-display-move-forward ()
  (interactive)
  (if chess-display-index
      (chess-display-set-current ?+)))

(defun chess-display-move-first ()
  (interactive)
  (if chess-display-index
      (chess-display-set-current nil)))

(defun chess-display-move-last ()
  (interactive)
  (if chess-display-index
      (chess-display-set-current t)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; chess-display-edit-mode (for editing the position directly)
;;

(defvar chess-display-edit-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map)
    (set-keymap-parent map chess-display-mode-map)

    (define-key map [?C] 'chess-display-clear-board)
    (define-key map [?G] 'chess-display-restore-board)
    (define-key map [?S] 'chess-display-send-board)

    (let ((keys '(?  ?p ?r ?n ?b ?q ?k ?P ?R ?N ?B ?Q ?K)))
      (while keys
	(define-key map (vector (car keys)) 'chess-display-set-piece)
	(setq keys (cdr keys))))
    map)
  "The mode map used for editing a chessboard position.")

(defun chess-display-edit-board ()
  "Setup the current board for editing."
  (interactive)
  (setq chess-display-edit-mode t)
  ;; Take us out of any game/ply/variation we might be looking at,
  ;; since we are not moving pieces now, but rather placing them --
  ;; for which purpose the movement keys can still be used.
  (chess-display-set-position nil (chess-display-position nil))
  ;; jww (2002-03-28): setup edit-mode keymap here
  (message "Now editing position directly, use S when complete..."))

(defun chess-display-send-board ()
  "Send the current board configuration to the user."
  (interactive)
  (if chess-display-game
      (chess-game-set-start-position chess-display-game
				     (chess-display-position nil)))
  (setq chess-display-edit-mode nil))

(defun chess-display-restore-board ()
  "Setup the current board for editing."
  (interactive)
  ;; jww (2002-03-28): NYI
  (setq chess-display-edit-mode nil)
  (chess-display-update nil))

(defun chess-display-clear-board ()
  "Setup the current board for editing."
  (interactive)
  (when (y-or-n-p "Really clear the chessboard? ")
    (let ((position (chess-display-position nil)))
      (dotimes (rank 8)
	(dotimes (file 8)
	  (chess-pos-set-piece position (cons rank file) ? ))))
    (chess-display-update nil)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Allow for quick entry of algebraic moves via keyboard
;;

(defvar chess-move-string "")
(defvar chess-legal-moves-pos nil)
(defvar chess-legal-moves nil)

(make-variable-buffer-local 'chess-move-string)
(make-variable-buffer-local 'chess-legal-moves-pos)
(make-variable-buffer-local 'chess-legal-moves)

(defun chess-keyboard-test-move (move)
  "Return the given MOVE if it matches the user's current input."
  (let ((i 0) (x 0)
	(l (length move))
	(xl (length chess-move-string))
	(match t))
    (unless (or (and (equal chess-move-string "ok")
		     (equal move "O-O"))
		(and (equal chess-move-string "oq")
		     (equal move "O-O-O")))
      (while (and (< i l) (< x xl))
	(if (= (aref move i) ?x)
	    (setq i (1+ i)))
	(if (/= (downcase (aref move i))
		(aref chess-move-string x))
	    (setq match nil i l)
	  (setq i (1+ i) x (1+ x)))))
    (if match move)))

(defsubst chess-keyboard-display-moves (&optional move-list)
  (if (> (length chess-move-string) 0)
      (message "[%s] %s" chess-move-string
	       (mapconcat 'identity
			  (or move-list
			      (delq nil (mapcar 'chess-keyboard-test-move
						chess-legal-moves))) " "))))

(defun chess-keyboard-shortcut-delete ()
  (interactive)
  (when (and chess-move-string
	     (stringp chess-move-string)
	     (> (length chess-move-string) 1))
    (setq chess-move-string
	  (substring chess-move-string 0
		     (1- (length chess-move-string))))
    (chess-keyboard-display-moves)))

(defun chess-keyboard-shortcut (&optional display-only)
  (interactive)
  (unless (memq last-command '(chess-keyboard-shortcut
			       chess-keyboard-shortcut-delete))
    (setq chess-move-string nil))
  (unless display-only
    (setq chess-move-string
	  (concat chess-move-string
		  (char-to-string (downcase last-command-char)))))
  (let ((position (chess-display-position nil)))
    (unless (and chess-legal-moves
		 (eq position chess-legal-moves-pos))
      (setq chess-legal-moves-pos position
	    chess-legal-moves
	    (sort (mapcar 'chess-ply-to-algebraic (chess-legal-plies position))
		  'string-lessp)))
    (let ((moves (delq nil (mapcar 'chess-keyboard-test-move
				   chess-legal-moves))))
      (cond
       ((= (length moves) 1)
	(chess-display-manual-move (car moves))
	(setq chess-move-string nil
	      chess-legal-moves nil
	      chess-legal-moves-pos nil))
       ((null moves)
	(chess-keyboard-shortcut-delete))
       (t
	(chess-keyboard-display-moves moves))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Manage a face cache for textual displays
;;

(defvar chess-display-face-cache '((t . t)))

(defsubst chess-display-get-face (color)
  (or (cdr (assoc color chess-display-face-cache))
      (let ((face (make-face 'chess-display-highlight)))
	(set-face-attribute face nil :background color)
	(add-to-list 'chess-display-face-cache (cons color face))
	face)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Default window and frame popup functions
;;

(defun chess-display-popup-in-window ()
  "Popup the given DISPLAY, so that it's visible to the user."
  (unless (get-buffer-window (current-buffer))
    (fit-window-to-buffer (display-buffer (current-buffer)))))

(defun chess-display-popup-in-frame (display height width)
  "Popup the given DISPLAY, so that it's visible to the user."
  (let ((window (get-buffer-window (current-buffer) t)))
    (if window
	(let ((frame (window-frame window)))
	  (unless (eq frame (selected-frame))
	    (raise-frame frame)))
      (let ((params (list (cons 'name "*Chessboard*")
			  (cons 'height height)
			  (cons 'width width))))
	(if display
	    (push (cons 'display display) params))
	(select-frame (make-frame params))
	(set-window-dedicated-p (selected-window) t)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Mousing around on the chess-display
;;

(defvar chess-display-last-selected nil)
(make-variable-buffer-local 'chess-display-last-selected)

(defun chess-display-select-piece ()
  "Select the piece under the cursor.
Clicking once on a piece selects it; then click on the target location."
  (interactive)
  (let ((coord (get-text-property (point) 'chess-coord))
	(position (chess-display-position nil)))
    (when coord
      (catch 'invalid
	(if chess-display-last-selected
	    (let ((last-sel chess-display-last-selected))
	      ;; if they select the same square again, just deselect it
	      (if (= (point) (car last-sel))
		  (chess-display-update nil)
		(let ((s-piece (chess-pos-piece position (cadr last-sel)))
		      (t-piece (chess-pos-piece position coord)) ply)
		  (when (and (not (eq t-piece ? ))
			     (if (chess-pos-side-to-move position)
				 (< t-piece ?a)
			       (> t-piece ?a)))
		    (message "Cannot capture your own pieces.")
		    (throw 'invalid t))
		  (setq ply (chess-ply-create position (cadr last-sel) coord))
		  (unless ply
		    (message "That is not a legal move.")
		    (throw 'invalid t))
		  (chess-display-move nil ply)))
	      (setq chess-display-last-selected nil))
	  (let ((piece (chess-pos-piece position coord)))
	    (cond
	     ((eq piece ? )
	      (message "Cannot select an empty square.")
	      (throw 'invalid t))
	     ((if (chess-pos-side-to-move position)
		  (> piece ?a)
		(< piece ?a))
	      (message "Cannot move your opponent's pieces.")
	      (throw 'invalid t)))
	    (setq chess-display-last-selected (list (point) coord))
	    (chess-display-highlight nil coord 'selected)))))))

(defun chess-display-mouse-select-piece (event)
  "Select the piece the user clicked on."
  (interactive "e")
  (cond ((fboundp 'event-window)	; XEmacs
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event))))
	((fboundp 'posn-window)		; Emacs
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))))
  (chess-display-select-piece))

(provide 'chess-display)

;;; chess-display.el ends here
