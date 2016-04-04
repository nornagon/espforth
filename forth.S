// next word
#define nw a15

// data stack pointer
#define dsp a1

// return stack pointer
#define rsp a14

// link register
#define lr a0

#define RAM 0x3FFE8000
#define RAM_SIZE 0x14000
#define RAM_END (RAM + RAM_SIZE)


/*
  MEMORY LAYOUT -------------------------------------------------------

  The esp12e has 96K of data RAM starting at 0x3FFE8000. The standard linker
  script lays out that memory as follows:

  3FFE8000  +------------+
            | .data      |
            +------------+
            | .rodata    |
            +------------+
     ^      | .bss       |
     |      +------------+
    96K     | .. free .. |
     |      |            |
     v      |            |
            \/\/\/\/\/\/\/

            \/\/\/\/\/\/\/
            |            |
  3FFFBFFC  +------------+
  3FFFC000

  Instruction RAM is 32K starting at 0x40100000.

  We reserve a fixed-size block at the endmost part of RAM for the return
  stack, and before that will come the top of the data stack. Heap will grow
  from after the end of the .bss section.

  3FFE8000  +------------+
            | .data      |
            +------------+
            | .rodata    |
            +------------+
            | .bss       |
            +------------+
            | heap       |
            | vvvv       |
            |            |
            |            |
            \/\/\/\/\/\/\/

            \/\/\/\/\/\/\/
            |            |
            |            |
            | ^^^^       |
        S0  | data stack |
            +------------+
            |            |
     1K     | ^^^^       |
        R0  | ret stack  |
  3FFFBFFC  +------------+
  3FFFC000

*/

#define RETURN_STACK_TOP RAM_END
#define RETURN_STACK_SIZE 0x400
#define DATA_STACK_TOP (RETURN_STACK_TOP - RETURN_STACK_SIZE)

  .macro NEXT
  l32i a2, nw, 0
  addi nw, nw, 4
  l32i a3, a2, 0
  jx a3
  .endm

  .macro PUSH sp, reg
  addi \sp, \sp, -4
  s32i \reg, \sp, 0
  .endm

  .macro POP sp, reg
  l32i \reg, \sp, 0
  addi \sp, \sp, 4
  .endm

  .text
  .align 4

DOCOL:
  PUSH rsp, nw
  addi nw, a2, 4
  NEXT

  .text
  .global call_user_start
call_user_start:
  movi a0, uart_rx_one_char_block
  callx0 a0

  // Set up the return stack pointer to point to the top of dram0.
  movi rsp, RAM_END
  // Set up the data stack pointer to point just beneath the end of the return
  // stack.
  movi dsp, DATA_STACK_TOP
  movi a2, var_S0
  s32i dsp, a2, 0
  movi a2, _heap_start
  movi a3, var_HERE
  s32i a2, a3, 0
  // Set the next word to be QUIT and jump start this thing!
  movi nw, cold_start
  NEXT

  .section .rodata
cold_start:
  .int QUIT


/*
  WORD DEFINITION MACROS ----------------------------------------------
*/

  .set F_IMMED, 0x80
  .set F_HIDDEN, 0x20
  .set F_LENMASK, 0x1f

  .set link, 0

  .macro defword name, namelen, flags=0, label
  .section .rodata
  .align 4
  .global name_\label
name_\label :
  .int link
  .set link, name_\label
  .byte \flags + \namelen
  .ascii "\name"
  .align 4
  .global \label
\label :
  .int DOCOL  // the codeword
  // list of word pointers to follow
  .endm

  .macro defcode name, namelen, flags=0, label
  // Our predefined words go in .rodata, which isn't really different to .data
  // but kind of represents the fact that they're not supposed to be changed.
  // Theoretically we could put these in a memory-mapped page with read-only
  // access, if the CPU supported it.
  .section .rodata
  .align 4
  .global name_\label
name_\label :
  .int link   // link to previous word in dictionary
  .set link, name_\label
  .byte \flags + \namelen
  .ascii "\name"
  .align 4
  .global \label
\label :
  .int code_\label  // this is the codeword, which just points to our raw asm
  .text
  .global code_\label
code_\label :
  .endm

  // defvar defines a word which pushes the address of the variable onto the
  // stack.
  .macro defvar name, namelen, flags=0, label, initial=0
  defcode \name, \namelen, \flags, \label
  movi a2, var_\name
  PUSH dsp, a2
  NEXT
  .data
  .align 4
var_\name :
  .int \initial
  .endm

  .macro defconst name, namelen, flags=0, label, value
  defcode \name, \namelen, \flags, \label
  movi a3, \value
  PUSH dsp, a3
  NEXT
  .endm

