! Incfile  : gyre_rot_factory
! Purpose  : factory procedures for r_rot_t and c_rot_t types
!
! Copyright 2013-2014 Rich Townsend
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

module gyre_rot_factory

  ! Uses

  use core_kinds

  use gyre_model
  use gyre_modepar
  use gyre_oscpar
  use gyre_rot

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Interfaces

  interface r_rot_t
     module procedure r_rot_t_
  end interface r_rot_t

  interface c_rot_t
     module procedure c_rot_t_
  end interface c_rot_t

  ! Access specifiers

  private

  public :: r_rot_t
  public :: c_rot_t

  ! Procedures

contains

  $define $ROT_T $sub

  $local $T $1

  function ${T}_rot_t_ (ml, mp, op) result (rt)

    use gyre_dopp_rot
    use gyre_null_rot
    use gyre_trad_rot

    class(model_t), pointer, intent(in) :: ml
    type(modepar_t), intent(in)         :: mp
    type(oscpar_t), intent(in)          :: op
    class(${T}_rot_t), allocatable      :: rt
    
    ! Create a ${T}_rot_t

    select case (op%rotation_method)
    case ('DOPPLER')
       allocate(rt, SOURCE=${T}_dopp_rot_t(ml, mp))
    case ('NULL')
       allocate(rt, SOURCE=${T}_null_rot_t(mp))
    case ('TRAD')
       allocate(rt, SOURCE=${T}_trad_rot_t(ml, mp))
    case default
       $ABORT(Invalid rotation_method)
    end select

    ! Finish

    return

  end function ${T}_rot_t_

  $endsub

  $ROT_T(r)
  $ROT_T(c)

end module gyre_rot_factory
