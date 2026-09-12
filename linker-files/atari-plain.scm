;;; Atari XL/XE, everything in bank $00.  For --code-model=small, or a
;;; large-model program small enough not to need the far banks.
;;;
;;; Bank $00 as a DOS leaves it (BASIC off):
;;;   $0000-$06FF  the OS's, and page 6 is yours by tradition
;;;   $0700-$1FFF  a resident DOS; MEMLO says where it ends
;;;   $2000-$20FF  the direct page          <- the program
;;;   $2100-$9BFF  everything else          <- the program
;;;   $9C00-$9FFF  SpartaDOS X's screen when it runs from a cartridge
;;;                (MEMTOP $9C1F); under a disk DOS the top is $BC1F
;;;   $A000-$BFFF  a cartridge, or RAM without one
;;;   $C000-$FFFF  the OS ROM and the hardware
;;;
;;; The .xex is entered through RUNAD; there is no reset vector.
(define memories
  '((memory DirectPage (address (#x2000 . #x20ff))
            (section (registers ztiny)))
    (memory LoRAM (address (#x2100 . #x9bff))
            (type any))
    (block stack (size #x0800))
    (block heap  (size #x0800))
    (base-address _DirectPageStart DirectPage 0)))
