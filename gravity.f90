!
! Module for solving gravity on grid.
! Contains a tree for a boundary solver
! And a relaxation method for everything else.
! A version of a multigrid solver is used with
! the switch FASTGRAVITY.
!
module selfgravity
 use parameters
 use derived_types
 use grid_commons
 use utils
 implicit none

 type(gravcell),dimension(:),allocatable,save::grav_grid
 real(pre),dimension(:),allocatable,save::gdy,gdx,gdz,gravrho
 real(pre)::mbox,xcom_grid,ycom_grid,zcom_grid
 real(pre)::abin=20.,ebin=0.0d0,mbin=1d0
 integer,dimension(:),allocatable,save::gny,gnx,gnz,ngrav_grid,grav_bound_indx,ngrav_bound
 integer,save::nchild=8,nlevel=4,nmulti=1

 real*8,save::thetaopen=0.7d0

 contains
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Factorial, used in expansions.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 recursive subroutine factorial(n,fac)
  logical, save::first=.true.
  real(pre)::n,fac

  if(first)then
    fac=n
    if(fac==zero)fac=one
    if(n>one)first=.false.
  endif
  if((n-one)>one)then
    fac=fac*(n-one)
    call factorial(n-one,fac)
  else
    first=.true.
  endif
  return  
 end subroutine factorial
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Initialize the gravity grid, including tree.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine init_grav_grid
 
 integer::nleaf,ileaf,ilevel,ngrav_tot,iskip
 integer::igrid,iz,ix,iy
 integer::ilevel2,iskip2,inode,ichild,ibound,tbound
 real(pre)::x,y,z,xg,yg,zg,dist,boxx,boxy,boxz,yoff=zero

