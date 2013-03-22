! Program  : gyre_nad
! Purpose  : nonadiabatic oscillation code
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

program gyre_nad

  ! Uses

  use core_kinds
  use core_constants
  use core_parallel
  use core_hgroup
  use core_order

  use gyre_mech_coeffs
  use gyre_therm_coeffs
  use gyre_oscpar
  use gyre_ad_bvp
  use gyre_ad_search
  use gyre_nad_bvp
  use gyre_nad_search
  use gyre_mode
  use gyre_frontend
  use gyre_grid

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Variables

  integer                            :: unit
  real(WP), allocatable              :: x_mc(:)
  class(mech_coeffs_t), allocatable  :: mc
  class(therm_coeffs_t), allocatable :: tc
  type(oscpar_t)                     :: op
  integer                            :: n_iter_max
  real(WP)                           :: psi_ad
  character(LEN=256)                 :: ivp_solver_type
  type(ad_bvp_t)                     :: ad_bp
  type(nad_bvp_t)                    :: nad_bp
  real(WP), allocatable              :: omega(:)
  type(mode_t), allocatable          :: ad_md(:)
  type(mode_t), allocatable          :: nad_md(:)
  integer                            :: i
  real(WP), allocatable              :: E(:)

  ! Initialize

  call init_parallel()

  if(MPI_RANK == 0) then

     write(OUTPUT_UNIT, '(A)') 'gyre_nad [hg]'
     write(OUTPUT_UNIT, '(A,2X,I0)') 'OpenMP Threads :', OMP_SIZE_MAX
     write(OUTPUT_UNIT, '(A,2X,I0)') 'MPI Processors :', MPI_SIZE
     
     call open_input(unit)

  endif

  call write_header('Initialization', '=')

  call init_coeffs(unit, x_mc, mc, tc)
  call init_oscpar(unit, op)
  call init_numpar(unit, n_iter_max, psi_ad, ivp_solver_type)
  call init_scan(unit, mc, omega)
  call init_bvp(unit, x_mc, mc, tc, op, omega, psi_ad, ivp_solver_type, ad_bp, nad_bp)

  ! Search for modes

  call ad_scan_search(ad_bp, omega, n_iter_max, ad_md)
  call nad_prox_search(nad_bp, ad_md, n_iter_max, nad_md)

  ! Calculate inertias

  allocate(E(SIZE(nad_md)))

  do i = 1,SIZE(nad_md)
     E(i) = inertia(mc, op, nad_md(i))
  end do

  ! Write output
 
  if(MPI_RANK == 0) then
     call write_eigdata(unit, mc, op, nad_md)
  endif

  ! Finish

  call final_parallel()

contains

  subroutine init_numpar (unit, n_iter_max, psi_ad, ivp_solver_type)

    integer, intent(in)           :: unit
    integer, intent(out)          :: n_iter_max
    real(WP), intent(out)         :: psi_ad
    character(LEN=*), intent(out) :: ivp_solver_type

    namelist /numpar/ n_iter_max, psi_ad, ivp_solver_type

    ! Read numerical parameters

    if(MPI_RANK == 0) then

       n_iter_max = 50
       psi_ad = 0._WP

       ivp_solver_type = 'MAGNUS_GL2'

       rewind(unit)
       read(unit, NML=numpar)

    endif

    $if($MPI)
    call bcast(n_iter_max, 0)
    call bcast(psi_ad, 0)
    call bcast(ivp_solver_type, 0)
    $endif

    ! Finish

    return

  end subroutine init_numpar

