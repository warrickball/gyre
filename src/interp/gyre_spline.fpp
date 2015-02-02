! Module   : gyre_spline
! Purpose  : cubic spline interpolators
!
! Copyright 2015 Rich Townsend
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

module gyre_spline

  ! Uses

  use core_kinds
  $if ($HDF5)
  use core_hgroup
  $endif
  use core_linalg
  use core_parallel
  use core_order

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type spline_t
     private
     real(WP), allocatable :: x_(:)     ! Abscissa
     real(WP), allocatable :: f_(:)     ! Ordinate
     real(WP), allocatable :: df_dx_(:) ! First derivatives
     integer               :: n         ! Number of points
   contains
     private
     procedure         :: x_n_
     generic, public   :: x => x_n_
     procedure, public :: x_min => x_min_
     procedure, public :: x_max => x_max_
     procedure         :: f_1_
     procedure         :: f_v_
     procedure         :: f_n_
     generic, public   :: f => f_1_, f_v_, f_n_
     procedure         :: df_dx_1_
     procedure         :: df_dx_v_
     procedure         :: df_dx_n_
     generic, public   :: df_dx => df_dx_1_, df_dx_v_, df_dx_n_
     procedure         :: int_f_n_
     generic, public   :: int_f => int_f_n_
  end type spline_t

  ! Interfaces

  interface spline_t
     module procedure spline_t_
     module procedure spline_t_eval_derivs_
     module procedure spline_t_y_func_
  end interface spline_t

  $if ($HDF5)
  interface read
     module procedure read_
  end interface read
  interface write
     module procedure write_
  end interface write
  $endif

  $if ($MPI)
 interface bcast
     module procedure bcast_0_
     module procedure bcast_1_
     module procedure bcast_2_
     module procedure bcast_3_
     module procedure bcast_4_
  end interface bcast
  interface bcast_alloc
     module procedure bcast_alloc_0_
     module procedure bcast_alloc_1_
     module procedure bcast_alloc_2_
     module procedure bcast_alloc_3_
     module procedure bcast_alloc_4_
  end interface bcast_alloc
  $endif

  ! Access specifiers

  private

  public :: spline_t
  $if ($HDF5)
  public :: read
  public :: write
  $endif
  $if ($MPI)
  public :: bcast
  public :: bcast_alloc
  $endif

  ! Procedures

contains

  function spline_t_ (x, f, df_dx) result (sp)

    real(WP), intent(in) :: x(:)
    real(WP), intent(in) :: f(:)
    real(WP), intent(in) :: df_dx(:)
    type(spline_t)       :: sp
    
    $CHECK_BOUNDS(SIZE(f),SIZE(x))
    $CHECK_BOUNDS(SIZE(df_dx),SIZE(x))

    $ASSERT(ALL(x(2:) > x(:SIZE(x)-1)),Non-monotonic abscissa)

    ! Construct the spline_t

    sp%x_ = x
    sp%f_ = f

    sp%df_dx_ = df_dx

    sp%n = SIZE(x)

    ! Finish

    return

  end function spline_t_
  
!****

  function spline_t_eval_derivs_ (x, f, deriv_type, df_dx_a, df_dx_b) result (sp)

    real(WP), intent(in)           :: x(:)
    real(WP), intent(in)           :: f(:)
    character(*), intent(in)       :: deriv_type
    real(WP), optional, intent(in) :: df_dx_a
    real(WP), optional, intent(in) :: df_dx_b
    type(spline_t)                 :: sp

    real(WP) :: df_dx(SIZE(x))

    $CHECK_BOUNDS(SIZE(f),SIZE(x))

    ! Construct the spline_t, with derivatives calculated according to
    ! deriv_type

    select case (deriv_type)
    case ('NATURAL')
       df_dx = natural_df_dx_(x, f, df_dx_a, df_dx_b)
    case('FINDIFF')
       df_dx = findiff_df_dx_(x, f, df_dx_a, df_dx_b)
    case('MONO')
       df_dx = mono_df_dx_(x, f, df_dx_a, df_dx_b)
    case default
       $ABORT(Invalid deriv_type)
    end select

    sp = spline_t(x, f, df_dx)

    ! Finish

    return

  end function spline_t_eval_derivs_