/*
  WORD DEFINITIONS ----------------------------------------------------
*/

  defconst "R0",2,,RZ,RETURN_STACK_TOP
  defconst "DOCOL",5,,__DOCOL,DOCOL
  defconst "F_IMMED",7,,__F_IMMED,F_IMMED
  defconst "F_HIDDEN",8,,__F_HIDDEN,F_HIDDEN
  defconst "F_LENMASK",9,,__F_LENMASK,F_LENMASK

  defvar "STATE",5,,STATE
  defvar "HERE",4,,HERE
  defvar "S0",2,,SZ
  defvar "BASE",4,,BASE,10

/*
  STACK TWIDDLING -----------------------------------------------------
*/

  defcode "DROP",4,,DROP
  addi dsp, dsp, 4
  NEXT

  defcode "DUP",3,,DUP
  l32i a2, dsp, 0
  PUSH dsp, a2
  NEXT

  defcode "OVER",4,,OVER
  l32i a2, dsp, 4
  PUSH dsp, a2
  NEXT

  defcode "2DUP",4,,TWODUP
  l32i a2, dsp, 0
  l32i a3, dsp, 4
  PUSH dsp, a2
  PUSH dsp, a3
  NEXT

/*
  RETURN STACK --------------------------------------------------------
*/

  defcode ">R",2,,TOR
  POP dsp, a2
  PUSH rsp, a2
  NEXT

  defcode "R>",2,,FROMR
  POP rsp, a2
  PUSH dsp, a2
  NEXT

/*
  STACK POINTER TRICKERY ----------------------------------------------
*/

  defcode "RSP@",4,,RSPFETCH
  PUSH dsp, rsp
  NEXT

  defcode "RSP!",4,,RSPSTORE
  POP dsp, rsp
  NEXT

  defcode "RDROP",5,,RDROP
  addi rsp, rsp, 4
  NEXT

  defcode "DSP@",4,,DSPFETCH
  mov a2, dsp
  PUSH dsp, a2
  NEXT

  defcode "DSP!",4,,DSPSTORE
  POP dsp, a2
  mov dsp, a2
  NEXT

/*
  ARITHMETIC ----------------------------------------------------------
*/

  defcode "+",1,,ADD
  POP dsp, a2
  POP dsp, a3
  add a2, a2, a3
  PUSH dsp, a2
  NEXT

  defcode "-",1,,SUB
  POP dsp, a2
  POP dsp, a3
  sub a2, a2, a3
  PUSH dsp, a2
  NEXT

  defcode "*",1,,MUL
  POP dsp, a2
  POP dsp, a3
  mull a2, a2, a3
  PUSH dsp, a2
  NEXT

  defcode "/",1,,DIV
  POP dsp, a2
  POP dsp, a3
  movi a0, __udivsi3
  callx0 a0
  PUSH dsp, a2
  NEXT

  defcode "MOD",3,,MOD
  POP dsp, a2
  POP dsp, a3
  movi a0, __umodsi3
  callx0 a0
  PUSH dsp, a2
  NEXT

  defcode "4+",2,,INCR4
  POP dsp, a2
  addi a2, a2, 4
  PUSH dsp, a2
  NEXT

/*
  COMPARISON ----------------------------------------------------------
*/

  defcode "=",1,,EQU
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  beq a2, a3, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

  defcode "<>",2,,NEQU
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  bne a2, a3, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

  defcode "<",1,,LT
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  blt a2, a3, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

  defcode "<=",1,,LE
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  bge a3, a2, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

  defcode ">",1,,GT
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  blt a3, a2, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

  defcode ">=",2,,GE
  POP dsp, a2
  POP dsp, a3
  movi a4, 1
  bge a2, a3, 1f
  movi a4, 0
1:
  PUSH dsp, a4
  NEXT

/*
  LITERALS ------------------------------------------------------------
*/

  defcode "LIT",3,,LIT
  l32i a2, nw, 0
  addi nw, nw, 4
  PUSH dsp, a2
  NEXT

/*
  MEMORY --------------------------------------------------------------
*/

  defcode "!",1,,STORE
  POP dsp, a2  // address
  POP dsp, a3  // value
  s32i a3, a2, 0
  NEXT

  defcode "@",1,,FETCH
  POP dsp, a2  // address
  l32i a2, a2, 0
  PUSH dsp, a2
  NEXT

  defcode "C!",2,,STOREBYTE
  POP dsp, a2  // address
  POP dsp, a3  // value
  s8i a3, a2, 0
  NEXT

  defcode "C@",2,,FETCHBYTE
  POP dsp, a2  // address
  l8ui a2, a2, 0
  PUSH dsp, a2
  NEXT


/*
  INPUT AND OUTPUT ----------------------------------------------------
*/

  defcode "KEY",3,,KEY
  call0 _KEY
  PUSH dsp, a2
  NEXT
