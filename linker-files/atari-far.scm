;;; Atari XL/XE with a 65C816 that has RAM above bank $00 -- a Rapidus,
;;; an Antonia -- for --code-model=large.  Bank $00 is laid out as in
;;; atari-plain.scm; the code goes to banks $01 and up.
;;;
;;; A .xex can only load into bank $00, so tools/mkxex.py carries the far
;;; parts as chunks aimed at the stack block and has the DOS call
;;; _fl_copy (src/farload.s) after each one to move it up.  What stays in
;;; bank $00 is everything the small data model addresses through the
;;; data bank register: data, zdata, cdata, idata, the stack, the heap,
;;; the direct page -- and `code`, which is where the startup and the
;;; CIO trampoline live, since CIO is an emulation-mode call and returns
;;; to bank $00.
;;;
;;; ONE MEMORY PER BANK.  The program counter wraps inside its bank, so a
;;; function that straddled $01FFFF/$020000 would run as two halves; the
;;; linker never splits a fragment across memories, so with a memory per
;;; bank every function lands whole.  Two memories per bank, in fact:
;;; nothing is placed in the $D5 page.  Altirra's 65C816 performed a taken
;;; branch's page-crossing dummy read in bank $00 rather than bank K
;;; (cpumachine.inl, kStateJccFalseRead), and $D5xx on the motherboard
;;; bus is cartridge control.  Real silicon has no such cycle.  AltirraSDL
;;; has the fix (pull request #88, merged 2026-09-06, in main from
;;; 46567a14); Altirra proper still has the read as of 4.50-test20.  The
;;; hole costs 256 bytes a bank; take it out when every emulator you run
;;; under is fixed.
;;;
;;; Fifteen banks is the SRAM of a 1 MB Rapidus.  A program that needs
;;; more RAM than that at load time can extend the list; the loader
;;; refuses, by name, a bank that turns out not to be RAM.
(define (far-bank b)
  (let ((name (string-append "Bank" (number->string b 16)))
        (base (* b #x10000)))
    (list
      (list 'memory (string->symbol name)
            (list 'address (cons base (+ base #xd4ff)))
            '(section farcode far zfar cfar switch))
      (list 'memory (string->symbol (string-append name "h"))
            (list 'address (cons (+ base #xd600) (+ base #xffff)))
            '(section farcode far zfar cfar switch)))))

(define memories
  (append
    (apply append (map far-bank '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)))
    '((memory DirectPage (address (#x2000 . #x20ff))
              (section (registers ztiny)))
      (memory LoRAM (address (#x2100 . #x9bff))
              (type any))
      ;; The stack doubles as the loader's staging buffer, so it is also
      ;; the largest chunk the .xex carries: keep it at 1 KB or more.
      (block stack (size #x0800))
      (block heap  (size #x0800))
      (base-address _DirectPageStart DirectPage 0))))