!****

  function spline_t_y_func_ (x_a, x_b, f_func, f_tol, deriv_type, relative_tol, df_dx_a, df_dx_b) result (sp)

    real(WP), intent(in)           :: x_a
    real(WP), intent(in)           :: x_b
    interface
       function f_func (x) result (f)
         use core_kinds
         implicit none
         real(WP), intent(in) :: x
         real(WP)             :: f
       end function f_func
    end interface
    real(WP), optional, intent(in) :: f_tol
    character(*), intent(in)       :: deriv_type
    logical, optional, intent(in)  :: relative_tol
    real(WP), optional, intent(in) :: df_dx_a
    real(WP), optional, intent(in) :: df_dx_b
    type(spline_t)                 :: sp

    real(WP), parameter :: EPS = 4._WP*EPSILON(0._WP)

    logical               :: relative_tol_
    integer               :: n
    real(WP), allocatable :: x(:)
    real(WP), allocatable :: f(:)
    real(WP), allocatable :: x_dbl(:)
    real(WP), allocatable :: f_dbl(:)
    integer               :: j
    real(WP), allocatable :: err(:)
    real(WP), allocatable :: err_thresh(:)

    if (PRESENT(relative_tol)) then
       relative_tol_ = relative_tol
    else
       relative_tol_ = .FALSE.
    endif

    ! Construct the spline_t by sampling the function f(x) until the
    ! residuals drop below f_tol

    ! Initialize n to the smallest possible value

    n = 2

    x = [x_a,x_b]
    f = [f_func(x_a),f_func(x_b)]

    ! Now increase n until the desired tolerance is reached

    n_loop : do

       ! Construct the spline

       sp = spline_t(x, f, deriv_type, df_dx_a=df_dx_a, df_dx_b=df_dx_b)

       ! Calculate x and y at double the resolution

       allocate(x_dbl(2*n-1))
       allocate(f_dbl(2*n-1))

       x_dbl(1::2) = x
       x_dbl(2::2) = 0.5_WP*(x(:n-1) + x(2:))

       f_dbl(1::2) = f

       do j = 1, n-1
          f_dbl(2*j) = f_func(x_dbl(2*j))
       end do

       ! Examine how well the spline fits the double-res data

       err = ABS(sp%f(x_dbl(2::2)) - f_dbl(2::2))

       if (relative_tol_) then
          err_thresh = (EPS + f_tol)*ABS(f_dbl(2::2))
       else
          err_thresh = EPS*ABS(f_dbl(2::2)) + f_tol
       endif

       if (ALL(err <= err_thresh)) exit n_loop

       ! Loop around

       call MOVE_ALLOC(x_dbl, x)
       call MOVE_ALLOC(f_dbl, f)

       n = 2*n-1

    end do n_loop
       
    ! Finish

    return

  end function spline_t_y_func_

!****

  $if ($HDF5)

  subroutine read_ (hg, sp)

    type(hgroup_t), intent(inout) :: hg
    type(spline_t), intent(out)   :: sp

    real(WP), allocatable :: x(:)
    real(WP), allocatable :: f(:)
    real(WP), allocatable :: df_dx(:)

    ! Read the spline_t

    call read_dset_alloc(hg, 'x', x)
    call read_dset_alloc(hg, 'f', f)
    call read_dset_alloc(hg, 'df_dx', df_dx)

    sp = spline_t(x, f, df_dx)

    ! Finish

    return

  end subroutine read_

!****

  subroutine write_ (hg, sp)

    type(hgroup_t), intent(inout) :: hg
    type(spline_t), intent(in)    :: sp

    ! Write the spline_t

    call write_attr(hg, 'n', sp%n)

    call write_dset(hg, 'x', sp%x_)
    call write_dset(hg, 'f', sp%f_)
    call write_dset(hg, 'df_dx', sp%df_dx_)

    ! Finish

    return

  end subroutine write_

  $endif

