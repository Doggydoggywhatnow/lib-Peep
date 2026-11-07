! Liberated Peep for Fortran (iso_c_binding)
module peep
  use, intrinsic :: iso_c_binding
  implicit none
  private
  public :: peep_t, peep_open_bytes, peep_read, peep_seek_to, peep_set_gain, peep_close_all
  public :: peep_rate, peep_channels, peep_total, peep_position

  interface
    function c_open(p, codecs, data, n, work, ws) bind(C, name="peep_open")
      import :: c_int, c_ptr, c_size_t
      integer(c_int) :: c_open
      type(c_ptr), value :: p, codecs, data, work
      integer(c_size_t), value :: n, ws
    end function c_open
    function c_fill(p, out, frames) bind(C, name="peep_fill")
      import :: c_ptr, c_size_t
      integer(c_size_t) :: c_fill
      type(c_ptr), value :: p, out
      integer(c_size_t), value :: frames
    end function c_fill
    subroutine c_seek(p, frame) bind(C, name="peep_seek")
      import :: c_ptr, c_int64_t
      type(c_ptr), value :: p
      integer(c_int64_t), value :: frame
    end subroutine c_seek
    subroutine c_close(p) bind(C, name="peep_close")
      import :: c_ptr
      type(c_ptr), value :: p
    end subroutine c_close
    function c_flac() bind(C, name="peep_flac")      ! address of the FLAC codec table
      import :: c_ptr
      type(c_ptr) :: c_flac
    end function c_flac
  end interface

  ! A decoder. Declare it with the TARGET attribute and do not copy it.
  type :: peep_t
    integer(c_int64_t) :: p(20) = 0_c_int64_t           ! struct peep (160 bytes)
    integer(c_int8_t), allocatable :: data(:)           ! the library reads from this
    type(c_ptr) :: codecs(2)
    integer(c_int64_t), allocatable :: work(:)
    integer(c_int16_t), allocatable :: out(:)
  end type peep_t

contains

  ! bytes: a WAV or FLAC file. ok is .true. on success.
  subroutine peep_open_bytes(pe, bytes, ok)
    type(peep_t), target, intent(inout) :: pe
    integer(c_int8_t), intent(in) :: bytes(:)
    logical, intent(out) :: ok
    integer(c_size_t) :: need
    pe%data = bytes
    allocate (pe%out(4096 * 2))
    pe%p = 0_c_int64_t
    pe%codecs(1) = c_flac()
    pe%codecs(2) = c_null_ptr
    ok = c_open(c_loc(pe%p), c_loc(pe%codecs), c_loc(pe%data), int(size(pe%data), c_size_t), c_null_ptr, 0_c_size_t) /= 0
    if (.not. ok) then
      need = int(pe%p(19), c_size_t)                    ! work_need (offset 144)
      if (need == 0) return
      allocate (pe%work((need + 7) / 8))
      pe%work = 0_c_int64_t
      ok = c_open(c_loc(pe%p), c_loc(pe%codecs), c_loc(pe%data), int(size(pe%data), c_size_t), &
                  c_loc(pe%work), need) /= 0
    end if
  end subroutine peep_open_bytes

  integer function peep_rate(pe)                         ! Hz
    type(peep_t), intent(in) :: pe
    peep_rate = int(iand(pe%p(6), int(z'FFFFFFFF', c_int64_t)))
  end function peep_rate

  integer function peep_channels(pe)                     ! channels in the file
    type(peep_t), intent(in) :: pe
    peep_channels = int(iand(ishft(pe%p(6), -32), int(z'FFFFFFFF', c_int64_t)))
  end function peep_channels

  integer(c_int64_t) function peep_total(pe)             ! frames, 0 = unknown
    type(peep_t), intent(in) :: pe
    peep_total = pe%p(5)
  end function peep_total

  integer(c_int64_t) function peep_position(pe)          ! frames played so far
    type(peep_t), intent(in) :: pe
    peep_position = pe%p(4)
  end function peep_position

  ! Reads up to `frames` stereo frames. n is the number of frames produced (0 at the end);
  ! the samples are pe%out(1:2*n), interleaved.
  subroutine peep_read(pe, frames, n)
    type(peep_t), target, intent(inout) :: pe
    integer, intent(in) :: frames
    integer, intent(out) :: n
    n = int(c_fill(c_loc(pe%p), c_loc(pe%out), int(min(frames, 4096), c_size_t)))
  end subroutine peep_read

  subroutine peep_seek_to(pe, frame)
    type(peep_t), target, intent(inout) :: pe
    integer(c_int64_t), intent(in) :: frame
    call c_seek(c_loc(pe%p), frame)
  end subroutine peep_seek_to

  subroutine peep_set_gain(pe, q8)                       ! volume 0..256 (256 = full)
    type(peep_t), intent(inout) :: pe
    integer, intent(in) :: q8
    pe%p(7) = ior(iand(pe%p(7), not(int(z'FFFFFFFF', c_int64_t))), int(max(0, min(256, q8)), c_int64_t))
  end subroutine peep_set_gain

  subroutine peep_close_all(pe)
    type(peep_t), target, intent(inout) :: pe
    call c_close(c_loc(pe%p))
  end subroutine peep_close_all

end module peep