!!!!!! allocate(phi_new(ngrid))
 allocate(gdx(nlevel))
 allocate(gdy(nlevel))
 allocate(gdz(nlevel))
 allocate(gnx(nlevel))
 allocate(gny(nlevel))
 allocate(gnz(nlevel))
 allocate(ngrav_grid(nlevel))
 allocate(ngrav_bound(nlevel))

 ngrav_tot=0

 boxx= dble(nx)*dx
 boxy= dble(ny)*dy
 boxz= dble(nz)*dz

 do ilevel=1,nlevel
   gdx(ilevel) = dx*two**(ilevel)
   gdy(ilevel) = dy*two**(ilevel)
   gdz(ilevel) = dz*two**(ilevel)
   gnx(ilevel) = boxx/gdx(ilevel)
   gny(ilevel) = boxy/gdy(ilevel)
   gnz(ilevel) = boxz/gdz(ilevel)

   ngrav_grid(ilevel) = gnx(ilevel)*gny(ilevel)*gnz(ilevel)
   ngrav_tot=ngrav_tot+ngrav_grid(ilevel)
   print *, "#",ilevel,ngrid,ngrav_grid(ilevel),gnx(ilevel),gny(ilevel),gnz(ilevel),gdx(ilevel),gdy(ilevel),gdz(ilevel)
 enddo
 allocate(grav_grid(ngrav_tot))
 
 ilevel=1
 nleaf=nchild

 iskip=0
 do ilevel =1,nlevel
 igrid=0

 do iz = 1,gnz(ilevel)
  z = gdz(ilevel)*(dble(iz)-(dble(gnz(ilevel))+one)*half)
  do iy = 1,gny(ilevel)
   y = gdy(ilevel)*(dble(iy)-(dble(gny(ilevel))+one)*half)
   do ix = 1,gnx(ilevel)
    x = gdx(ilevel)*(dble(ix)-(dble(gnx(ilevel))+one)*half)
    igrid=igrid+1
    grav_grid(igrid+iskip)%x=x
    grav_grid(igrid+iskip)%y=y
    grav_grid(igrid+iskip)%z=z
    grav_grid(igrid+iskip)%id=igrid+iskip
    grav_grid(igrid+iskip)%rmax=zero
    grav_grid(igrid+iskip)%boundary=.false.
    do ileaf=1,nchild
     grav_grid(igrid+iskip)%ichild(ileaf)=0
    enddo
   enddo
  enddo
 enddo

 iskip=iskip+ngrav_grid(ilevel)
 
 enddo

 iskip=0
 ilevel=1
 print *,"# Building links for grav level ",ilevel
  nleaf=0
  do igrid=1,ngrid
   x=grid(igrid)%x
   y=grid(igrid)%y
   z=grid(igrid)%z

    iz = int( (z+boxz*half)/gdz(ilevel) )+1
    iy = int( (y+boxy*half)/gdy(ilevel) )+1
    ix = int( (x+boxx*half)/gdx(ilevel) )+1
 
   inode = (iz-1)*gny(ilevel)*gnx(ilevel)+ (iy-1)*gnx(ilevel) +ix 

   xg=grav_grid(inode+iskip)%x
   yg=grav_grid(inode+iskip)%y
   zg=grav_grid(inode+iskip)%z

   if(abs(xg-x)*(one)>gdx(ilevel)*half .or.  &
      abs(yg-y)*(one)>gdy(ilevel)*half .or.  &
      abs(zg-z)*(one)>gdz(ilevel)*half ) then
      print *, "Mistmatch between node and leaf for node ",inode+iskip,igrid
      print *, xg-x,yg-y,zg-z,gdx(ilevel)*half,gdy(ilevel)*half,gdz(ilevel)*half
      print *, xg,yg,zg,x,y,z,ix,iy,iz
      stop
   endif

   dist=sqrt( (xg-x)**2+(yg-y)**2+(zg-z)**2 )
   if (dist>grav_grid(inode+iskip)%rmax) grav_grid(inode+iskip)%rmax=dist
 
   do ichild=1,nchild
     ileaf= grav_grid(inode+iskip)%ichild(ichild)
     if(ileaf==0)then
       grav_grid(inode+iskip)%ichild(ichild)=igrid
       if(grid(igrid)%boundary==1.or.grid(igrid)%boundary==2)then
          grav_grid(inode+iskip)%boundary=.true.
       endif
       nleaf=nleaf+1
       exit
     else
       if(ichild>nchild)then
         print *, grav_grid(inode+iskip)%ichild(ichild),ichild,nchild,ilevel
         print *,"More children than allowed.  Linking must be broken."
         print *, xg-x,yg-y,zg-z,gdx(ilevel)*half,gdy(ilevel)*half,gdz(ilevel)*half
         print *, xg,yg,zg,x,y,z
 
         stop
       endif
     endif
   enddo 
  enddo
 print *, "Assigned a total of ",nleaf," children"

 iskip=0
 iskip2=ngrav_grid(1)
 do ilevel=1,nlevel-1
  ilevel2=ilevel+1
  print *,"# Building links for grav level ",ilevel2
  do igrid=1,ngrav_grid(ilevel)
    x=grav_grid(igrid+iskip)%x
    y=grav_grid(igrid+iskip)%y
    z=grav_grid(igrid+iskip)%z
     do ix=1,gnx(ilevel2)
       xg = gdx(ilevel2)*(dble(ix)-one)-boxx*half+gdx(ilevel2)
       if ( x < xg ) exit
     enddo
     do iy=1,gny(ilevel2)
       yg = gdy(ilevel2)*(dble(iy)-one)-boxy*half+gdy(ilevel2)
       if ( y < yg ) exit
     enddo
     do iz=1,gnz(ilevel2)
       zg = gdz(ilevel2)*(dble(iz)-one)-boxz*half+gdz(ilevel2)
       if ( z < zg ) exit
     enddo
    inode = (iz-1)*gny(ilevel2)*gnx(ilevel2)+ (iy-1)*gnx(ilevel2) +ix  + iskip2
 
    xg=grav_grid(inode)%x
    yg=grav_grid(inode)%y
    zg=grav_grid(inode)%z
 
   if(abs(xg-x)>gdx(ilevel2)*half .and.  &
      abs(yg-y)>gdy(ilevel2)*half .and.  &
      abs(zg-z)>gdz(ilevel2)*half ) then
      print *, "Mistmatch between node and leaf"
      stop
   endif

   dist=sqrt( (xg-x)**2+(yg-y)**2+(zg-z)**2 )
   if (dist>grav_grid(inode)%rmax) grav_grid(inode)%rmax=dist
 
   do ichild=1,nchild
     ileaf= grav_grid(inode)%ichild(ichild)
     if(ileaf==0)then
       grav_grid(inode)%ichild(ichild)=igrid+iskip
       exit
     else
       if(ichild>nchild)then
         print *, inode,grav_grid(inode)%ichild(ichild),ichild,nchild,ilevel
         print *,"More children than allowed.  Linking must be broken."
         stop
       endif
     endif
   enddo 
  enddo
  iskip=iskip+ngrav_grid(ilevel)
  iskip2=iskip2+ngrav_grid(ilevel2)
 enddo

 tbound=0
 do ilevel=1,nlevel
  iskip=0
  do inode=1,ilevel-1
    iskip=iskip+ngrav_grid(ilevel)
  enddo
  ibound=0
  do igrid=1,ngrav_grid(ilevel)
    inode=igrid+iskip
    if (grav_grid(inode)%boundary)ibound=ibound+1
  enddo
  ngrav_bound(ilevel)=ibound
  tbound=tbound+ibound
 enddo
 allocate(grav_bound_indx(tbound))
 ibound=0
 do ilevel=1,nlevel
  iskip=0
  do inode=1,ilevel-1
    iskip=iskip+ngrav_grid(ilevel)
  enddo
  do igrid=1,ngrav_grid(ilevel)
    inode=igrid+iskip
    if (grav_grid(inode)%boundary)then
      ibound=ibound+1
      grav_bound_indx(ibound)=inode
    endif
  enddo
 enddo
 

 print *, "# Built Gravity Tree "

 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Now find center of mass for each node in the gravity tree
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine set_com_in_tree
  real(pre)::x,y,z,mass,xcm,ycm,zcm,mtot_loc,mnode
  real(pre)::rmax
  integer::ilevel,iskip,inode,ichild,indx

  ilevel=1
  iskip=0
  mtot_loc=zero
  xcom_grid=zero;ycom_grid=zero;zcom_grid=zero
  do inode=1,ngrav_grid(ilevel)
    mnode=zero
    xcm=zero;ycm=zero;zcm=zero
    do ichild=1,nchild
     indx=grav_grid(inode+iskip)%ichild(ichild)
     if(indx==0)exit
     x=grid(indx)%x;y=grid(indx)%y;z=grid(indx)%z
     mass=rhotot(indx)*dx*dy*dz
     xcm=xcm+mass*(x)
     ycm=ycm+mass*(y)
     zcm=zcm+mass*(z)
     mnode=mnode+mass
    enddo
    xcom_grid=xcom_grid+xcm
    ycom_grid=ycom_grid+ycm
    zcom_grid=zcom_grid+zcm
    if(mnode==zero)cycle
    xcm=xcm/mnode;ycm=ycm/mnode;zcm=zcm/mnode
    rmax=zero
    do ichild=1,nchild
     indx=grav_grid(inode+iskip)%ichild(ichild)
     if(indx==0)exit
     x=grid(indx)%x;y=grid(indx)%y;z=grid(indx)%z
     rmax=max(rmax,sqrt( (x-xcm)**2+(y-ycm)**2+(z-zcm)**2))
    enddo
    mtot_loc=mtot_loc+mnode
    grav_grid(inode+iskip)%xcm=xcm
    grav_grid(inode+iskip)%ycm=ycm
    grav_grid(inode+iskip)%zcm=zcm
    grav_grid(inode+iskip)%mass=mnode
    grav_grid(inode+iskip)%rmax=rmax
  enddo