!****

  $if ($MPI)

  subroutine bcast_0_ (sp, root_rank)

    class(spline_t), intent(inout) :: sp
    integer, intent(in)            :: root_rank

    ! Broadcast the spline

    call bcast(sp%n, root_rank)

    call bcast_alloc(sp%x, root_rank)
    call bcast_alloc(sp%f_, root_rank)
    call bcast_alloc(sp%df_dx_, root_rank)

    ! Finish

    return

  end subroutine bcast_0_

  $BCAST(type(spline_t),1)
  $BCAST(type(spline_t),2)
  $BCAST(type(spline_t),3)
  $BCAST(type(spline_t),4)

  $BCAST_ALLOC(type(spline_t),0)
  $BCAST_ALLOC(type(spline_t),1)
  $BCAST_ALLOC(type(spline_t),2)
  $BCAST_ALLOC(type(spline_t),3)
  $BCAST_ALLOC(type(spline_t),4)

  $endif

!****

  function x_n_ (this) result (x)

    class(spline_t), intent(in) :: this
    real(WP)                    :: x(this%n)

    ! Return the abscissa points

    x = this%x_

    return

  end function x_n_

!****

  function x_min_ (this) result (x_min)

    class(spline_t), intent(in) :: this
    real(WP)                    :: x_min

    ! Return the minimum abscissa point

    x_min = this%x_(1)

    ! FInish

    return

  end function x_min_

!****

  function x_max_ (this) result (x_max)

    class(spline_t), intent(in) :: this
    real(WP)                    :: x_max

    ! Return the maximum abscissa point

    x_max = this%x_(this%n)

    ! FInish

    return

  end function x_max_

!****

  function f_1_ (this, x) result (f)

    class(spline_t), intent(in) :: this
    real(WP), intent(in)        :: x
    real(WP)                    :: f

    integer  :: i
    real(WP) :: h
    real(WP) :: w

    ! Interpolate f at a single point

    ! Set up the bracketing index

    i = 1

    call locate(this%x_, x, i)
    $ASSERT(i > 0 .AND. i < this%n,Out-of-bounds interpolation)

    ! Set up the interpolation weights

    h = this%x_(i+1) - this%x_(i)
    w = (x - this%x_(i))/h

    ! Do the interpolation

    f =    this%f_(i  )*phi_(1._WP-w) + &
           this%f_(i+1)*phi_(w      ) - &
     h*this%df_dx_(i  )*psi_(1._WP-w) + &
     h*this%df_dx_(i+1)*psi_(w      )

    ! Finish

    return

  end function f_1_

!****

  function f_v_ (this, x) result (f)

    class(spline_t), intent(in) :: this
    real(WP), intent(in)        :: x(:)
    real(WP)                    :: f(SIZE(x))

    integer  :: i
    integer  :: j
    real(WP) :: h
    real(WP) :: w

    ! Interpolate f at a vector of points

    i = 1

    x_loop : do j = 1,SIZE(x)

       ! Update the bracketing index

       call locate(this%x_, x(j), i)
       $ASSERT(i > 0 .AND. i < this%n,Out-of-bounds interpolation)

       ! Set up the interpolation weights

       h = this%x_(i+1) - this%x_(i)
       w = (x(j) - this%x_(i))/h

       ! Do the interpolation

       f(j) = this%f_(i  )*phi_(1._WP-w) + &
              this%f_(i+1)*phi_(w      ) - &
        h*this%df_dx_(i  )*psi_(1._WP-w) + &
        h*this%df_dx_(i+1)*psi_(w      )

    end do x_loop

    ! Finish

    return

  end function f_v_

!****

  function f_n_ (this) result (f)

    class(spline_t), intent(in) :: this
    real(WP)                    :: f(this%n)

    ! Return f at abscissa points

    f = this%f_

    ! Finish

  end function f_n_

!****

  function df_dx_1_ (this, x) result (df_dx)

    class(spline_t), intent(in) :: this
    real(WP), intent(in)        :: x
    real(WP)                    :: df_dx

    integer  :: i
    real(WP) :: h
    real(WP) :: w

    ! Differentiate f at a single point

    ! Set up the bracketing index

    i = 1

    call locate(this%x_, x, i)
    $ASSERT(i > 0 .AND. i < this%n,Out-of-bounds interpolation)

    ! Set up the interpolation weights

    h = this%x_(i+1) - this%x_(i)
    w = (x - this%x_(i))/h

    ! Do the interpolation

    df_dx =    -this%f_(i  )*dphi_dt_(1._WP-w)/h + &
                this%f_(i+1)*dphi_dt_(w      )/h + &
            this%df_dx_(i  )*dpsi_dt_(1._WP-w) + &
            this%df_dx_(i+1)*dpsi_dt_(w      )

    ! Finish

    return

  end function df_dx_1_

