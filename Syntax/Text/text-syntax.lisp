;;; -*- Mode: Lisp; Package: COMMON-LISP-USER -*-

;;;  (c) copyright 2005 by
;;;           Robert Strandh (strandh@labri.fr)
;;;  (c) copyright 2005 by
;;;           Matthieu Villeneuve (matthieu.villeneuve@free.fr)
;;;  (c) copyright 2007 by
;;;           Troels Henriksen (athas@sigkill.dk)

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.

;;; Syntax for analysing ordinary text.

;;; Invariants after a complete syntax analysis:
;;;
;;; There is exactly one left-sticky mark at every offset followed by
;;; character other than a newline and preceded either by nothing
;;; (beginning of the buffer), by a newline character at the beginning
;;; of the buffer, or by two newline characters.
;;; 
;;; There is exactly one right-sticky mark at every offset preceded by
;;; a character other than a newline and followed either by nothing
;;; (end of the buffer), by a newline character at the end of the
;;; buffer, or by two newline characters.
;;;
;;; It follows that:
;;;   * there can never be two marks in the same place,
;;;   * there are as many left-sticky marks as right-sticky marks, 
;;;   * left-sticky and right-sticky marks alternate, starting with a 
;;;     left-sticky mark
;;;
;;; N.B.: These invariants only hold AFTER a complete syntax analysis.
;;;       we do now know what might have happened during the editing
;;;       phase between to invocations of the analysis.
;;;
;;; D.H.: Invariant text needs to change to reflect sentences.
;;;       Should there be paragraph invariants and sentence invariants?
;;;       Did I ducttape this in the wrong place?
;;;       Sentence invariants:  
;;;       Left stickies after . ? and !, at the end of the buffer
;;;       Right stickies at non whitespace characters preceeded by space and punctuation.
;;;       

(in-package :climacs-text-syntax)

(defun index-of-mark-after-offset (flexichain offset)
  "Searches for the mark after `offset' in the marks stored in `flexichain'."
  (loop with low-position = 0
     with high-position = (flexichain:nb-elements flexichain)
     for middle-position = (floor (+ low-position high-position) 2)
     until (= low-position high-position)
     do (if (drei-buffer:mark>= (flexichain:element* flexichain middle-position) offset)
            (setf high-position middle-position)
            (setf low-position (floor (+ low-position 1 high-position) 2)))
     finally (return low-position)))