!
!***
! Check for consistency in total mass. There may be a slight difference
! due to inclusion of the ghost cells, but only if significant mass is
! at the edge of the grid.
!***
!
!
#ifdef VERBOSE
  print *, "# Mtot on level 1 ",mtot_loc ! check for consistency in mass.
#endif
!
!
  xcom_grid=xcom_grid/mtot_loc
  ycom_grid=ycom_grid/mtot_loc
  zcom_grid=zcom_grid/mtot_loc
  mbox=mtot_loc

  iskip = ngrav_grid(1)
  do ilevel=2,nlevel
   mtot_loc=zero
   do inode=1,ngrav_grid(ilevel)
     mnode=zero
     xcm=zero;ycm=zero;zcm=zero
     do ichild=1,nchild
      indx=grav_grid(inode+iskip)%ichild(ichild)
      if(indx==0)exit
      x=grav_grid(indx)%xcm;y=grav_grid(indx)%ycm;z=grav_grid(indx)%zcm
      mass=grav_grid(indx)%mass
      xcm=xcm+mass*(x)
      ycm=ycm+mass*(y)
      zcm=zcm+mass*(z)
      mnode=mnode+mass
     enddo
     if(mnode==zero)cycle
     xcm=xcm/mnode;ycm=ycm/mnode;zcm=zcm/mnode
     rmax=zero
     do ichild=1,nchild
      indx=grav_grid(inode+iskip)%ichild(ichild)
      if(indx==0)cycle
      x=grav_grid(indx)%xcm;y=grav_grid(indx)%ycm;z=grav_grid(indx)%zcm
      rmax=max(rmax,sqrt( (x-xcm)**2+(y-ycm)**2+(z-zcm)**2))
     enddo
     grav_grid(inode+iskip)%xcm=xcm
     grav_grid(inode+iskip)%ycm=ycm
     grav_grid(inode+iskip)%zcm=zcm
     grav_grid(inode+iskip)%mass=mnode
     grav_grid(inode+iskip)%rmax=rmax
     mtot_loc=mtot_loc+mnode
   enddo
   iskip=iskip+ngrav_grid(ilevel)
   !print *,"#total mass on level ",ilevel,mtot_loc
  enddo

 return

end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get potential from tree only. This solves for the potential everywhere
! using a tree. The dipole moment is included because we use the COM of
! each mode.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine get_pot_from_tree
  integer::igrid,ilevel,indx,l,flag,inode,iskip
  real(pre)::x,y,z,xx,yy,zz,r,phi_loc,theta

!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(igrid,ilevel,indx,l,flag,inode,iskip)&
!$OMP&PRIVATE(x,y,z,xx,yy,zz,r,phi_loc,theta)
!$OMP DO SCHEDULE(dynamic)
  do igrid=1,ngrid
   phi_loc=zero
   x=grid(igrid)%x;y=grid(igrid)%y;z=grid(igrid)%z
   iskip=0
   do ilevel=1,nlevel-1
     iskip=iskip+ngrav_grid(ilevel)
   enddo
   ilevel=nlevel
   do inode=1,ngrav_grid(ilevel)
    if(.not.(grav_grid(inode+iskip)%mass>zero))cycle
    xx=grav_grid(inode+iskip)%xcm;yy=grav_grid(inode+iskip)%ycm;zz=grav_grid(inode+iskip)%zcm
    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
    flag=0
    if(r>zero)then
     theta = sqrt(gdx(ilevel)**2+gdy(ilevel)**2+gdz(ilevel)**2)/r !grav_grid(inode+iskip)%rmax/r
     if(theta>thetaopen)flag=1
    else
     flag=1
    endif
    if(flag==0)then
      !print *, "Flag level, ",nlevel
      phi_loc=phi_loc-grav_grid(inode+iskip)%mass/r !- &
    else
      indx=inode+iskip !grav_grid(inode)%id
      l=ilevel
      call gather_pot(phi_loc,x,y,z,indx,l,1) ! work horse of the function.
    endif
   enddo
   !print *, igrid,phi_loc
   phi(igrid)=phi_loc
 enddo
!$OMP ENDDO
!$OMP END PARALLEL
end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Similar to above, but for the boundary cells only.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine get_pot_bc_from_tree
  integer::igrid,ilevel,indx,l,flag,inode,iskip,ibound
  real(pre)::x,y,z,xx,yy,zz,r,phi_loc,theta

