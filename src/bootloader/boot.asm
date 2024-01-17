org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A


;
;FAT12 header
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'   ;8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880  ;2880*512 = 1.44MB
bdb_media_descriptor:       db 0F0h  ;0F0h = 1.44MB, 0F8h = 2.88MB - F0 is 3.5" floppy disk
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0


;extended boot record
ebr_drive_number:           db 0  ;0x00 floppy, 0x80 hard disk 
ebr_reserved:               db 0
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h  ;serial number, value doesnt matter
ebr_volume_label:           db 'GRAVGEN OS'  ;11 bytes - padded with spaces
ebr_file_system_type:       db 'FAT12   '  ;8 bytes - padded with spaces


;
;Rest of the code
;

start:
  jmp main

;printing a string to the screen
;params: ds:si - points to string

puts:
  push si
  push ax

.loop:
  lodsb ;loads next character in al
  or al, al ;check if null
  jz .done
  
  mov ah, 0x0e
  int 0x10
  jmp .loop

.done:
  pop ax
  pop si
  ret


main: 
  
  ;setup data segment
  mov ax, 0  ;since cannot write to ds/es directly
  mov ds, ax
  mov es, ax

  ;setup stack
  mov ss, ax
  mov sp, 0x7C00

  ;read something from floppy
  ;BIOS should set dl to drive no
  mov [ebr_drive_number], dl

  mov ax, 1         ;LBA=1, second sector of disk
  mov cl, 1         ; 1 sector to read
  mov bx, 0x7E00   ; data should be after the bootloader
  call disk_read
  
  ;print message
  mov si, msg_hello
  call puts

  hlt

;
;Error handlers
;

floppy_error:
  mov si, msg_read_failed
  call puts
  jmp wait_key_and_reboot
  hlt

wait_key_and_reboot:
  mov ah, 0
  int 16h             ;wait for keypress
  jmp 0FFFFh:0        ; jump to beginning of BIOS, works as reboot

.halt:
  cli         ;disable interrupts, this was CPU cannot get out of halt state
  hlt

;
;Disk routines
;converting Logical Block Address to Cylinder-Head-Sector
;parameters: 
; - ax = lba address
;
;returns:
; - cx [bits 0-5] = sector number
; - cx [bits 6-15] = cylinder
; - dh = head
;

lba_to_chs:
  
  push ax
  push dx

  xor dx, dx          ;dx = 0
  div word [bdb_sectors_per_track]  ;ax = LBA / sectors_per_track
                                    ;dx = LBA % sectors_per_track
  inc dx                            ;dx = (LBA % sectors_per_track) + 1 = sector
  mov cx, dx                        ;cx = sector

  xor dx, dx          ;dx = 0
  div word [bdb_heads]              ;ax = (LBA / sectors_per_track) / heads = cylinder
                                    ;dx = (LBA / sectors_per_track) % heads = head
  mov dh, dl                        ;dh = head
  mov ch, al                        ;ch = cylinder (lower 8 bits)
  shl ah, 6                         ;ah = cylinder (upper 2 bits)
  or cl, ah                         ;put upper 2 bits of cylinder into cl

  pop ax
  mov dl, al        ;restore dl
  pop ax
  ret

;
; reads sectors from a disk
; parameters:
; - ax: LBA address
; - cl: number of sectors to read (max 128)
; - dl: drive number
; - es:bx: memory address where to store the data
;
disk_read:
  push ax          ;save registers that will be modified
  push bx
  push cx
  push dx
  push di

  push cx             ;temporarily save cl (number of sectors to read)
  call lba_to_chs     
  pop ax              ;al = number of sectors to read

  mov ah, 02h         ;read sectors
  mov di, 3           ;retry count

.retry: 
  pusha               ; save all registers, idk what bios might modify
  stc                 ; set carry flag, some BIOSes forget to set it
  int 13h             ; carry flag cleared = success
  jnc .done           ; jump if carry not set

  ;read failed
  popa
  call disk_reset

  dec di
  test di, di
  jnz .retry

.fail:
  ; when no other choice, all attempts exhausted
  jmp floppy_error

.done:
  popa

  push di
  push dx
  push cx
  push bx
  push ax 
  ret           ;restore modified registers

;
;Disk Reset
; params:
; - dl: drive number
;

disk_reset:
  pusha 
  mov ah, 0
  stc
  int 13h
  jc floppy_error
  popa
  ret


msg_hello: db 'Hello World!', ENDL, 0
msg_read_failed: db 'Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h


