! Module   : gyre_mesa_file
! Purpose  : read MESA files
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

module gyre_mesa_file

  ! Uses

  use core_kinds
  use core_constants

  use gyre_base_coeffs
  use gyre_therm_coeffs
  use gyre_evol_base_coeffs
  use gyre_evol_therm_coeffs

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Access specifiers

  private

  public :: read_mesa_file

  ! Procedures

contains

  subroutine read_mesa_file (file, G, deriv_type, bc, tc, x)

    character(LEN=*), intent(in)                              :: file
    real(WP), intent(in)                                      :: G
    character(LEN=*), intent(in)                              :: deriv_type 
    class(base_coeffs_t), allocatable, intent(out)            :: bc
    class(therm_coeffs_t), allocatable, intent(out), optional :: tc
    real(WP), allocatable, intent(out), optional              :: x(:)

    integer               :: unit
    integer               :: n
    real(WP)              :: M_star
    real(WP)              :: R_star
    real(WP)              :: L_star
    integer               :: n_cols
    real(WP), allocatable :: var(:,:)
    integer               :: k
    integer               :: k_chk
    real(WP), allocatable :: r(:)
    real(WP), allocatable :: m(:)
    real(WP), allocatable :: p(:)
    real(WP), allocatable :: rho(:)
    real(WP), allocatable :: T(:)
    real(WP), allocatable :: N2(:)
    real(WP), allocatable :: nabla(:)
    real(WP), allocatable :: Gamma_1(:)
    real(WP), allocatable :: c_p(:)
    real(WP), allocatable :: delta(:)
    real(WP), allocatable :: kappa(:)
    real(WP), allocatable :: kappa_rho(:)
    real(WP), allocatable :: kappa_T(:)
    real(WP), allocatable :: epsilon(:)
    real(WP), allocatable :: epsilon_rho(:)
    real(WP), allocatable :: epsilon_T(:)
    real(WP), allocatable :: nabla_ad(:)

    ! Read the model from the MESA-format file

    open(NEWUNIT=unit, FILE=file, STATUS='OLD')

    ! Read the header

    read(unit, *) n, M_star, R_star, L_star, n_cols

    if(n_cols == 1) then

       ! Handle older file formats which didn't have n_cols

       n_cols = 18

       backspace(unit)

       write(OUTPUT_UNIT, *) '  Detected old-format file'

    endif

    ! Read the data

    allocate(var(n_cols,n))

    read_loop : do k = 1,n
       read(unit, *) k_chk, var(:,k)
       $ASSERT(k == k_chk,Index mismatch)
    end do read_loop

    close(unit)

    r = var(1,:)
    m = var(2,:)/(1._WP+var(2,:))*M_star
    p = var(4,:)
    T = var(5,:)
    rho = var(6,:)
    nabla = var(7,:)
    N2 = var(8,:)
    Gamma_1 = var(12,:)*var(10,:)/var(9,:)
    c_p = var(10,:)
    delta = var(11,:)/var(12,:)
    kappa = var(13,:)
    kappa_T = var(14,:)
    kappa_rho = var(15,:)
    epsilon = var(16,:)
    epsilon_T = var(17,:)
    epsilon_rho = var(18,:)

    nabla_ad = p*delta/(rho*T*var(10,:))

    ! Decide whether epsilon_T and epsilon_rho need scaling

    k = MAXLOC(ABS(epsilon_T), DIM=1)

    if(ABS(epsilon_T(k)) < 1E-3*ABS(epsilon(k))) then

       epsilon_T = epsilon_T*epsilon
       epsilon_rho = epsilon_rho*epsilon

       write(OUTPUT_UNIT, *) '  Rescaled epsilons'

    endif

    ! If necessary, add central data

    if(r(1) > 0._WP) then

       m = [0._WP,m]
       N2 = [0._WP,N2]

       call add_center(r, p)
       call add_center(r, rho)
       call add_center(r, T)
       call add_center(r, Gamma_1)
       call add_center(r, nabla_ad)
       call add_center(r, delta)
       call add_center(r, nabla)
       call add_center(r, kappa)
       call add_center(r, kappa_rho)
       call add_center(r, kappa_T)
       call add_center(r, epsilon)
       call add_center(r, epsilon_rho)
       call add_center(r, epsilon_T)

       r = [0._WP,r]

       write(OUTPUT_UNIT, *) '  Added central point'

    endif

    ! Initialize the base_coeffs

    allocate(evol_base_coeffs_t::bc)

    select type (bc)
    type is (evol_base_coeffs_t)
       call bc%init(G, M_star, R_star, L_star, r, m, p, rho, T, &
                    N2, Gamma_1, nabla_ad, delta, deriv_type)
    class default
       $ABORT(Invalid bc type)
    end select

    ! Initialize the therm_coeffs

    if(PRESENT(tc)) then

       allocate(evol_therm_coeffs_t::tc)

       select type (tc)
       type is (evol_therm_coeffs_t)
          call tc%init(G, M_star, R_star, L_star, r, m, p, rho, T, &
                       Gamma_1, nabla_ad, delta, nabla,  &
                       kappa, kappa_rho, kappa_T, &
                       epsilon, epsilon_rho, epsilon_T, deriv_type)
       class default
          $ABORT(Invalid tc type)
       end select

    endif

    ! Set up the grid

    if(PRESENT(x)) x = r/R_star

    ! Finish

    return

  end subroutine read_mesa_file

!****

  subroutine add_center (x, y)

    real(WP), intent(in)                 :: x(:)
    real(WP), intent(inout), allocatable :: y(:)

    real(WP) :: y_0

    ! Add center (x=0) data to the array y(x), incrementing the
    ! dimension of y by 1. x is not altered.

    y_0 = (x(2)**2*y(1) - x(1)**2*y(2))/(x(2)**2 - x(1)**2)

    y = [y_0,y]

    ! Finish

    return

  end subroutine add_center

end module gyre_mesa_file