!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(igrid,ilevel,indx,l,flag,inode,iskip)&
!$OMP&PRIVATE(x,y,z,xx,yy,zz,r,phi_loc,theta)
!$OMP DO SCHEDULE(dynamic)
  do ibound=1,nghost
   igrid=indx_ghost(ibound)
   phi_loc=zero
   x=grid(igrid)%x;y=grid(igrid)%y;z=grid(igrid)%z
   iskip=0
   do ilevel=1,nlevel-1
     iskip=iskip+ngrav_grid(ilevel)
   enddo
   ilevel=nlevel
   do inode=1,ngrav_grid(ilevel)
    xx=grav_grid(inode+iskip)%xcm;yy=grav_grid(inode+iskip)%ycm;zz=grav_grid(inode+iskip)%zcm
    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
    flag=0
    if(r>zero)then
     theta = sqrt(gdx(ilevel)**2+gdy(ilevel)**2+gdz(ilevel)**2)/r !grav_grid(inode+iskip)%rmax/r
     if(theta>thetaopen)flag=1
    else
     flag=1
    endif
    if(flag==0)then
      phi_loc=phi_loc-grav_grid(inode+iskip)%mass/r !- &
    else
      indx=inode+iskip !grav_grid(inode)%id
      l=ilevel
      call gather_pot(phi_loc,x,y,z,indx,l,1)
    endif
   enddo
   phi(igrid)=phi_loc
 enddo
!$OMP ENDDO
!#ifdef EXTRAANCHORS
!!$OMP DO SCHEDULE(dynamic)
!  do ibound=1,nanchor
!   igrid=indx_anchor(ibound)
!   phi_loc=zero
!   x=grid(igrid)%x;y=grid(igrid)%y;z=grid(igrid)%z
!   iskip=0
!   do ilevel=1,nlevel-1
!     iskip=iskip+ngrav_grid(ilevel)
!   enddo
!   ilevel=nlevel
!   do inode=1,ngrav_grid(ilevel)
!    xx=grav_grid(inode+iskip)%xcm;yy=grav_grid(inode+iskip)%ycm;zz=grav_grid(inode+iskip)%zcm
!    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
!    flag=0
!    if(r>zero)then
!     theta = sqrt(gdx(ilevel)**2+gdy(ilevel)**2+gdz(ilevel)**2)/r !grav_grid(inode+iskip)%rmax/r
!     if(theta>thetaopen)flag=1
!    else
!     flag=1
!    endif
!    if(flag==0)then
!      phi_loc=phi_loc-grav_grid(inode+iskip)%mass/r !- &
!    else
!      indx=inode+iskip !grav_grid(inode)%id
!      l=ilevel
!      call gather_pot(phi_loc,x,y,z,indx,l,1)
!    endif
!   enddo
!   phi(igrid)=phi_loc
! enddo
!!$OMP ENDDO
!#endif
!$OMP END PARALLEL
end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Use tree to get potential at level mlevel. 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine get_pot_at_higher_level(mlevel)
  integer::igrid,ilevel,indx,l,flag,inode,iskip,mlevel,id,ibottom,iskip2
  real(pre)::x,y,z,xx,yy,zz,r,phi_loc,theta

  iskip2=0
   do ilevel=1,mlevel-1
     iskip2=iskip2+ngrav_grid(ilevel)
   enddo
 
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(id,x,y,z,inode,r,flag,ilevel,theta, &
!$OMP& xx,yy,zz,indx,l,phi_loc,ibottom,iskip)
!$OMP DO SCHEDULE(dynamic) 
  do ibottom=1,ngrav_grid(mlevel)
   id=ibottom+iskip2
   phi_loc=zero
   x=grav_grid(id)%x;y=grav_grid(id)%y;z=grav_grid(id)%z
   iskip=0
   do ilevel=1,nlevel-1
     iskip=iskip+ngrav_grid(ilevel)
   enddo
   ilevel=nlevel
   do inode=1,ngrav_grid(ilevel)
    xx=grav_grid(inode+iskip)%xcm;yy=grav_grid(inode+iskip)%ycm;zz=grav_grid(inode+iskip)%zcm
    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
    flag=0
    if(r>zero)then
     theta = sqrt(gdx(ilevel)**2+gdy(ilevel)**2+gdz(ilevel)**2)/r !grav_grid(inode+iskip)%rmax/r
     if(theta>thetaopen)flag=1
    else
     flag=1
    endif
    if(flag==0)then
      phi_loc=phi_loc-grav_grid(inode+iskip)%mass/r !- &
    else
      indx=inode+iskip !grav_grid(inode)%id
      l=ilevel
      call gather_pot(phi_loc,x,y,z,indx,l,mlevel)
    endif
   enddo
   grav_grid(id)%phi=phi_loc
 enddo
!$OMP ENDDO
!$OMP ENDPARALLEL
end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get potential at domain boundaries for level mlevel
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine get_pot_bc_at_higher_level(mlevel)
  integer::igrid,ilevel,indx,l,flag,inode,iskip,mlevel,id,ibottom,iskip2
  real(pre)::x,y,z,xx,yy,zz,r,phi_loc,theta

  iskip2=0
  do ilevel=1,mlevel-1
    iskip2=iskip2+ngrav_bound(ilevel)
  enddo
 
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP& PRIVATE(id,x,y,z,inode,r,flag,ilevel,theta, &
!$OMP& xx,yy,zz,indx,l,phi_loc,ibottom,iskip) 