!****

  function df_dx_v_ (this, x) result (df_dx)

    class(spline_t), intent(in) :: this
    real(WP), intent(in)        :: x(:)
    real(WP)                    :: df_dx(SIZE(x))

    integer  :: i
    integer  :: j
    real(WP) :: h
    real(WP) :: w

    ! Differentiate f at a vector of points

    i = 1

    x_loop : do j = 1,SIZE(x)

       ! Update the bracketing index

       call locate(this%x_, x(j), i)
       $ASSERT(i > 0 .AND. i < this%n,Out-of-bounds interpolation)

       ! Set up the interpolation weights

       h = this%x_(i+1) - this%x_(i)
       w = (x(j) - this%x_(i))/h

       ! Do the interpolation

       df_dx(j) = -this%f_(i  )*dphi_dt_(1._WP-w)/h + &
                   this%f_(i+1)*dphi_dt_(w      )/h + &
               this%df_dx_(i  )*dpsi_dt_(1._WP-w) + &
               this%df_dx_(i+1)*dpsi_dt_(w      )

    end do x_loop

    ! Finish

    return

  end function df_dx_v_

!****

  function df_dx_n_ (this) result (df_dx)

    class(spline_t), intent(in) :: this
    real(WP)                    :: df_dx(this%n)

    ! Return df_dx at abscissa points

    df_dx = this%df_dx_

    ! Finish

    return

  end function df_dx_n_

!****

  function int_f_n_ (this) result (int_f)

    class(spline_t), intent(in) :: this
    real(WP)                    :: int_f(this%n)

    integer  :: i
    real(WP) :: h

    ! Integrate f across the full domain

    int_f(1) = 0._WP

    x_loop : do i = 1,this%n-1
       
       h = this%x_(i+1) - this%x_(i)

       int_f(i+1) = int_f(i) + (this%f_(i) + this%f_(i+1))*h/2._WP - &
                               (this%df_dx_(i+1) - this%df_dx_(i))*h**2/12._WP

    end do x_loop

    ! Finish

    return

  end function int_f_n_

!****

  function natural_df_dx_ (x, f, df_dx_a, df_dx_b) result (df_dx)

    real(WP), intent(in)           :: x(:)
    real(WP), intent(in)           :: f(:)
    real(WP), intent(in), optional :: df_dx_a
    real(WP), intent(in), optional :: df_dx_b
    real(WP)                       :: df_dx(SIZE(x))

    integer  :: n
    real(WP) :: h(SIZE(x)-1)
    real(WP) :: L(SIZE(x)-1)
    real(WP) :: D(SIZE(x))
    real(WP) :: U(SIZE(x)-1)
    real(WP) :: B(SIZE(x),1)
    integer  :: info

    $CHECK_BOUNDS(SIZE(f),SIZE(x))
    
    ! Calcualte the first derivatives for a natural spline (ensuring
    ! the second derivatives are continuous)

    n = SIZE(x)

    h = x(2:) - x(:n-1)

    ! Set up the tridiagonal matrix and RHS

    ! Inner boundary

    D(1) = 1._WP
    U(1) = 0._WP

    if(PRESENT(df_dx_a)) then
       B(1,1) = df_dx_a
    else
       B(1,1) = (f(2) - f(1))/h(1)
    endif

    ! Internal points

    L(1:n-2) = 2._WP/h(1:n-2)
    D(2:n-1) = 4._WP/h(1:n-2) + 4._WP/h(2:n-1)
    U(2:n-1) = 2._WP/h(2:n-1)

    B(2:n-1,1) = -6._WP*f(1:n-2)/h(1:n-2)**2 + 6._WP*f(2:n-1)/h(1:n-2)**2 + &
                 6._WP*f(3:n  )/h(2:n-1)**2 - 6._WP*f(2:n-1)/h(2:n-1)**2

    ! Outer boundary

    L(n-1) = 0._WP
    D(n) = 1._WP

    if(PRESENT(df_dx_b)) then
       B(n,1) = df_dx_b
    else
       B(n,1) = (f(n) - f(n-1))/h(n-1)
    endif

    ! Solve the tridiagonal system

    call XGTSV(n, 1, L, D, U, B, SIZE(B, 1), info)
    $ASSERT(info == 0,Non-zero return from XTGSV)

    df_dx = B(:,1)

    ! Finish

    return

  end function natural_df_dx_