_KEY:
  PUSH dsp, a0
  movi a0, uart_rx_one_char_block
  callx0 a0
  // & echo
  PUSH dsp, a2  // uart_tx_one_char sets a2 to 0, so save it
  movi a0, uart_tx_one_char
  callx0 a0
  POP dsp, a2
  POP dsp, a0
  ret

  defcode "EMIT",4,,EMIT
  POP dsp, a2
  call0 _EMIT
  NEXT
_EMIT:
  PUSH dsp, a0
  movi a0, uart_tx_one_char
  callx0 a0
  POP dsp, a0
  ret

  defcode "WORD",4,,WORD
  call0 _WORD
  PUSH dsp, a3
  PUSH dsp, a2
  NEXT
_WORD:
  PUSH dsp, a0
  movi a12, ' '+1
1:
  call0 _KEY
  blt a2, a12, 1b        // if char is <= 0x20, keep looking

  // we have the start of the word, now look for the end & store as we go
  movi a13, word_buffer
2:
  s8i a2, a13, 0
  addi a13, a13, 1
  call0 _KEY
  bge a2, a12, 2b

  // return the length of the word in a2, and the pointer to the word in a3
  movi a3, word_buffer
  sub a2, a13, a3
  POP dsp, a0
  ret

  .section .bss
word_buffer:
  .space 32

  defcode "NUMBER",6,,NUMBER
  POP dsp, a2 // length
  POP dsp, a3 // addr
  call0 _NUMBER
  PUSH dsp, a3 // parsed number
  PUSH dsp, a2 // number of unparsed characters (0 = no error)
  NEXT
_NUMBER:
  movi a4, 0
  blti a2, 1, 5f
  movi a9, var_BASE
  l32i a9, a9, 0
  movi a6, '9'+1

  movi a8, 0 // is_negative
  l8ui a5, a3, 0
  movi a7, '-'
  bne a5, a7, 1f
  blti a2, 2, 5f // if first char is '-' and length < 2, NaN
  movi a8, 1
  addi a2, a2, -1
  addi a3, a3, 1

1:
  mull a4, a4, a9
  l8ui a5, a3, 0
  addi a3, a3, 1
  addi a5, a5, -'0'
  bltz a5, 4f
  blt a5, a6, 3f
  addi a5, a5, -('A'-'0')
  bltz a5, 4f
  addi a5, a5, 10
3:
  bge a5, a9, 4f  // digit >= base
  add a4, a4, a5
  addi a2, a2, -1
  bnez a2, 1b

4:
  beqz a8, 5f   // negate the parsed number if we detected a '-' earlier
  neg a4, a4

5:
  mov a3, a4   // a3 = parsed number, a2 = num remaining chars
  ret

  defcode "TELL",4,,TELL
  POP dsp, a12 // length
  POP dsp, a13 // addr
1:
  beqz a12, 2f
  l8ui a2, a13, 0
  call0 _EMIT
  addi a13, a13, 1
  addi a12, a12, -1
  j 1b
2:
  NEXT

/*
  FLOW CONTROL --------------------------------------------------------
*/

  defcode "EXIT",4,,EXIT
  POP rsp, nw
  NEXT

  defcode "BRANCH",6,,BRANCH
  l32i a2, nw, 0
  add nw, nw, a2
  NEXT

  defcode "0BRANCH",7,,ZBRANCH
  POP dsp, a0
  beqz a0, code_BRANCH
  addi nw, nw, 4
  NEXT

/*
  LEXICON -------------------------------------------------------------
*/

  defcode "FIND",4,,FIND
  POP dsp, a2  // length
  POP dsp, a3  // address of word to find
  call0 _FIND
  PUSH dsp, a2 // address of found word, or 0
  NEXT
_FIND:
  beqz a2, 5f  // no 0-length words.
  movi a4, var_LATEST
  l32i a4, a4, 0
1:
  beqz a4, 5f  // we got to NULL
  
  l8ui a5, a4, 4  // a5 = len + flags
  movi a6, (F_LENMASK|F_HIDDEN)
  and a5, a5, a6
  bne a5, a2, 4f  // lengths unequal, go to next word

  // compare strings
  PUSH dsp, a3  // save the needle, we're going to step through the string
  addi a8, a4, 5 // word+5 is where the name starts
2:
  addi a5, a5, -1
  bltz a5, 3f // ran out of characters. so they match!
  l8ui a6, a8, 0
  l8ui a7, a3, 0
  addi a8, a8, 1
  addi a3, a3, 1
  beq a6, a7, 2b

3:
  POP dsp, a3
  bgez a5, 4f  // if we get here and a5 > -1 then we found a mismatch. next!
  mov a2, a4
  ret

4: // go to next word
  l32i a4, a4, 0
  j 1b