!****

  subroutine init_bvp (unit, x_mc, mc, tc, op, omega, psi_ad, ivp_solver_type, ad_bp, nad_bp)

    use gyre_ad_jacobian
    use gyre_ad_bound
    use gyre_ad_shooter
    use gyre_nad_jacobian
    use gyre_nad_bound
    use gyre_nad_shooter

    integer, intent(in)                       :: unit
    real(WP), intent(in), allocatable         :: x_mc(:)
    class(mech_coeffs_t), intent(in), target  :: mc
    class(therm_coeffs_t), intent(in), target :: tc
    type(oscpar_t), intent(in)                :: op
    real(WP), intent(in)                      :: omega(:)
    real(WP), intent(in)                      :: psi_ad
    character(LEN=*), intent(in)              :: ivp_solver_type
    type(ad_bvp_t), intent(out)               :: ad_bp
    type(nad_bvp_t), intent(out)              :: nad_bp

    type(ad_jacobian_t)   :: ad_jc
    type(nad_jacobian_t)  :: nad_jc
    type(ad_bound_t)      :: ad_bd
    type(nad_bound_t)     :: nad_bd
    character(LEN=256)    :: grid_type
    real(WP)              :: alpha_osc
    real(WP)              :: alpha_exp
    integer               :: n_center
    integer               :: n_floor
    real(WP)              :: s
    integer               :: n_grid
    integer               :: dn(SIZE(x_mc)-1)
    integer               :: i
    real(WP), allocatable :: x_sh(:)
    type(ad_shooter_t)    :: ad_sh
    type(nad_shooter_t)   :: nad_sh

    namelist /shoot_grid/ grid_type, alpha_osc, alpha_exp, &
         n_center, n_floor, s, n_grid

    namelist /recon_grid/ alpha_osc, alpha_exp, n_center, n_floor

    ! Initialize the Jacobians and boundary conditions

    call ad_jc%init(mc, op)
    call nad_jc%init(mc, tc, op)

    call ad_bd%init(mc, op)
    call nad_bd%init(mc, tc, op)

    ! Read shooting grid parameters

    if(MPI_RANK == 0) then

       grid_type = 'DISPERSION'

       alpha_osc = 0._WP
       alpha_exp = 0._WP
       
       n_center = 0
       n_floor = 0

       s = 100._WP
       n_grid = 100

       rewind(unit)
       read(unit, NML=shoot_grid)

    endif

    $if($MPI)
    call bcast(grid_type, 0)
    call bcast(alpha_osc, 0)
    call bcast(alpha_exp, 0)
    call bcast(n_center, 0)
    call bcast(n_floor, 0)
    call bcast(s, 0)
    call bcast(n_grid, 0)
    $endif

    ! Initialize the shooting grid

    select case(grid_type)
    case('GEOM')
       call build_geom_grid(s, n_grid, x_sh)
    case('LOG')
       call build_log_grid(s, n_grid, x_sh)
    case('DISPERSION')
       $ASSERT(ALLOCATED(x_mc),No input grid)
       dn = 0
       do i = 1,SIZE(omega)
          call plan_dispersion_grid(x_mc, mc, CMPLX(omega(i), KIND=WP), op, alpha_osc, alpha_exp, n_center, n_floor, dn)
       enddo
       call build_oversamp_grid(x_mc, dn, x_sh)
    case default
       $ABORT(Invalid grid_type)
    end select

    ! Read recon grid parameters

    if(MPI_RANK == 0) then

       alpha_osc = 0._WP
       alpha_exp = 0._WP
       
       n_center = 0
       n_floor = 0

       rewind(unit)
       read(unit, NML=recon_grid)

    endif

    $if($MPI)
    call bcast(alpha_osc, 0)
    call bcast(alpha_exp, 0)
    call bcast(n_center, 0)
    call bcast(n_floor, 0)
    $endif

    ! Initialize the shooters

    call ad_sh%init(mc, op, ad_jc, x_sh, alpha_osc, alpha_exp, n_center, n_floor, ivp_solver_type)
    call nad_sh%init(mc, tc, op, ad_jc, nad_jc, x_sh, alpha_osc, alpha_exp, n_center, n_floor, ivp_solver_type)

    ! Initialize the bvps

    call ad_bp%init(ad_sh, ad_bd)
    call nad_bp%init(nad_sh, nad_bd)

    ! Finish

    return

  end subroutine init_bvp

!****

  subroutine write_eigdata (unit, mc, op, md)

    integer, intent(in)              :: unit
    class(mech_coeffs_t), intent(in) :: mc
    class(oscpar_t), intent(in)      :: op
    type(mode_t), intent(in)         :: md(:)

    character(LEN=256)               :: freq_units
    character(LEN=FILENAME_LEN)      :: eigval_file
    character(LEN=FILENAME_LEN)      :: eigfunc_prefix
    integer                          :: i
    complex(WP)                      :: freq(SIZE(md))
    type(hgroup_t)                   :: hg
    character(LEN=FILENAME_LEN)      :: eigfunc_file

    namelist /output/ freq_units, eigval_file, eigfunc_prefix

    ! Read output parameters

    freq_units = 'NONE'

    eigval_file = ''
    eigfunc_prefix = ''

    rewind(unit)
    read(unit, NML=output)

    ! Write eigenvalues

    freq_loop : do i = 1,SIZE(md)
       freq(i) = mc%conv_freq(md(i)%omega, 'NONE', freq_units)
    end do freq_loop

    if(eigval_file /= '') then

       call hg%init(eigval_file, CREATE_FILE)
          
       call write_attr(hg, 'n_md', SIZE(md))