!$OMP DO SCHEDULE(dynamic) 
  do ibottom=1,ngrav_bound(mlevel)
   id=grav_bound_indx(ibottom+iskip2)
   phi_loc=zero
   x=grav_grid(id)%x;y=grav_grid(id)%y;z=grav_grid(id)%z
   iskip=0
   do ilevel=1,nlevel-1
     iskip=iskip+ngrav_grid(ilevel)
   enddo
   ilevel=nlevel
   do inode=1,ngrav_grid(ilevel)
    xx=grav_grid(inode+iskip)%xcm;yy=grav_grid(inode+iskip)%ycm;zz=grav_grid(inode+iskip)%zcm
    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
    flag=0
    if(r>zero)then
     theta = sqrt(gdx(ilevel)**2+gdy(ilevel)**2+gdz(ilevel)**2)/r !grav_grid(inode+iskip)%rmax/r
     if(theta>thetaopen)flag=1
    else
     flag=1
    endif
    if(flag==0)then
      phi_loc=phi_loc-grav_grid(inode+iskip)%mass/r !- &
    else
      indx=inode+iskip !grav_grid(inode)%id
      l=ilevel
      call gather_pot(phi_loc,x,y,z,indx,l,mlevel)
    endif
   enddo
   !print *, igrid,phi_loc
   grav_grid(id)%phi=phi_loc
 enddo
!$OMP ENDDO
!$OMP END PARALLEL
end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Main work horse for getting the potential via a tree. This is the
! walking function.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
recursive subroutine gather_pot(phi_loc,x,y,z,id,ilevel,level_limit)
  real(pre)::phi_loc,x,y,z,xx,yy,zz,theta,r
  integer::id,ilevel,flag,ilm,new_indx,ichild,indx,level_limit
  ilm=ilevel-1

  if(ilevel>1)then

  do ichild=1,nchild
   indx=grav_grid(id)%ichild(ichild)
   if(indx==0)exit
   xx=grav_grid(indx)%xcm;yy=grav_grid(indx)%ycm;zz=grav_grid(indx)%zcm
   r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2)
   flag=0
   if(r>zero)then
    theta = sqrt(gdx(ilm)**2+gdy(ilm)**2+gdz(ilm)**2)/r!grav_grid(indx)%rmax/r
    if(theta>thetaopen.and.ilevel>level_limit)flag=1
   else
    flag=1
   endif
   if(flag==0)then
     phi_loc=phi_loc-grav_grid(indx)%mass/r     !- &
   else
     new_indx=indx!grav_grid(indx)%id
     call gather_pot(phi_loc,x,y,z,new_indx,ilm,level_limit)
   endif
  enddo
   
  else

  do ichild=1,nchild
    indx=grav_grid(id)%ichild(ichild)
    if(indx==0)exit
    xx=grid(indx)%x;yy=grid(indx)%y;zz=grid(indx)%z
    r=sqrt( (x-xx)**2+(y-yy)**2+(z-zz)**2 )
    if(r>zero)then
     phi_loc=phi_loc-rhotot(indx)*dx*dy*dz/r
    endif
  enddo

  endif
end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Find the gravity grid boundaries at level ilevel.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
subroutine get_boundary_grav(ilevel,id,b)
  integer::ilevel,id,b(6)

  b(1)=id+gnx(ilevel)
  b(2)=id-gnx(ilevel)
  b(3)=id+1
  b(4)=id-1
  b(5)=id+gnx(ilevel)*gny(ilevel)
  b(6)=id-gnx(ilevel)*gny(ilevel)

end subroutine
!
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Projection function to go from coarse to fine.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!
real(pre) function project_phi_from_coarse(ilevel,id,iskip,xc,yc,zc)
  integer::id,b(8),ilevel,zskip,iadd,iskip,i
  real(pre)::x,y,z,xc,yc,zc,phi1,phi2,phi3,phi4,phi5,phi6

  x=grav_grid(id)%x;y=grav_grid(id)%y;z=grav_grid(id)%z

  zskip=gnx(ilevel)*gny(ilevel)
  if (xc < x) then
    if (yc < y) then
      if ( zc < z ) then

       b(1) = id-1-gnx(ilevel)-zskip

      else

       b(1) = id-1-gnx(ilevel)
 
      endif

    else ! x negative y positive
      if ( zc < z ) then

       b(1) = id-1-zskip

      else

       b(1) = id-1
 
      endif

    endif
    
  else ! x positive

    if (yc < y) then
      if ( zc < z ) then

        b(1) = id - gnx(ilevel)-zskip

      else

        b(1) = id - gnx(ilevel)
 
      endif
    else ! x & y positive
      if ( zc < z ) then
        b(1) = id - zskip
      else
        b(1) = id 
      endif
    endif

  endif

  b(2) = b(1)+1
  b(3) = b(1)+gnx(ilevel)
  b(4) = b(3)+1
  b(5) = b(1)+zskip
  b(6) = b(2)+zskip
  b(7) = b(3)+zskip
  b(8) = b(4)+zskip

  iadd=0
  if(xc<grav_grid(iskip+1)%x)iadd=1
  if(yc<grav_grid(iskip+1)%y)iadd=iadd+gnx(ilevel)
  if(zc<grav_grid(iskip+1)%z)iadd=iadd+zskip

  if(xc>grav_grid(iskip+ngrav_grid(ilevel))%x)iadd=iadd-1
  if(yc>grav_grid(iskip+ngrav_grid(ilevel))%y)iadd=iadd-gnx(ilevel)
  if(zc>grav_grid(iskip+ngrav_grid(ilevel))%z)iadd=iadd-zskip

  do i=1,8
    b(i)=b(i)+iadd
  enddo

  x=grav_grid(b(1))%x
  y=grav_grid(b(1))%y
  z=grav_grid(b(1))%z
  phi1 = grav_grid(b(1))%phi+(grav_grid(b(2))%phi-grav_grid(b(1))%phi)*(xc-x)/gdx(ilevel)
  phi2 = grav_grid(b(3))%phi+(grav_grid(b(4))%phi-grav_grid(b(3))%phi)*(xc-x)/gdx(ilevel)
  phi3 = grav_grid(b(5))%phi+(grav_grid(b(6))%phi-grav_grid(b(5))%phi)*(xc-x)/gdx(ilevel)
  phi4 = grav_grid(b(7))%phi+(grav_grid(b(8))%phi-grav_grid(b(7))%phi)*(xc-x)/gdx(ilevel)

  phi5=phi1+(phi2-phi1)*(yc-y)/gdy(ilevel)
  phi6=phi3+(phi4-phi3)*(yc-y)/gdy(ilevel)

  project_phi_from_coarse=phi5+(phi6-phi5)*(zc-z)/gdz(ilevel)