5: // not found
  movi a2, 0
  ret

  defcode ">CFA",4,,TCFA
  POP dsp, a2
  call0 _TCFA
  PUSH dsp, a2
  NEXT
_TCFA:
  l8ui a3, a2, 4  // load flags+len into a3
  addi a2, a2, 5  // skip link pointer + len byte
  movi a4, F_LENMASK
  and a3, a3, a4
  add a2, a2, a3
  addi a2, a2, 3  // round up to nearest 4-byte boundary
  movi a4, ~3
  and a2, a2, a4
  ret

  defword ">DFA",4,,TDFA
  .int TCFA
  .int INCR4
  .int EXIT

/*
  COMPILING -----------------------------------------------------------
*/

  defcode "CREATE",6,,CREATE
  // Get name length & address
  POP dsp, a2          // a2 = length
  POP dsp, a3          // a3 = address
  movi a0, var_HERE
  l32i a4, a0, 0
  mov a8, a4
  movi a6, var_LATEST  // get the link pointer
  l32i a5, a6, 0
  s32i a5, a4, 0       // store it at HERE
  s8i a2, a4, 4        // store the length byte after that
  addi a4, a4, 5
  // copy the name
1:
  l8ui a5, a3, 0
  s8i a5, a4, 0
  addi a4, a4, 1
  addi a3, a3, 1
  addi a2, a2, -1
  bnez a2, 1b

  addi a4, a4, 3       // round up to the nearest 4
  movi a5, ~3
  and a4, a4, a5

  s32i a4, a0, 0       // store the new HERE
  s32i a8, a6, 0       // store the old HERE into LATEST
  NEXT

  defcode ",",1,,COMMA
  POP dsp, a2
  call0 _COMMA
  NEXT
_COMMA:
  movi a3, var_HERE
  l32i a4, a3, 0
  s32i a2, a4, 0
  addi a4, a4, 4
  s32i a4, a3, 0
  ret

  defcode "[",1,F_IMMED,LBRAC
  movi a2, 0
  movi a3, var_STATE
  s32i a2, a3, 0
  NEXT

  defcode "]",1,,RBRAC
  movi a2, 1
  movi a3, var_STATE
  s32i a2, a3, 0
  NEXT

  defword ":",1,,COLON
  .int WORD
  .int CREATE
  .int LIT, DOCOL, COMMA
  .int LATEST, FETCH, HIDDEN
  .int RBRAC
  .int EXIT

  defword ";",1,F_IMMED,SEMICOLON
  .int LIT, EXIT, COMMA
  .int LATEST, FETCH, HIDDEN
  .int LBRAC
  .int EXIT

  defcode "IMMEDIATE",9,F_IMMED,IMMEDIATE
  movi a0, var_LATEST
  l8ui a2, a0, 4      // get the name/length byte
  movi a3, F_IMMED
  xor a2, a2, a3      // toggle the IMMEDIATE flag
  s8i a2, a0, 4
  NEXT

  defcode "HIDDEN",6,,HIDDEN
  POP dsp, a0         // get the word to modify from the stack
  l8ui a2, a0, 4      // get the name/length byte
  movi a3, F_IMMED
  xor a2, a2, a3      // toggle the IMMEDIATE flag
  s8i a2, a0, 4
  NEXT

  defword "HIDE",4,,HIDE
  .int WORD, FIND, HIDDEN
  .int EXIT

  defcode "'",1,,TICK
  l32i a0, nw, 0      // get the address of the next word
  addi nw, nw, 4      // don't execute it
  PUSH dsp, a0        // push the address on the stack
  NEXT


/*
  INTERPRETER ---------------------------------------------------------
*/

  defword "QUIT",4,,QUIT
  .int RZ, RSPSTORE   // R0 RSP!, clear the return stack
  .int INTERPRET      // interpret the next word
  .int BRANCH, -8     // and loop forever

  defword "INTERPRET",9,,INTERPRET
  //.int KEY, EMIT
  //.int WORD, TELL
  .int LIT, 62, EMIT, WORD, FIND, ZBRANCH, -24, LIT, 42, EMIT
  .int EXIT

  defcode "K*",2,,KSTARS
  1:
  movi a0, uart_rx_one_char_block
  callx0 a0
  movi a2, '*'
  movi a0, uart_tx_one_char
  callx0 a0
  j 1b

  defcode "DEBUG",2,,DEBUG
  1:
  movi a0, uart_rx_one_char_block
  callx0 a0
  movi a2, debugstr
  mov a3, nw
  movi a0, ets_printf
  callx0 a0
  movi a2, '.'
  movi a0, uart_tx_one_char
  callx0 a0
  j 1b
  .section .rodata
debugstr:
  .asciz "nw: %08x"


  defvar "LATEST",6,,LATEST,link