!       call write_attr(hg, 'n', bp%n)
!       call write_attr(hg, 'n_e', bp%n_e)

       call write_attr(hg, 'l', op%l)

       call write_dset(hg, 'n_p', md%n_p)
       call write_dset(hg, 'n_g', md%n_g)

       call write_dset(hg, 'freq', freq)
       call write_attr(hg, 'freq_units', freq_units)

       call write_dset(hg, 'E', E)

       call hg%final()

    end if

    ! Write eigenfunctions

    if(eigfunc_prefix /= '') then

       mode_loop : do i = 1,SIZE(md)

          write(eigfunc_file, 100) TRIM(eigfunc_prefix), i, '.h5'
100       format(A,I4.4,A)

          call hg%init(eigfunc_file, CREATE_FILE)

!          call write_attr(hg, 'n', bp%n)
!          call write_attr(hg, 'n_e', bp%n_e)

          call write_attr(hg, 'l', op%l)
          call write_attr(hg, 'lambda_0', op%lambda_0)

          call write_attr(hg, 'n_p', md(i)%n_p)
          call write_attr(hg, 'n_g', md(i)%n_g)

          call write_dset(hg, 'freq', freq(i))
          call write_attr(hg, 'freq_units', freq_units)

          call write_dset(hg, 'x', md(i)%x)
          call write_dset(hg, 'y', md(i)%y)

          call hg%final()

       end do mode_loop

    end if

    ! Finish

    return

  end subroutine write_eigdata

!*****

  function inertia (mc, op, md) result (E)

    class(mech_coeffs_t), intent(in) :: mc
    class(oscpar_t), intent(in)      :: op
    class(mode_t), intent(in)        :: md
    real(WP)                         :: E

    integer     :: i
    real(WP)    :: dE_dx(md%n)
    real(WP)    :: U
    real(WP)    :: c_1
    complex(WP) :: xi_r
    complex(WP) :: xi_h
    real(WP)    :: E_norm

    ! Set up the inertia integrand

    !$OMP PARALLEL DO PRIVATE (U, c_1, xi_r, xi_h)
    do i = 1,md%n

       U = mc%U(md%x(i))
       c_1 = mc%c_1(md%x(i))

       if(op%l == 0) then
          xi_r = md%y(1,i)
          xi_h = 0._WP
       else
          xi_r = md%y(1,i)
          xi_h = md%y(2,i)/(c_1*md%omega**2)
       endif

       if(md%x(i) > 0._WP) then
          xi_r = xi_r*md%x(i)**(op%lambda_0+1._WP)
          xi_h = xi_h*md%x(i)**(op%lambda_0+1._WP)
       else
          if(op%lambda_0 /= -1._WP) then
             xi_r = 0._WP
             xi_h = 0._WP
          endif
       endif

       dE_dx(i) = (ABS(xi_r)**2 + op%l*(op%l+1)*ABS(xi_h)**2)*U*md%x(i)**2/c_1

    end do

    ! Integrate via a tropezoidal rule

    E = SUM(0.5_WP*(dE_dx(2:) + dE_dx(:md%n-1))*(md%x(2:) - md%x(:md%n-1)))

    ! Normalize

    if(op%l == 0) then
       xi_r = md%y(1,md%n)
       xi_h = 0._WP
    else
       xi_r = md%y(1,md%n)
       xi_h = md%y(2,md%n)/md%omega**2
    endif

    E_norm = ABS(xi_r)**2 + op%l*(op%l+1)*ABS(xi_h)**2
    $ASSERT(E_norm /= 0._WP,E_norm is zero)    
    
    E = E/E_norm

    ! Finish

    return

  end function inertia

end program gyre_nad