end function
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Basic framework for a multigrid solver using V cycles.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine walk_the_V(first)
  integer::igrid,b(6),iter,ilevel,inode,id,indx,iskip,ichild,ilower
  real(pre)::denom,alpha,err_loc,gradphi,resid,mloc
  real(pre)::dxloc,dyloc,dzloc,rho_loc,phi_loc
  real(pre)::phi0,phi1,phi2,phi3,phi4,phi5,phi6,rho0
  logical::active,first

  ilower=0
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(inode,id,indx,phi0,ichild,iskip,ilevel) &
!$OMP&PRIVATE(rho_loc,phi_loc)  

!
!***
! baselevel
!***
!
  if(first)then
    ilevel=1
!$OMP DO SCHEDULE(STATIC)
    do inode=1,ngrav_grid(ilevel)
       id=inode
       rho_loc=zero
       phi_loc=zero
       do ichild=1,nchild
         indx=grav_grid(id)%ichild(ichild)
         rho_loc=rho_loc+rhotot(indx)
         phi_loc=phi_loc+phi(indx)
       enddo
       grav_grid(id)%rho=rho_loc*0.125d0
       grav_grid(id)%phi=phi_loc*0.125d0
    enddo
!$OMP ENDDO
!$OMP BARRIER

!
!***
! other levels
!***
!
    do ilevel=2,nmulti
     iskip=0
     do inode=1,ilevel-1
       iskip=iskip+ngrav_grid(inode)
     enddo
!$OMP DO SCHEDULE(STATIC)
     do inode=1,ngrav_grid(ilevel)
       id=inode+iskip
       rho_loc=zero
       phi_loc=zero
       do ichild=1,nchild
         indx=grav_grid(id)%ichild(ichild)
         rho_loc=rho_loc+grav_grid(indx)%rho
         phi_loc=phi_loc+grav_grid(indx)%phi
       enddo
       grav_grid(id)%rho=rho_loc*0.125d0
       grav_grid(id)%phi=phi_loc*0.125d0
     enddo
!$OMP ENDDO
!$OMP BARRIER
    enddo
  else
   !print *,"ERROR: Trying to do multiple V passes."
   !print *,"Currently set for single V pass with cascading solution."
   !stop "Stopping in walk_the_V"
  endif
!$OMP END PARALLEL

  do ilevel = nmulti,1,-1
    maxerr=zero
     if(ilevel==nmulti)then
         call get_pot_at_higher_level(ilevel)
     else
         call get_pot_bc_at_higher_level(ilevel)
     endif
      maxerr=one
      iter=0
!$OMP PARALLEL DEFAULT(SHARED) PRIVATE(err_loc,iter) 
      err_loc=maxerr
      do while (err_loc>grav_err_tol_low)
!$OMP BARRIER
!$OMP MASTER
        maxerr=zero
!$OMP END MASTER
!$OMP BARRIER
        iter=iter+1
        call sor_potential_coarse(ilevel,err_loc)
!$OMP ATOMIC
        maxerr=max(maxerr,err_loc)
!$OMP BARRIER
       err_loc=maxerr
      enddo
!$OMP END PARALLEL
    iskip=0
    do inode=1,ilevel-1
      iskip=iskip+ngrav_grid(inode)
    enddo

!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(inode,id,indx,phi0,ichild) &
!$OMP&PRIVATE(phi_loc)  
!$OMP DO SCHEDULE(STATIC)
    do inode=1,ngrav_grid(ilevel)
      id=inode+iskip
      if(ilevel>1)then
        do ichild=1,nchild
         indx=grav_grid(id)%ichild(ichild)
         if(grav_grid(indx)%boundary)cycle
         phi0=project_phi_from_coarse(ilevel,id,iskip,grav_grid(indx)%x,grav_grid(indx)%y,grav_grid(indx)%z)
         grav_grid(indx)%phi=phi0
        enddo
      else
        do ichild=1,nchild
         indx=grav_grid(id)%ichild(ichild)
         if(grid(indx)%boundary==1.or.grid(indx)%boundary==2)cycle
         phi0=project_phi_from_coarse(ilevel,id,iskip,grid(indx)%x,grid(indx)%y,grid(indx)%z)
         phi(indx)=phi0
        enddo
      endif
    enddo
