! Module   : gyre_cad_trans
! Purpose  : adiabatic variables/equations transformations (complex)
!
! Copyright 2017 Rich Townsend
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

module gyre_cad_trans

  ! Uses

  use core_kinds

  use gyre_linalg
  use gyre_model
  use gyre_model_util
  use gyre_mode_par
  use gyre_osc_par
  use gyre_point
  use gyre_rot
  use gyre_rot_factory

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Parameter definitions

  integer, parameter :: GYRE_SET = 0
  integer, parameter :: DZIEM_SET = 1
  integer, parameter :: JCD_SET = 2
  integer, parameter :: LAGP_SET = 3

  integer, parameter :: J_V_2 = 1
  integer, parameter :: J_DV_2 = 2
  integer, parameter :: J_U = 3
  integer, parameter :: J_DU = 4
  integer, parameter :: J_C_1 = 5
  integer, parameter :: J_DC_1 = 6

  integer, parameter :: J_LAST = J_DC_1

  ! Derived-type definitions

  type :: cad_trans_t
     private
     class(model_t), pointer     :: ml => null()
     class(c_rot_t), allocatable :: rt
     real(WP), allocatable       :: coeffs(:,:)
     integer                     :: l
     integer                     :: set
     integer                     :: n_e
   contains
     private
     procedure, public :: stencil
     procedure, public :: trans_eqns
     procedure, public :: trans_cond
     procedure, public :: trans_vars
     procedure         :: G_
     procedure         :: G_dziem_
     procedure         :: G_jcd_
     procedure         :: G_lagp_
     procedure         :: H_
     procedure         :: H_dziem_
     procedure         :: H_jcd_
     procedure         :: H_lagp_
     procedure         :: dH_
     procedure         :: dH_jcd_
     procedure         :: dH_lagp_
  end type ad_trans_t

  ! Interfaces

  interface ad_trans_t
     module procedure ad_trans_t_
  end interface ad_trans_t

  ! Access specifiers

  private

  public :: ad_trans_t

  ! Procedures