!****

  function findiff_df_dx_ (x, f, df_dx_a, df_dx_b) result (df_dx)

    real(WP), intent(in)           :: x(:)
    real(WP), intent(in)           :: f(:)
    real(WP), intent(in), optional :: df_dx_a
    real(WP), intent(in), optional :: df_dx_b
    real(WP)                       :: df_dx(SIZE(x))

    integer  :: n
    real(WP) :: h(SIZE(x)-1)
    real(WP) :: s(SIZE(x)-1)

    $CHECK_BOUNDS(SIZE(f),SIZE(x))

    ! Calculate the first derivatives via centered finite differences

    n = SIZE(x)

    h = x(2:) - x(:n-1)

    s = (f(2:) - f(:n-1))/h

    if(PRESENT(df_dx_a)) then
       df_dx(1) = df_dx_a
    else
       df_dx(1) = s(1)
    endif

    df_dx(2:n-1) = 0.5_WP*(s(1:n-2) + s(2:n-1))

    if(PRESENT(df_dx_b)) then
       df_dx(n) = df_dx_b
    else
       df_dx(n) = s(n-1)
    endif

    ! Finish

    return

  end function findiff_df_dx_

!****

  function mono_df_dx_ (x, f, df_dx_a, df_dx_b) result (df_dx)

    real(WP), intent(in)           :: x(:)
    real(WP), intent(in)           :: f(:)
    real(WP), intent(in), optional :: df_dx_a
    real(WP), intent(in), optional :: df_dx_b
    real(WP)                       :: df_dx(SIZE(x))

    integer  :: n
    real(WP) :: h(SIZE(x)-1)
    real(WP) :: s(SIZE(x)-1)
    real(WP) :: p(SIZE(x))
    integer  :: i

    $CHECK_BOUNDS(SIZE(f),SIZE(x))

    ! Calculate the first derivatives using the Steffen (1990, A&A,
    ! 239, 443) monontonicity preserving algorithm

    n = SIZE(x)

    h = x(2:) - x(:n-1)

    s = (f(2:) - f(:n-1))/h

    ! Calculate parabolic gradients

    if(PRESENT(df_dx_a)) then
       p(1) = df_dx_a
    else
       p(1) = s(1)
    endif

    p(2:n-1) = (s(1:n-2)*h(2:n-1) + s(2:n-1)*h(1:n-2))/(h(1:n-2) + h(2:n-1))

    if(PRESENT(df_dx_b)) then
       p(n) = df_dx_b
    else
       p(n) = s(n-1)
    endif

    ! Calculate monotonic gradients

    df_dx(1) = p(1)

    do i = 2,n-1
       df_dx(i) = (SIGN(1._WP, s(i-1)) + SIGN(1._WP, s(i)))* &
                  MIN(ABS(s(i-1)), ABS(s(i)), 0.5*ABS(p(i)))
    end do

    df_dx(n) = p(n)

    ! Finish

    return

  end function mono_df_dx_

!****

  function phi_ (t)

    real(WP), intent(in) :: t
    real(WP)             :: phi_

    ! Evaluate the phi basis function

    phi_ = 3._WP*t**2 - 2._WP*t**3

    return

  end function phi_

!****

  function psi_ (t)

    real(WP), intent(in) :: t
    real(WP)             :: psi_

    ! Evaluate the psi basis function 

    psi_ = t**3 - t**2

    return

  end function psi_

!****

  function dphi_dt_ (t)

    real(WP), intent(in) :: t
    real(WP)             :: dphi_dt_

    ! Evaluate the first derivative of the phi basis function

    dphi_dt_ = 6._WP*t - 6._WP*t**2

    return

  end function dphi_dt_

!****

  function dpsi_dt_ (t)

    real(WP), intent(in) :: t
    real(WP)             :: dpsi_dt_

    ! Evaluate the first derivative of the psi basis function

    dpsi_dt_ = 3._WP*t**2 - 2._WP*t

    return

  end function dpsi_dt_

end module gyre_spline