!$OMP ENDDO
!$OMP ENDPARALLEL
  enddo
 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Over relaxation on the coarse grid. Used in the multigridding.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine sor_potential_coarse(ilevel,err_loc)
  integer::igrid,b(6),iter,ilevel,inode,id,indx,iskip,ichild,redblack
  real(pre)::denom,alpha,err_loc,gradphi,resid,mloc
  real(pre)::dxloc,dyloc,dzloc,rho_loc,phi_loc
  real(pre)::phi0,phi1,phi2,phi3,phi4,phi5,phi6,rho0
  
   iskip=0
   do inode=1,ilevel-1
     iskip=iskip+ngrav_grid(inode)
   enddo
   err_loc=zero

!!!$OMP PARALLEL DEFAULT(SHARED) &
!!!$OMP&PRIVATE(inode,id,rho0,phi0,b) &
!!!$OMP&PRIVATE(phi1,phi2,phi3,phi4,phi5,phi6,resid) &
!!!!$OMP&REDUCTION(max:maxerr) 
   dxloc=gdx(ilevel)
   dyloc=gdy(ilevel)
   dzloc=gdz(ilevel)
   denom=(dyloc*dzloc/dxloc+dxloc*dzloc/dyloc+dxloc*dyloc/dzloc)*two
 
!$OMP DO SCHEDULE(STATIC) PRIVATE(inode,id,rho0,phi0,b) &
!$OMP&PRIVATE(phi1,phi2,phi3,phi4,phi5,phi6,resid) 
   do inode=1,ngrav_grid(ilevel)
     id=inode+iskip

     rho0=grav_grid(id)%rho
     phi0=grav_grid(id)%phi

     if(.not.grav_grid(id)%boundary)then
      call get_boundary_grav(ilevel,id,b)

      phi1=grav_grid(b(1))%phi
      phi2=grav_grid(b(2))%phi
      phi3=grav_grid(b(3))%phi
      phi4=grav_grid(b(4))%phi
      phi5=grav_grid(b(5))%phi
      phi6=grav_grid(b(6))%phi

      resid=( (phi1+phi2)*dxloc*dzloc/dyloc+(phi3+phi4)*dyloc*dzloc/dxloc &
           +(phi5+phi6)*dxloc*dyloc/dzloc &
           - phi0*denom-four*pi*rho0*dxloc*dyloc*dzloc )/(denom)

      grav_grid(id)%phi=phi0+resid*0.5d0
      
      if(phi0/=zero)then
        err_loc=max(err_loc,abs(resid/phi0))
      else
        err_loc=max(err_loc,abs(resid))
      endif
     endif
   enddo
!$OMP ENDDO
 end subroutine
! 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! 
! Over relaxation on the fine grid.  This implementation is not in use
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! 
!
 subroutine sor_potential_fine(maxiter)
  integer::igrid,b(6),iter,master_iter,maxiter
  real(pre)::denom,alpha,err_loc,gradphi,maxerr_loc,resid
  real(pre)::alpha0=1.0d0,dx2,dy2,dz2
  logical::active

   maxerr=zero
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&private(b,iter,dx2,dy2,dz2) &
!$OMP&private(denom,alpha,err_loc,active,gradphi,maxerr_loc,resid)

  alpha=alpha0 
  maxerr=one
  iter=0
  denom=(dy*dz/dx+dx*dz/dy+dx*dy/dz)*two
  maxerr_loc=maxerr
!$OMP MASTER
  maxerr=zero
!$OMP ENDMASTER
!$OMP BARRIER
  do while (iter<maxiter)
!$OMP DO SCHEDULE(STATIC) REDUCTION(max:maxerr)
   do igrid=1,ngrid
     if(grid(igrid)%boundary==1.or.grid(igrid)%boundary==2)cycle
     !if(grid(igrid)%boundary>0)cycle
     call get_boundary_wb(igrid,b) 

      resid=( (phi(b(1))+phi(b(2)))*dx*dz/dy+(phi(b(3))+phi(b(4)))*dy*dz/dx &
           +(phi(b(5))+phi(b(6)))*dx*dy/dz &
           - phi(igrid)*denom-four*pi*rhotot(igrid)*dx*dy*dz )/(denom)

      phi_new(igrid)=phi(igrid)+resid*0.5d0

     err_loc = abs( resid/(phi_new(igrid)))
     maxerr=max(err_loc,maxerr)
 
   enddo
!$OMP ENDDO
!$OMP BARRIER
   maxerr_loc=maxerr
!$OMP DO  SCHEDULE(STATIC) 
   do igrid=1,ngrid
     !if(grid(igrid)%boundary>0)cycle ! don't change the boundary or anchor  potential!
     if(grid(igrid)%boundary==1.or.grid(igrid)%boundary==2)cycle
       phi(igrid)=phi_new(igrid)!phi(igrid)+((alpha)*phi_new(igrid)) ! subtract residual
   enddo
!$OMP ENDDO
#ifdef VERBOSE
!
!
!$OMP MASTER
  print *, "#",iter,maxerr
  master_iter=iter
!$OMP END MASTER
#endif /* end ifdef VERBOSE */
!
!
  iter=iter+1
  enddo

!$OMP END PARALLEL
 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Driver for multigrid solver
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine vcycle_pot()
   integer::iter,iter2
   logical first

   iter=0
   maxerr=1d6
   first=.true.
   !do while (maxerr>grav_err_tol.and.iter<3)
   do while (iter<1)
     call walk_the_V(first)
     iter=iter+1
     first=.false.
   print *, "Walking the V (iter,maxerr): ",iter,maxerr
   enddo
   iter2=0
   maxerr=1d6
   call sor_potential2(iter2)
   print *, "Refining on fine grid (iter,maxerr): ",iter2,maxerr

 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Over relaxation on fine grid. This implementation is in use.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine sor_potential2(master_iter)
  integer::igrid,b(6),iter,master_iter
  real(pre)::denom,alpha,err_loc,gradphi,maxerr_loc,resid
  real(pre)::alpha0=1.0d0,dx2,dy2,dz2
  logical::active

   maxerr=zero
