! Module   : gyre_discfunc
! Purpose  : discriminant root finding
!
! Copyright 2013 Rich Townsend
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

module gyre_discfunc

  ! Uses

  use core_kinds

  use gyre_bvp
  use gyre_ext_arith
  use gyre_ext_func

  ! This should not be needed, but it solves unresolved symbol issues
  ! with gfortran
  use gyre_mode

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type, extends(ext_func_t) :: discfunc_t
     private
     class(bvp_t), pointer :: bp
   contains 
     private
     procedure, public :: init
     procedure, public :: eval_ec
  end type discfunc_t

  ! Access specifiers

  private

  public :: discfunc_t

  ! Procedures

contains

  subroutine init (this, bp)

    class(discfunc_t), intent(out)   :: this
    class(bvp_t), intent(in), target :: bp

    ! Initialize the discfunc

    this%bp => bp

    ! Finish

    return

  end subroutine init

!****

  function eval_ec (this, ez) result (f_ez)

    class(discfunc_t), intent(inout) :: this
    type(ext_complex_t), intent(in)  :: ez
    type(ext_complex_t)              :: f_ez

    ! Evaluate the discriminant

    f_ez = this%bp%discrim(CMPLX(ez))

    ! Finish

    return

  end function eval_ec

end module gyre_discfunc