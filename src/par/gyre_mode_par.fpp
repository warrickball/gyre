  ! Module   : gyre_mode_par
! Purpose  : mode parameters
!
! Copyright 2013-2016 Rich Townsend
!
! This file is part of GYRE. GYRE is free software: you can
! redistribute it and/or modify it under the terms of the GNU General
! Public License as published by the Free Software Foundation, version 3.
!
! GYRE is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
! or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
! License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

$include 'core.inc'
$include 'core_parallel.inc'

module gyre_mode_par

  ! Uses

  use core_kinds
  use core_parallel

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type :: mode_par_t
     integer       :: l = 0
     integer       :: m = 0
     integer       :: n_pg_min = -HUGE(0)
     integer       :: n_pg_max = HUGE(0)
     logical       :: rossby = .FALSE.
     logical       :: static = .FALSE.
     character(64) :: ad_search = 'SCAN'
     character(64) :: nad_search = 'AD'
     character(64) :: tag = ''
  end type mode_par_t

  ! Interfaces

  $if ($MPI)

  interface bcast
     module procedure bcast_0_
     module procedure bcast_1_
  end interface bcast

  interface bcast_alloc
     module procedure bcast_alloc_0_
     module procedure bcast_alloc_1_
  end interface bcast_alloc

  $endif

 ! Access specifiers

  private

  public :: mode_par_t
  public :: read_mode_par
  $if ($MPI)
  public :: bcast
  public :: bcast_alloc
  $endif

  ! Procedures

contains

  subroutine read_mode_par (unit, md_p)

    integer, intent(in)                        :: unit
    type(mode_par_t), allocatable, intent(out) :: md_p(:)

    integer                         :: n_md_p
    integer                         :: i
    integer                         :: l
    integer                         :: m
    integer                         :: n_pg_min
    integer                         :: n_pg_max
    logical                         :: rossby
    logical                         :: static
    character(LEN(md_p%ad_search))  :: ad_search
    character(LEN(md_p%nad_search)) :: nad_search
    character(LEN(md_p%tag))        :: tag
 
    namelist /mode/ l, m, n_pg_min, n_pg_max, rossby, static, ad_search, nad_search, tag

    ! Count the number of mode namelists

    rewind(unit)

    n_md_p = 0

    count_loop : do
       read(unit, NML=mode, END=100)
       n_md_p = n_md_p + 1
    end do count_loop

100 continue

    ! Read mode parameters

    rewind(unit)

    allocate(md_p(n_md_p))

    read_loop : do i = 1, n_md_p

       ! Set default values

       md_p(i) = mode_par_t()

       l = md_p(i)%l
       m = md_p(i)%m
       n_pg_min = md_p(i)%n_pg_min
       n_pg_max = md_p(i)%n_pg_max
       static = md_p(i)%static
       rossby = md_p(i)%rossby
       ad_search = md_p(i)%ad_search
       nad_search = md_p(i)%nad_search
       tag = md_p(i)%tag

       ! Read the namelist

       read(unit, NML=mode)

       ! Store read values

       md_p(i)%l = l
       md_p(i)%m = m
       md_p(i)%n_pg_min = n_pg_min
       md_p(i)%n_pg_max = n_pg_max
       md_p(i)%static = static
       md_p(i)%rossby = rossby
       md_p(i)%ad_search = ad_search
       md_p(i)%nad_search = nad_search
       md_p(i)%tag = tag

    end do read_loop

    ! Finish

    return

  end subroutine read_mode_par

  !****

  $if ($MPI)

  subroutine bcast_0_ (md_p, root_rank)

    type(mode_par_t), intent(inout) :: md_p
    integer, intent(in)             :: root_rank

    ! Broadcast the mode_par_t

    call bcast(md_p%l, root_rank)
    call bcast(md_p%m, root_rank)

    call bcast(md_p%n_pg_min, root_rank)
    call bcast(md_p%n_pg_max, root_rank)

    call bcast(md_p%static, root_rank)
    call bcast(md_p%rossby, root_rank)

    call bcast(md_p%ad_search, root_rank)
    call bcast(md_p%nad_search, root_rank)
    call bcast(md_p%tag, root_rank)

    ! Finish

    return

  end subroutine bcast_0_

  $BCAST(type(mode_par_t),1)

  $BCAST_ALLOC(type(mode_par_t),0)
  $BCAST_ALLOC(type(mode_par_t),1)

  $endif

end module gyre_mode_par
