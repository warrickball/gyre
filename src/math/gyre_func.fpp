! Module   : gyre_func
! Purpose  : standard mathematical functions
!
! Copyright 2019 The GYRE Team
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

module gyre_func

  ! Uses

  use core_kinds
  use core_constants

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Access specifiers

  private

  public :: factorial
  public :: double_factorial
  public :: legendre_P
  public :: spherical_Y

  ! Procedures

contains

  function factorial (n) result (f)

    integer, intent(in) :: n
    real(WP)            :: f

    $ASSERT_DEBUG(n >= 0,Invalid n)

    ! Evaluate the factorial n!
    
    f = GAMMA(REAL(n+1, WP))

    ! Finish

    return

  end function factorial

  !****

  function double_factorial (n) result (f)

    integer, intent(in) :: n
    real(WP)            :: f

    integer :: k

    $ASSERT_DEBUG(n >= -1,Invalid n)

    ! Evaluate the double factorial n!!

    if (n == 0) then

       f = 1._WP

    elseif (MOD(n, 2) == 0) then

       k = n/2
       f = 2**k*factorial(k)

    else

       k = (n+1)/2
       f = factorial(2*k)/(2**k*factorial(k))

    end if

    ! Finish

    return

  end function double_factorial

  !****

  function legendre_P (l, m, x) result (P)

    integer, intent(in)  :: l
    integer, intent(in)  :: m
    real(WP), intent(in) :: x
    real(WP)             :: P

    integer  :: am
    real(WP) :: y
    real(WP) :: P_1
    real(WP) :: P_2
    integer  :: k

    $ASSERT(ABS(x) <= 1,Invalid x)

    ! Evaluate the associated Legendre function P^m_l with degree l
    ! and order m. The definitions given by [Abramowicz:1970] are
    ! adopted --- in particular, their eqn. 8.6.6, which uses the
    ! Condon-Shortley phase term

    am = ABS(m)

    if (am > l) then

       P = 0._WP

    elseif (l < 0) then

       P = 0._WP

    else

       y = SQRT((1._WP - x)*(1._WP + x))
       P = (-1)**am * double_factorial(2*am-1) * y**am

       if (l > am) then

          P_1 = P
          P = x*(2*am+1)*P_1

          do k = am+2, l
             P_2 = P_1
             P_1 = P
             P = ((2*k-1)*x*P_1 - (k+am-1)*P_2)/(k-am)
          end do

       endif

    endif

    if (m < 0) then
       P = (-1)**am*factorial(l-am)/factorial(l+am)*P
    endif

    ! Finish

    return

  end function legendre_P

  !****

  function spherical_Y (l, m, theta, phi) result (Y)

    integer, intent(in)  :: l
    integer, intent(in)  :: m
    real(WP), intent(in) :: theta
    real(WP), intent(in) :: phi
    complex(WP)          :: Y

    ! Evaluate the spherical harmonic with degree l and order m

    Y = SQRT((2*l+1)/(4*PI)*factorial(l-m)/factorial(l+m))* &
         legendre_P(l, m, COS(theta))*EXP(CMPLX(0._WP, m*phi, WP))

    ! Finish

    return

  end function spherical_Y

end module gyre_func