!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&private(b,iter,dx2,dy2,dz2) &
!$OMP&private(denom,alpha,err_loc,active,gradphi,maxerr_loc,resid)

  alpha=alpha0 
  maxerr=one
  iter=0
  denom=(dy*dz/dx+dx*dz/dy+dx*dy/dz)*two
  maxerr_loc=maxerr
  do while(maxerr_loc>grav_err_tol.and.iter<50000.or.iter<miniter)
!$OMP MASTER
  maxerr=zero
!$OMP ENDMASTER
!$OMP BARRIER
!$OMP DO SCHEDULE(STATIC) REDUCTION(max:maxerr)
   do igrid=1,ngrid
     !if(grid(igrid)%boundary>0)cycle
     if(grid(igrid)%boundary==1.or.grid(igrid)%boundary==2)cycle
     call get_boundary_wb(igrid,b) 

      resid=( (phi(b(1))+phi(b(2)))*dx*dz/dy+(phi(b(3))+phi(b(4)))*dy*dz/dx &
           +(phi(b(5))+phi(b(6)))*dx*dy/dz &
           - phi(igrid)*denom-four*pi*rhotot(igrid)*dx*dy*dz )/(denom)

      phi_new(igrid)=phi(igrid)+resid*0.99d0
      !phi_new(igrid)=phi(igrid)+resid*0.5d0

     err_loc = abs( resid/(phi(igrid)))
     maxerr=max(err_loc,maxerr)
 
   enddo
!$OMP ENDDO
!$OMP BARRIER
   maxerr_loc=maxerr
!$OMP DO  SCHEDULE(STATIC) 
   do igrid=1,ngrid
     !if(grid(igrid)%boundary>0)cycle ! don't change the boundary or anchor  potential!
     if(grid(igrid)%boundary==1.or.grid(igrid)%boundary==2)cycle
       phi(igrid)=phi_new(igrid)!phi(igrid)+((alpha)*phi_new(igrid)) ! subtract residual
   enddo
!$OMP ENDDO
   iter=iter+1
   if(mod(iter,1000)==0)then
     print *, "#WARNING SOR IS GOING THROUGH MANY ITERATIONS"
     print *, "#",iter,maxerr_loc,alpha
   endif
   alpha=alpha0 !- log10(min(one,maxerr))/ten
  enddo   
!$OMP BARRIER
!$OMP MASTER
  master_iter=iter
!$OMP END MASTER
!$OMP END PARALLEL
 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Add an external potential field. The default below is for a 
! Roche potential.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
 subroutine external_phi()! simple Roche potential
  integer::igrid
  real(pre)::x,y,z,omega2,pert
  real(pre)::x0,y0,z0,mbin,mbox
  real(pre)::xcom,ycom,zcom,plan,soft,r,rcycl


  x0=abs(object_x_displace)
  omega2=object_mass/x0**3
  x0dot=-sqrt(omega2)*x0/(6d0*pi)
  object_x_displace=object_x_displace-x0dot*dt
  print *,"Updated semi-major axis and rate: ",time,object_x_displace,x0dot


!$OMP PARALLEL DEFAULT(PRIVATE) SHARED(omega2,grid,phi,ngrid,dx,abin,object_mass,object_x_displace)
  mbox=object_mass
!$OMP DO SCHEDULE(STATIC)
  do igrid=1,ngrid
    x=grid(igrid)%x-object_x_displace
    y=grid(igrid)%y
    z=grid(igrid)%z
    r=sqrt(x*x+y*y+z*z)
    pert=-mbox/r-half*omega2*(x*x+y*y)
    phi(igrid)=phi(igrid)+pert
  enddo
!$OMP END DO
!$OMP END PARALLEL
 
 end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Test phi function. 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! 
 subroutine test_phi()
    integer::igrid,jgrid
    real(pre)::x,y,z,xx,yy,zz,testphi
    do igrid=1,ngrid
     x=grid(igrid)%x;y=grid(igrid)%y;z=grid(igrid)%z
    if(grid(igrid)%iz/=nz/2.or.grid(igrid)%iy/=ny/2)cycle
    testphi=zero
    do jgrid=1,ngrid
       xx=grid(jgrid)%x;yy=grid(jgrid)%y;zz=grid(jgrid)%z
       if(xx==x.and.yy==y.and.zz==z)then
         testphi=testphi-cons(1,jgrid)*dx*dy*dz/sqrt((quarter*dx)**2+(quarter*dz)**2+(quarter*dy)**2)
       else
         testphi=testphi-cons(1,jgrid)*dx*dy*dz/sqrt((x-xx)**2+(y-yy)**2+(z-zz)**2)
      endif
    enddo
    print *,grid(igrid)%x,grid(igrid)%y,grid(igrid)%z,cons(1,igrid),p(igrid),&
       u(1,igrid),u(2,igrid),u(3,igrid),phi(igrid),testphi,phi(igrid)/testphi,phi_new(igrid),&
       grid(igrid)%boundary
    enddo
    stop
 end subroutine
end module selfgravity