(drei-syntax:define-syntax text-syntax (drei-fundamental-syntax:fundamental-syntax)
  ((paragraphs :initform (make-instance 'flexichain:standard-flexichain))
   (sentence-beginnings :initform (make-instance 'flexichain:standard-flexichain))
   (sentence-endings :initform (make-instance 'flexichain:standard-flexichain)))
  (:name "Text")
  (:pathname-types "text" "txt" "README"))

(defmethod drei-syntax:update-syntax esa-utils:values-max-min ((syntax text-syntax) prefix-size suffix-size
                                         &optional begin end)
  (declare (ignore begin end))
  (let* ((buffer (buffer syntax))
         (high-mark-offset (- (drei-buffer:size buffer) suffix-size))
         (low-mark-offset prefix-size)
         (high-offset (min (+ high-mark-offset 3) (drei-buffer:size buffer)))
	 (low-offset (max (- low-mark-offset 3) 0)))
    (with-slots (paragraphs sentence-beginnings sentence-endings) syntax
      (let ((pos1 (index-of-mark-after-offset paragraphs low-offset))
	    (pos-sentence-beginnings (index-of-mark-after-offset sentence-beginnings low-offset))
	    (pos-sentence-endings (index-of-mark-after-offset sentence-endings low-offset)))
        ;; start by deleting all syntax marks that are between the low and
        ;; the high marks
        (loop repeat (- (flexichain:nb-elements paragraphs) pos1)
           while (drei-buffer:mark<= (flexichain:element* paragraphs pos1) high-offset)
           do (flexichain:delete* paragraphs pos1))
        (loop repeat (- (flexichain:nb-elements sentence-beginnings) pos-sentence-beginnings)
           while (drei-buffer:mark<= (flexichain:element* sentence-beginnings pos-sentence-beginnings) high-offset)
           do (flexichain:delete* sentence-beginnings pos-sentence-beginnings))
        (loop repeat (- (flexichain:nb-elements sentence-endings) pos-sentence-endings)
           while (drei-buffer:mark<= (flexichain:element* sentence-endings pos-sentence-endings) high-offset)
           do (flexichain:delete* sentence-endings pos-sentence-endings))

        ;; check the zone between low-offset and high-offset for
        ;; paragraph delimiters and sentence delimiters
        (loop with buffer-size = (drei-buffer:size buffer)
           for offset from low-offset to high-offset ;; Could be rewritten with even fewer buffer-object calls,
           for current-object = nil then (if (>= offset high-offset) nil (drei-buffer:buffer-object buffer offset)) ;;  but it'd be premature optimization, and messy besides.  
           for next-object =  nil then (if (>= offset (- high-offset 1)) nil (drei-buffer:buffer-object buffer (1+ offset)))
           for prev-object =  nil then (if (= offset low-offset) nil (drei-buffer:buffer-object buffer (1- offset)))
           for before-prev-object = nil then (if (<= offset (1+ low-offset)) nil (drei-buffer:buffer-object buffer (- offset 2)))
           do (progn 
                (cond ((and (< offset buffer-size)
                            (member prev-object '(#\. #\? #\!))
                            (or (= offset (1- buffer-size))
                                (and (member current-object '(#\Newline #\Space #\Tab))
                                     (or (= offset 1)
                                         (not (member before-prev-object '(#\Newline #\Space #\Tab)))))))
                       (let ((m (drei-buffer:make-buffer-mark buffer low-mark-offset :left)))
                         (setf (drei-buffer:offset m) offset)
                         (flexichain:insert* sentence-endings pos-sentence-endings m))
                       (incf pos-sentence-endings))

                      ((and (>= offset 0)
                            (not (member current-object '(#\. #\? #\! #\Newline #\Space #\Tab)))
                            (or (= offset 0)
                                (member prev-object '(#\Newline #\Space #\Tab)))
                            (or (<= offset 1)
                                (member before-prev-object '(#\. #\? #\! #\Newline #\Space #\Tab))))
                       (let ((m (drei-buffer:make-buffer-mark buffer low-mark-offset :right)))
                         (setf (drei-buffer:offset m) offset)
                         (flexichain:insert* sentence-beginnings pos-sentence-beginnings m))
                       (incf pos-sentence-beginnings))
                      (t nil))

                ;; Paragraphs

                (cond ((and (< offset buffer-size) ;; Ends
                            (not (eql current-object #\Newline))
                            (or (zerop offset)
                                (and (eql prev-object #\Newline)
                                     (or (= offset 1)
                                         (eql before-prev-object #\Newline)))))
                       (let ((m (drei-buffer:make-buffer-mark buffer low-mark-offset :left)))
                         (setf (drei-buffer:offset m) offset)
                         (flexichain:insert* paragraphs pos1 m))
                       (incf pos1))

                      ((and (plusp offset) ;;Beginnings
                            (not (eql prev-object #\Newline))
                            (or (= offset buffer-size)
                                (and (eql current-object #\Newline)
                                     (or (= offset (1- buffer-size))
                                         (eql next-object #\Newline)))))
                       (let ((m (drei-buffer:make-buffer-mark buffer low-mark-offset :right)))
                         (setf (drei-buffer:offset m) offset)
                         (flexichain:insert* paragraphs pos1 m))
                       (incf pos1))
                      (t nil)))))))
  (values 0 (drei-buffer:size (buffer syntax))))

(defmethod drei-motion:backward-one-paragraph (mark (syntax text-syntax))
  (with-slots (paragraphs) syntax
     (let ((pos1 (index-of-mark-after-offset paragraphs (drei-buffer:offset mark))))
       (when (> pos1 0)
	 (setf (drei-buffer:offset mark)
	       (if (typep (flexichain:element* paragraphs (1- pos1)) 'drei-buffer:right-sticky-mark)
		   (drei-buffer:offset (flexichain:element* paragraphs (- pos1 2)))
		   (drei-buffer:offset (flexichain:element* paragraphs (1- pos1)))))
         t))))

(defmethod drei-motion:forward-one-paragraph ((mark mark) (syntax text-syntax))
  (with-slots (paragraphs) syntax
    (let ((pos1 (index-of-mark-after-offset
                 paragraphs
                 ;; if mark is at paragraph-end, jump to end of next
                 ;; paragraph
                 (1+ (drei-buffer:offset mark)))))
      (when (< pos1 (flexichain:nb-elements paragraphs))
	 (setf (drei-buffer:offset mark)
	       (if (typep (flexichain:element* paragraphs pos1) 'drei-buffer:left-sticky-mark)
		   (drei-buffer:offset (flexichain:element* paragraphs (1+ pos1)))
		   (drei-buffer:offset (flexichain:element* paragraphs pos1))))
         t))))

 (defmethod drei-motion:backward-one-sentence ((mark mark) (syntax text-syntax))
   (with-slots (sentence-beginnings) syntax
      (let ((pos1 (index-of-mark-after-offset sentence-beginnings (drei-buffer:offset mark))))
        (when (> pos1 0)
          (setf (drei-buffer:offset mark)
                (drei-buffer:offset (flexichain:element* sentence-beginnings (1- pos1))))
          t))))

 (defmethod drei-motion:forward-one-sentence ((mark mark) (syntax text-syntax))
   (with-slots (sentence-endings) syntax
     (let ((pos1 (index-of-mark-after-offset
                  sentence-endings
                  ;; if mark is at sentence-end, jump to end of next
                  ;; sentence
                  (1+ (drei-buffer:offset mark)))))
       (when (< pos1 (flexichain:nb-elements sentence-endings))
 	 (setf (drei-buffer:offset mark)
               (drei-buffer:offset (flexichain:element* sentence-endings pos1)))
         t))))

(defmethod drei-syntax:syntax-line-indentation ((mark mark) tab-width (syntax text-syntax))
  (loop with indentation = 0
        with mark2 = (drei-buffer:clone-mark mark)
        until (drei-buffer:beginning-of-buffer-p mark2)
        do (drei-motion:backward-line mark2 syntax)
           (setf indentation (line-indentation mark2 tab-width))
        while (empty-line-p mark2)
        finally (return indentation)))
