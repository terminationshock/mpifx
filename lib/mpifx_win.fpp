#:include 'mpifx.fypp'
#:set TYPES = NUMERIC_TYPES

!> Contains routined for MPI shared memory windows.
module mpifx_win_module
  use mpifx_common_module
  use iso_c_binding, only : c_ptr, c_f_pointer
  implicit none
  private

  public :: mpifx_win

  !> MPI shared memory window with some additional information.
  type mpifx_win
    private
    integer, public :: id  !< Window id.
    integer :: comm_id     !< Communicator id.
  contains
    !> Initializes an MPI shared memory window.
  #:for TYPE in TYPES
    generic :: allocate_shared => mpifx_win_allocate_shared_${TYPE_ABBREVS[TYPE]}$
  #:endfor

  #:for TYPE in TYPES
    procedure, private :: mpifx_win_allocate_shared_${TYPE_ABBREVS[TYPE]}$
  #:endfor

    !> Locks a shared memory segment for remote access.
    procedure :: lock => mpifx_win_lock

    !> Unlocks a shared memory segment.
    procedure :: unlock => mpifx_win_unlock

    !> Synchronizes shared memory across MPI ranks after remote access.
    procedure :: sync => mpifx_win_sync

    !> Ensures consistency of stores between fence calls.
    procedure :: fence => mpifx_win_fence

    !> Deallocates memory associated with a shared memory segment.
    procedure :: free => mpifx_win_free

  end type mpifx_win

contains

#:def mpifx_win_allocate_shared_template(SUFFIX, TYPE)

  !> Initialized a window handle and returns a pointer to the address associated with a shared
  !> memory segment.
  !!
  !! \param self  Handle of the shared memory window on return.
  !! \param mycomm  MPI communicator.
  !! \param global_length  Number of elements of type ${TYPE}$ in the entire shared memory window.
  !! \param global_pointer  Pointer to the shared data array of length 'global_length' on return.
  !! \param local_length  Number of elements of type ${TYPE}$ occupied by the current rank.
  !! \param local_pointer Pointer to the local chunk of the data array of length 'local_length' on
  !! return.
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_ALLOCATE_SHARED)
  !!
  subroutine mpifx_win_allocate_shared_${SUFFIX}$(self, mycomm, global_length, global_pointer,&
      & local_length, local_pointer, error)
    class(mpifx_win), intent(out) :: self
    class(mpifx_comm), intent(in) :: mycomm
    integer, intent(in) :: global_length
    ${TYPE}$, pointer, intent(out) :: global_pointer(:)
    integer, intent(in), optional :: local_length
    ${TYPE}$, pointer, intent(out), optional :: local_pointer(:)
    integer, intent(out), optional :: error

    integer :: disp_unit, error0, error1
    integer(MPI_ADDRESS_KIND) :: global_mem_size, local_mem_size
    type(c_ptr) :: global_baseptr, local_baseptr

    disp_unit = storage_size(global_pointer) / 8

    local_mem_size = 0
    if (present(local_length)) then
      local_mem_size = int(local_length, kind=MPI_ADDRESS_KIND) * disp_unit
    else if (mycomm%lead) then
      local_mem_size = int(global_length, kind=MPI_ADDRESS_KIND) * disp_unit
    end if

    call mpi_win_allocate_shared(local_mem_size, disp_unit, MPI_INFO_NULL, mycomm%id,&
        & local_baseptr, self%id, error0)
    call handle_errorflag(error0,&
        & "MPI_WIN_ALLOCATE_SHARED in mpifx_win_allocate_shared_${SUFFIX}$", error)

    call mpi_win_shared_query(self%id, mycomm%leadrank, global_mem_size, disp_unit, global_baseptr,&
        & error1)
    call handle_errorflag(error1, "MPI_WIN_SHARED_QUERY in mpifx_win_allocate_shared_${SUFFIX}$",&
        & error)

    self%comm_id = mycomm%id
    call c_f_pointer(global_baseptr, global_pointer, [global_length])
    if (present(local_pointer)) then
      call c_f_pointer(local_baseptr, local_pointer, [local_length])
    end if

  end subroutine mpifx_win_allocate_shared_${SUFFIX}$

#:enddef mpifx_win_allocate_shared_template

  !> Locks a shared memory segment for remote access. Starts a remote access epoch.
  !!
  !! \param self  Handle of the shared memory window.
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_LOCK_ALL)
  !!
  subroutine mpifx_win_lock(self, error)
    class(mpifx_win), intent(inout) :: self
    integer, intent(out), optional :: error

    integer :: error0

    call mpi_win_lock_all(MPI_MODE_NOCHECK, self%id, error0)
    call handle_errorflag(error0, "MPI_WIN_LOCK_ALL in mpifx_win_lock", error)

  end subroutine mpifx_win_lock


  !> Unlocks a shared memory segment. Finishes a remote access epoch.
  !!
  !! \param self  Handle of the shared memory window.
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_UNLOCK_ALL)
  !!
  subroutine mpifx_win_unlock(self, error)
    class(mpifx_win), intent(inout) :: self
    integer, intent(out), optional :: error

    integer :: error0

    call mpi_win_unlock_all(self%id, error0)
    call handle_errorflag(error0, "MPI_WIN_UNLOCK_ALL in mpifx_win_unlock", error)

  end subroutine mpifx_win_unlock


  !> Synchronizes shared memory across MPI ranks after remote access.
  !> Completes all memory stores in a remote access epoch.
  !!
  !! \param self  Handle of the shared memory window.
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_SYNC)
  !!
  subroutine mpifx_win_sync(self, error)
    class(mpifx_win), intent(inout) :: self
    integer, intent(out), optional :: error

    integer :: error0, error1

    call mpi_win_sync(self%id, error0)
    call handle_errorflag(error0, "MPI_WIN_SYNC in mpifx_win_sync", error)

    call mpi_barrier(self%comm_id, error1)
    call handle_errorflag(error1, "MPI_BARRIER in mpifx_win_sync", error)

  end subroutine mpifx_win_sync


  !> Ensure consistency of stores between fence calls
  !!
  !! \param self  Handle of the shared memory window.
  !! \param assert  Hint to the MPI library to assume certain condition (e.g., MPI_MODE_NOSTORE).
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_FENCE)
  !!
  subroutine mpifx_win_fence(self, assert, error)
    class(mpifx_win), intent(inout) :: self
    integer, intent(in), optional :: assert
    integer, intent(out), optional :: error

    integer :: error0, assert_

    assert_ = 0
    if (present(assert)) then
      assert_ = assert
    end if

    call mpi_win_fence(assert_, self%id, error0)
    call handle_errorflag(error0, "MPI_WIN_FENCE in mpifx_win_fence", error)

  end subroutine mpifx_win_fence


  !> Deallocates memory associated with a shared memory segment.
  !!
  !! \param self  Handle of the shared memory window.
  !! \param error  Optional error code on return.
  !!
  !! \see MPI documentation (\c MPI_WIN_FREE)
  !!
  subroutine mpifx_win_free(self, error)
    class(mpifx_win), intent(inout) :: self
    integer, intent(out), optional :: error

    integer :: error0

    call mpi_win_free(self%id, error0)
    call handle_errorflag(error0, "MPI_WIN_FREE in mpifx_win_free", error)

  end subroutine mpifx_win_free


#:for TYPE in TYPES
  #:set FTYPE = FORTRAN_TYPES[TYPE]
  #:set SUFFIX = TYPE_ABBREVS[TYPE]

  $:mpifx_win_allocate_shared_template(SUFFIX, FTYPE)

#:endfor

end module mpifx_win_module