contains

  function cad_trans_t_ (ml, pt_i, md_p, os_p) result (tr)

    class(model_t), pointer, intent(in) :: ml
    type(point_t), intent(in)           :: pt_i
    type(mode_par_t), intent(in)        :: md_p
    type(osc_par_t), intent(in)         :: os_p
    type(cad_trans_t)                   :: tr

    ! Construct the ad_trans_t

    tr%ml => ml

    allocate(tr%rt, SOURCE=c_rot_t(ml, pt_i, md_p, os_p))

    select case (os_p%variables_set)
    case ('GYRE')
       tr%set = GYRE_SET
    case ('DZIEM')
       tr%set = DZIEM_SET
    case ('JCD')
       tr%set = JCD_SET
    case ('LAGP')
       tr%set = LAGP_SET
    case default
       $ABORT(Invalid variables_set)
    end select

    tr%l = md_p%l

    tr%n_e = 4

    ! Finish

    return

  end function ad_trans_t_

  !****

  subroutine stencil (this, pt)

    class(cad_trans_t), intent(inout) :: this
    type(point_t), intent(in)         :: pt(:)

    integer :: n_s
    integer :: i

    ! Calculate coefficients at the stencil points

    call check_model(this%ml, [I_V_2,I_U,I_C_1])

    n_s = SIZE(pt)

    if (ALLOCATED(this%coeffs)) deallocate(this%coeffs)
    allocate(this%coeffs(n_s,J_LAST))

    do i = 1, n_s
       if (this%ml%is_vacuum(pt(i))) then
          this%coeffs(i,J_V_2) = HUGE(0._WP)
          this%coeffs(i,J_DV_2) = HUGE(0._WP)
          this%coeffs(i,J_DU) = -HUGE(0._WP)
       else
          this%coeffs(i,J_V_2) = this%ml%coeff(I_V_2, pt(i))
          this%coeffs(i,J_DV_2) = this%ml%dcoeff(I_V_2, pt(i))
          this%coeffs(i,J_DU) = this%ml%dcoeff(I_U, pt(i))
       endif
       this%coeffs(i,J_U) = this%ml%coeff(I_U, pt(i))
       this%coeffs(i,J_C_1) = this%ml%coeff(I_C_1, pt(i))
       this%coeffs(i,J_DC_1) = this%ml%dcoeff(I_C_1, pt(i))
    end do

    ! Set up stencil for the rt component

    call this%rt%stencil(pt)

    ! Finish

    return

  end subroutine stencil

  !****

  subroutine trans_eqns (this, xA, i, omega, from)

    class(cad_trans_t), intent(in) :: this
    complex(WP), intent(inout)     :: xA(:,:)
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    logical, intent(in), optional  :: from

    logical     :: from_
    complex(WP) :: G(this%n_e,this%n_e)
    complex(WP) :: H(this%n_e,this%n_e)
    complex(WP) :: dH(this%n_e,this%n_e)

    $CHECK_BOUNDS(SIZE(xA, 1),this%n_e)
    $CHECK_BOUNDS(SIZE(xA, 2),this%n_e)

    if (PRESENT(from)) then
       from_ = from
    else
       from_ = .TRUE.
    endif

    ! Transform equations to/from GYRE's canonical form

    if (from_) then

       ! Convert from

       if (this%set /= GYRE_SET) then
          G = this%G_(i, omega)
          H = this%H_(i, omega)
          dH = this%dH_(i, omega)
          xA = MATMUL(G, MATMUL(xA, H) - dH)
       endif

    else

       ! Convert to

       $ABORT(Not currently supported)

    end if

    ! Finish

    return

  end subroutine trans_eqns
  
  !****

  subroutine trans_cond (this, C, i, omega, from)

    class(cad_trans_t), intent(in) :: this
    complex(WP), intent(inout)     :: C(:,:)
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    logical, intent(in), optional  :: from

    logical     :: from_
    complex(WP) :: G(this%n_e,this%n_e)
    complex(WP) :: H(this%n_e,this%n_e)

    $CHECK_BOUNDS(SIZE(C, 2),this%n_e)

    if (PRESENT(from)) then
       from_ = from
    else
       from_ = .TRUE.
    endif

    ! Transform boundary/match conditions to/from GYRE's canonical
    ! form

    if (from_) then

       ! Convert from

       if (this%set /= GYRE_SET) then
          H = this%H_(i, omega)
          C = MATMUL(C, H)
       endif

    else

       ! Convert to

       if (this%set /= GYRE_SET) then
          G = this%G_(i, omega)
          C = MATMUL(C, G)
       endif

    end if

    ! Finish

    return

  end subroutine trans_cond

  !****

  subroutine trans_vars (this, y, i, omega, from)

    class(cad_trans_t), intent(in) :: this
    complex(WP), intent(inout)     :: y(:)
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    logical, intent(in), optional  :: from

    logical     :: from_
    complex(WP) :: G(this%n_e,this%n_e)
    complex(WP) :: H(this%n_e,this%n_e)

    $CHECK_BOUNDS(SIZE(y),this%n_e)

    if (PRESENT(from)) then
       from_ = from
    else
       from_ = .TRUE.
    endif

    ! Convert variables to/from GYRE's canonical form

    if (from_) then

       ! Convert from

       if (this%set /= GYRE_SET) then
          G = this%G_(i, omega)
          y = MATMUL(G, y)
       endif

    else

       ! Convert to

       if (this%set /= GYRE_SET) then
          H = this%H_(i, omega)
          y = MATMUL(H, y)
       endif

    end if

    ! Finish

    return

  end subroutine trans_vars

  !****

  function G_ (this, i, omega) result (G)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: G(4,4)

    ! Evaluate the transformation matrix to convert variables from the
    ! canonical form

    select case (this%set)
    case (DZIEM_SET)
       G = this%G_dziem_(i, omega)
    case (JCD_SET)
       G = this%G_jcd_(i, omega)
    case (LAGP_SET)
       G = this%G_lagp_(i, omega)
    case default
       $ABORT(Invalid set)
    end select

    ! Finish

    return

  end function G_

  !****

  function G_dziem_ (this, i, omega) result (G)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: G(this%n_e,this%n_e)

    ! Evaluate the transformation matrix to convert DZIEM variables
    ! from GYRE's canonical form

    ! Set up the matrix
      
    G(1,1) = 1._WP
    G(1,2) = 0._WP
    G(1,3) = 0._WP
    G(1,4) = 0._WP
          
    G(2,1) = 0._WP
    G(2,2) = 1._WP
    G(2,3) = 1._WP
    G(2,4) = 0._WP
          
    G(3,1) = 0._WP
    G(3,2) = 0._WP
    G(3,3) = 1._WP
    G(3,4) = 0._WP

    G(4,1) = 0._WP
    G(4,2) = 0._WP
    G(4,3) = 0._WP
    G(4,4) = 1._WP

    ! Finish

    return

  end function G_dziem_

  !****

  function G_jcd_ (this, i, omega) result (G)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: G(this%n_e,this%n_e)

    complex(WP) :: lambda
    complex(WP) :: omega_c

    ! Evaluate the transformation matrix to convert JCD variables from
    ! GYRE's canonical form

    associate( &
         U => this%coeffs(i,J_U), &
         c_1 => this%coeffs(i,J_C_1))

      lambda = this%rt%lambda(i, omega)

      omega_c = this%rt%omega_c(i, omega)

      ! Set up the matrix
      
      if (this%l /= 0) then

         G(1,1) = 1._WP
         G(1,2) = 0._WP
         G(1,3) = 0._WP
         G(1,4) = 0._WP
         
         G(2,1) = 0._WP
         G(2,2) = lambda/(c_1*omega_c**2)
         G(2,3) = lambda/(c_1*omega_c**2)
         G(2,4) = 0._WP
         
         G(3,1) = 0._WP
         G(3,2) = 0._WP
         G(3,3) = -1._WP
         G(3,4) = 0._WP

         G(4,1) = 0._WP
         G(4,2) = 0._WP
         G(4,3) = -(1._WP - U)
         G(4,4) = -1._WP

      else

         G(1,1) = 1._WP
         G(1,2) = 0._WP
         G(1,3) = 0._WP
         G(1,4) = 0._WP
         
         G(2,1) = 0._WP
         G(2,2) = 1._WP/(c_1*omega_c**2)
         G(2,3) = 1._WP/(c_1*omega_c**2)
         G(2,4) = 0._WP

         G(3,1) = 0._WP
         G(3,2) = 0._WP
         G(3,3) = -1._WP
         G(3,4) = 0._WP

         G(4,1) = 0._WP
         G(4,2) = 0._WP
         G(4,3) = -(1._WP - U)
         G(4,4) = -1._WP

      endif

    end associate

    ! Finish

    return

  end function G_jcd_

  !****

  function G_lagp_ (this, i, omega) result (G)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: G(this%n_e,this%n_e)

    ! Evaluate the transformation matrix to convert LAGP variables
    ! from GYRE's canonical form

    associate( &
         V_2 => this%coeffs(i,J_V_2))

      ! Set up the matrix

      G(1,1) = 1._WP
      G(1,2) = 0._WP
      G(1,3) = 0._WP
      G(1,4) = 0._WP

      G(2,1) = -V_2
      G(2,2) = V_2
      G(2,3) = 0._WP
      G(2,4) = 0._WP

      G(3,1) = 0._WP
      G(3,2) = 0._WP
      G(3,3) = 1._WP
      G(3,4) = 0._WP

      G(4,1) = 0._WP
      G(4,2) = 0._WP
      G(4,3) = 0._WP
      G(4,4) = 1._WP

    end associate

    ! Finish

    return

  end function G_lagp_

  !****

  function H_ (this, i, omega) result (H)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: H(4,4)

    ! Evaluate the transformation matrix to convert variables to
    ! GYRE's canonical form

    select case (this%set)
    case (DZIEM_SET)
       H = this%H_dziem_(i, omega)
    case (JCD_SET)
       H = this%H_jcd_(i, omega)
    case (LAGP_SET)
       H = this%H_lagp_(i, omega)
    case default
       $ABORT(Invalid set)
    end select

    ! Finish

    return

  end function H_

  !****

  function H_dziem_ (this, i, omega) result (H)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: H(this%n_e,this%n_e)

    ! Evaluate the transformation matrix to convert DZIEM variables to
    ! GYRE's canonical form

    ! Set up the matrix
      
    H(1,1) = 1._WP
    H(1,2) = 0._WP
    H(1,3) = 0._WP
    H(1,4) = 0._WP
       
    H(2,1) = 0._WP
    H(2,2) = 1._WP
    H(2,3) = -1._WP
    H(2,4) = 0._WP

    H(3,1) = 0._WP
    H(3,2) = 0._WP
    H(3,3) = 1._WP
    H(3,4) = 0._WP

    H(4,1) = 0._WP
    H(4,2) = 0._WP
    H(4,3) = 0._WP
    H(4,4) = 1._WP
    
    ! Finish

    return

  end function H_dziem_

  !****

  function H_jcd_ (this, i, omega) result (H)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: H(this%n_e,this%n_e)

    complex(WP) :: lambda
    complex(WP) :: omega_c

    ! Evaluate the transformation matrix to convert JCD variables to
    ! GYRE's canonical form

    associate( &
         U => this%coeffs(i,J_U), &
         c_1 => this%coeffs(i,J_C_1))

      lambda = this%rt%lambda(i, omega)

      omega_c = this%rt%omega_c(i, omega)

      ! Set up the matrix
      
      if (this%l /= 0._WP) then

         H(1,1) = 1._WP
         H(1,2) = 0._WP
         H(1,3) = 0._WP
         H(1,4) = 0._WP
       
         H(2,1) = 0._WP
         H(2,2) = c_1*omega_c**2/lambda
         H(2,3) = 1._WP
         H(2,4) = 0._WP

         H(3,1) = 0._WP
         H(3,2) = 0._WP
         H(3,3) = -1._WP
         H(3,4) = 0._WP

         H(4,1) = 0._WP
         H(4,2) = 0._WP
         H(4,3) = 1._WP - U
         H(4,4) = -1._WP

      else

         H(1,1) = 1._WP
         H(1,2) = 0._WP
         H(1,3) = 0._WP
         H(1,4) = 0._WP

         H(2,1) = 0._WP
         H(2,2) = c_1*omega_c**2
         H(2,3) = 1._WP
         H(2,4) = 0._WP

         H(3,1) = 0._WP
         H(3,2) = 0._WP
         H(3,3) = -1._WP
         H(3,4) = 0._WP

         H(4,1) = 0._WP
         H(4,2) = 0._WP
         H(4,3) = 1._WP - U
         H(4,4) = -1._WP

      endif

    end associate

    ! Finish

    return

  end function H_jcd_

  !****

  function H_lagp_ (this, i, omega) result (H)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: H(this%n_e,this%n_e)

    ! Evaluate the transformation matrix to convert LAGP variables to
    ! GYRE's canonical form

    associate( &
         V_2 => this%coeffs(i,J_V_2))

      ! Set up the matrix

      H(1,1) = 1._WP
      H(1,2) = 0._WP
      H(1,3) = 0._WP
      H(1,4) = 0._WP
      
      H(2,1) = 1._WP
      H(2,2) = 1._WP/V_2
      H(2,3) = 0._WP
      H(2,4) = 0._WP

      H(3,1) = 0._WP
      H(3,2) = 0._WP
      H(3,3) = 1._WP
      H(3,4) = 0._WP

      H(4,1) = 0._WP
      H(4,2) = 0._WP
      H(4,3) = 0._WP
      H(4,4) = 1._WP

    end associate

    ! Finish

    return

  end function H_lagp_

  !****

  function dH_ (this, i, omega) result (dH)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: dH(4,4)

    ! Evaluate the derivative x dH/dx of the transformation matrix H

    select case (this%set)
    case (GYRE_SET)
       dH = 0._WP
    case (DZIEM_SET)
       dH = 0._WP
    case (JCD_SET)
       dH = this%dH_jcd_(i, omega)
    case (LAGP_SET)
       dH = this%dH_lagp_(i, omega)
    case default
       $ABORT(Invalid set)
    end select

    ! Finish

    return

  end function dH_

  !****

  function dH_jcd_ (this, i, omega) result (dH)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: dH(this%n_e,this%n_e)

    complex(WP) :: lambda
    complex(WP) :: omega_c

    ! Evaluate the derivative x dH/dx of the JCD-variables
    ! transformation matrix H

    associate( &
      U => this%coeffs(i,J_U), &
      dU => this%coeffs(i,J_DU), &
      c_1 => this%coeffs(i,J_C_1), &
      dc_1 => this%coeffs(i,J_DC_1))

      lambda = this%rt%lambda(i, omega)

      omega_c = this%rt%omega_c(i, omega)

      ! Set up the matrix (nb: the derivatives of omega_c and lambda
      ! are neglected; this is incorrect when rotation is non-zero)
      
      if (this%l /= 0._WP) then

         dH(1,1) = 0._WP
         dH(1,2) = 0._WP
         dH(1,3) = 0._WP
         dH(1,4) = 0._WP
       
         dH(2,1) = 0._WP
         dH(2,2) = c_1*dc_1*omega_c**2/lambda
         dH(2,3) = 0._WP
         dH(2,4) = 0._WP

         dH(3,1) = 0._WP
         dH(3,2) = 0._WP
         dH(3,3) = 0._WP
         dH(3,4) = 0._WP
         
         dH(4,1) = 0._WP
         dH(4,2) = 0._WP
         dH(4,3) = -U*dU
         dH(4,4) = 0._WP

      else

         dH(1,1) = 0._WP
         dH(1,2) = 0._WP
         dH(1,3) = 0._WP
         dH(1,4) = 0._WP
         
         dH(2,1) = 0._WP
         dH(2,2) = c_1*dc_1*omega_c**2
         dH(2,3) = 0._WP
         dH(2,4) = 0._WP

         dH(3,1) = 0._WP
         dH(3,2) = 0._WP
         dH(3,3) = 0._WP
         dH(3,4) = 0._WP

         dH(4,1) = 0._WP
         dH(4,2) = 0._WP
         dH(4,3) = -U*dU
         dH(4,4) = 0._WP

      endif

    end associate

    ! Finish

    return

  end function dH_jcd_

  !****

  function dH_lagp_ (this, i, omega) result (dH)

    class(cad_trans_t), intent(in) :: this
    integer, intent(in)            :: i
    complex(WP), intent(in)        :: omega
    complex(WP)                    :: dH(this%n_e,this%n_e)

    ! Evaluate the derivative x dH/dx of the LAGP-variables
    ! transformation matrix H

    associate( &
         V_2 => this%coeffs(i,J_V_2), &
         dV_2 => this%coeffs(i,J_DV_2))

      ! Set up the matrix

      dH(1,1) = 0._WP
      dH(1,2) = 0._WP
      dH(1,3) = 0._WP
      dH(1,4) = 0._WP

      dH(2,1) = 0._WP
      dH(2,2) = -dV_2/V_2
      dH(2,3) = 0._WP
      dH(2,4) = 0._WP

      dH(3,1) = 0._WP
      dH(3,2) = 0._WP
      dH(3,3) = 0._WP
      dH(3,4) = 0._WP

      dH(4,1) = 0._WP
      dH(4,2) = 0._WP
      dH(4,3) = 0._WP
      dH(4,4) = 0._WP

    end associate

    ! Finish

    return

  end function dH_lagp_

end module gyre_ad_trans
