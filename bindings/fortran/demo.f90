program demo
  use, intrinsic :: iso_c_binding
  use peep
  implicit none
  character(len=10), parameter :: names(2) = [character(len=10) :: 'test.wav', 'test.flac']
  type(peep_t), target :: pe
  integer(c_int8_t), allocatable :: buf(:)
  integer(c_int64_t) :: total, total_sum, seek_sum
  integer :: i, u, n, k, fsize
  logical :: ok

  do i = 1, 2
    open (newunit=u, file=trim(names(i)), access='stream', form='unformatted', status='old')
    inquire (unit=u, size=fsize)
    allocate (buf(fsize))
    read (u) buf
    close (u)
    call peep_open_bytes(pe, buf, ok)
    if (.not. ok) stop 'could not open'
    total = 0; total_sum = 0
    do
      call peep_read(pe, 1024, n)
      if (n == 0) exit
      total = total + n
      total_sum = total_sum + sum_samples(pe%out(1:2*n))
    end do
    call peep_seek_to(pe, 2205_c_int64_t)
    call peep_read(pe, 100, n)
    seek_sum = sum_samples(pe%out(1:2*n))
    write (*, '(a," rate=",i0," channels=",i0," frames=",i0," sum=",i0," seek_sum=",i0)') &
      trim(names(i)), peep_rate(pe), peep_channels(pe), total, total_sum, seek_sum
    call peep_close_all(pe)
    deallocate (buf)
    k = 0
    if (allocated(pe%work)) deallocate (pe%work)
    deallocate (pe%data, pe%out)
  end do

contains
  function sum_samples(a) result(s)
    integer(c_int16_t), intent(in) :: a(:)
    integer(c_int64_t) :: s
    s = sum(int(a, c_int64_t))
  end function sum_samples
end program demo
