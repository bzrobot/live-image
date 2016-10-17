#! /bin/bash
set -eu

################################################################################
# The Real-Time eXperiment Interface (RTXI)
#
# Copyright (C) 2011 Georgia Institute of Technology, University of Utah, Weill 
# Cornell Medical College
#
# This program is free software: you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation, either version 3 of the License, or (at your option) any later 
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more 
# details.
#
# You should have received a copy of the GNU General Public License along with 
# this program. If not, see <http://www.gnu.org/licenses/>.
################################################################################

###############################################################################
# Mount ramfs and virtual filesystems. Prepare chroot environment. 
###############################################################################

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C

###############################################################################
# Set global variables. 
###############################################################################

RTXI_VERSION="$1"
XENOMAI_VERSION="$2"
KERNEL_VERSION="$3"
UBUNTU_VERSION="$4"
UBUNTU_FLAVOR="$5"

if [ "$RTXI_VERSION" = "2.1" ]; then
  QWT_VERSION=6.1.3
elif [ "$RTXI_VERSION" = "2.0" ]; then
  QWT_VERSION=6.1.0
fi

HDF_VERSION=1.8.4

cd $HOME

# Locations for compiling RTXI source code
BASE=$HOME/rtxi
SCRIPTS=$BASE/scripts
DEPS=$BASE/deps
if [ "$RTXI_VERSION" = "2.1" ]; then
  HDF=$DEPS
  QWT=$DEPS
elif [ "$RTXI_VERSION" = "2.0" ]; then
  HDF=$DEPS/hdf
  QWT=$DEPS/qwt
  DYN=$DEPS/dynamo
fi

INCLUDES=$DEPS/rtxi_includes

# Installation locations for RTXI
RTXI_INCLUDES=/usr/local/lib/rtxi_includes
RTXI_MODULES=/usr/local/lib/rtxi_modules

###############################################################################
# Enable deb-src and the universe/multiverse repositories. 
###############################################################################

add-apt-repository -s "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main universe restricted multiverse"

###############################################################################
# Install package dependencies. (DO NOT UPGRADE EXISTING PACKAGES!)
###############################################################################

apt-get update
# apt-get -y upgrade <- this has created unbootable live CDs before. 
apt-get -y install git

# check whether to build v2.0 or v2.1. 
git clone https://github.com/rtxi/rtxi
cd rtxi

if [ "$RTXI_VERSION" == "2.1" ]; then
  if test `echo "$XENOMAI_VERSION" | grep -c "3."` -ne 0; then
    git checkout rttweak
  fi
  apt-get -y install \
    autotools-dev automake libtool kernel-package gcc g++ gdb fakeroot crash \
    kexec-tools makedumpfile kernel-wedge libncurses5-dev libelf-dev \
    binutils-dev libgsl0-dev libboost-dev vim emacs git lshw stress gksu \
    libqt5svg5-dev libqt5opengl5 libqt5gui5 libqt5core5a libqt5xml5 \
    libqt5network5 qtbase5-dev qt5-default libgles2-mesa-dev gdebi \
    libqt5designer5 qttools5-dev libqt5designercomponents5 qttools5-dev-tools \
    libgit2-dev libmarkdown2-dev
elif [ "$RTXI_VERSION" == "2.0" ]; then
  git checkout v2.0-xenomai-2.6.4 
  apt-get -y install \
    autotools-dev automake libtool kernel-package g++ gcc gdb fakeroot crash \
    kexec-tools makedumpfile kernel-wedge git-core libncurses5 libncurses5-dev \
    libelf-dev binutils-dev libgsl0-dev vim stress lshw libboost-dev gksu \
    qt4-dev-tools libqt4-dev libqt4-opengl-dev gdebi r-base r-cran-ggplot2 \
    r-cran-reshape2 r-cran-hdf5 r-cran-plyr r-cran-scales
else 
  echo "Invalid RTXI version set"
  exit 1
fi
  
###############################################################################
# Install gridExtra for v2.0 (it'll get its own deb package in 16.04). Be 
# careful about version numbers. If gridExtra package updates, this link might 
# break. 
###############################################################################

if [ "$RTXI_VERSION" == "2.0" ]; then
  cd $DEPS
  wget https://cran.r-project.org/src/contrib/Archive/gridExtra/gridExtra_0.9.1.tar.gz
  R CMD INSTALL gridExtra_0.9.1.tar.gz
fi

###############################################################################
# Install dynamo for v2.0
###############################################################################

if [ "$RTXI_VERSION" == "2.0" ]; then
  echo "Installing DYNAMO utility..."
  apt-get -y install mlton
  
  cd $DYN
  mllex dl.lex
  mlyacc dl.grm
  mlton dynamo.mlb
  cp dynamo /usr/bin/
fi

###############################################################################
# Install HDF5
###############################################################################

echo "----->Checking for HDF5"
cd $HDF
tar xf hdf5-$HDF_VERSION.tar.bz2
cd hdf5-$HDF_VERSION
./configure --prefix=/usr
make -sj`nproc`
make install

###############################################################################
# Install Qwt
###############################################################################

echo "----->Installing Qwt..."
cd $QWT
tar xf qwt-$QWT_VERSION.tar.bz2
cd qwt-$QWT_VERSION
qmake qwt.pro
make -sj`nproc`
make install
cp -vf /usr/local/qwt-$QWT_VERSION/lib/libqwt.so.$QWT_VERSION /usr/lib/.
ln -sf /usr/lib/libqwt.so.$QWT_VERSION /usr/lib/libqwt.so
ldconfig

###############################################################################
# Install rtxi_includes and make it writable from all users in group "adm"
###############################################################################

if [ "$RTXI_VERSION" == "2.0" ]; then
  rsync -a $DEPS/rtxi_includes /usr/local/lib/.
  find $BASE/plugins/. -name "*.h" -exec cp -t $RTXI_INCLUDES/ {} +
  setfacl -Rm g:adm:rwX,d:g:adm:rwX $RTXI_INCLUDES
fi

###############################################################################
# Install RT kernel (from the deb files you provided)
###############################################################################

cd ~/
gdebi -n linux-image*.deb
gdebi -n linux-headers*.deb

###############################################################################
# Install Xenomai
###############################################################################

# Code goes here. 
cd $DEPS
wget https://xenomai.org/downloads/xenomai/stable/xenomai-$XENOMAI_VERSION.tar.bz2
tar xf xenomai-$XENOMAI_VERSION.tar.bz2

mkdir build
cd build
if [[ "$XENOMAI_VERSION" =~ "2.6" ]]; then
  ../xenomai-$XENOMAI_VERSION/configure \
    --enable-shared --enable-smp --enable-x86-sep
elif [[ "$XENOMAI_VERSION" =~ "3." ]]; then
  ../xenomai-$XENOMAI_VERSION/configure \
    --with-core=cobalt --enable-pshared --enable-smp --enable-x86-vsyscall \
    --enable-dlopen-libs
else
  echo "Xenomai version specified in the \$XENOMAI_VERSION variable needs to be 2.6.x or 3.x"
  exit 1
fi

make -s
make install

###############################################################################
# Install RTXI and all the icons, config files, etc. that go with it. 
###############################################################################

cd $BASE

# Theming for Qt4 (v2.0 only)
if [ "$RTXI_VERSION" == "2.0" ]; then
  cp ../handy-scripts/rtxi_utils/ui-tweaks/main.cpp src/main.cpp
  cp ../handy-scripts/rtxi_utils/ui-tweaks/default_gui_model.cpp src/default_gui_model.cpp
  if [ ! -d /root/.config ]; then mkdir /root/.config; fi
  cp -f scripts/icons/Trolltech.conf /root/.config/ 
fi

./autogen.sh
./configure --enable-xenomai --enable-analogy 
make -sj`nproc` -C ./
make install -C ./

# For v2.0, put all the icons, config files, etc. into place manually.
if [ "$RTXI_VERSION" == "2.0" ]; then
  cp -f libtool /usr/local/lib/rtxi/
  cp -f scripts/icons/RTXI-icon.png /usr/local/lib/rtxi/
  cp -f scripts/icons/RTXI-widget-icon.png /usr/local/lib/rtxi/
  cp -f scripts/rtxi.desktop /usr/share/applications/
  chmod +x /usr/share/applications/rtxi.desktop
  cp -f rtxi.conf /etc/rtxi.conf
  cp -f /usr/xenomai/sbin/analogy_config /usr/sbin/
fi

# Add rule to load analogy driver at boot with systemd (xenial) or sysvinit 
# (trusty). 
if [ $(lsb_release -sc) == "xenial" ]; then
  sudo cp -f scripts/services/rtxi_load_analogy.service /etc/systemd/system/
  sudo systemctl enable rtxi_load_analogy.service
else
  sudo cp -f scripts/services/rtxi_load_analogy /etc/init.d/
  sudo update-rc.d rtxi_load_analogy defaults
fi

ldconfig

###############################################################################
# Create a shared folder and install some modules in it. 
###############################################################################

mkdir $RTXI_MODULES
setfacl -Rm g:adm:rwX,d:g:adm:rwX $RTXI_MODULES

# Clone and install some modules
mkdir $RTXI_MODULES
cd $RTXI_MODULES
git clone https://github.com/RTXI/analysis-tools.git
git clone https://github.com/RTXI/iir-filter.git
git clone https://github.com/RTXI/fir-window.git
git clone https://github.com/RTXI/sync.git
git clone https://github.com/RTXI/mimic-signal.git
git clone https://github.com/RTXI/signal-generator.git
git clone https://github.com/RTXI/ttl-pulses.git
git clone https://github.com/RTXI/wave-maker.git
git clone https://github.com/RTXI/noise-generator.git

for dir in *; do
  if [ -d "$dir" ]; then
    cd "$dir"
    make -j`nproc`
    make install
    make clean
    git clean -xdf
    cd ../
  fi
done

# Disable the Public and Templates directories from being formed
sed -i 's/PUBLICSHARE/#PUBLICSHARE/g' /etc/xdg/user-dirs.defaults
sed -i 's/TEMPLATE/#TEMPLATE/g' /etc/xdg/user-dirs.defaults

###############################################################################
# Install zsh and some zsh plugins. 
###############################################################################

apt-get -y install zsh zsh-syntax-highlighting zsh-antigen

###############################################################################
# Install some GTK and icon themes. 
###############################################################################

cd ~/

apt-get -y install libgtk-3-dev

GLIB_OVERRIDE="/usr/share/glib-2.0/schemas/20_ubuntu-gnome-default-settings.gschema.override"

if test `echo "$UBUNTU_VERSION" | grep -c "16.04"` -ne 0; then
  apt-get -y install libgtk-3-dev ruby-bundler ruby-sass npm nodejs
  ln -s /usr/bin/nodejs /usr/bin/node
  npm -g install gulp grunt-cli bower

  # Install Arc GTK theme.
  git clone https://github.com/horst3180/arc-theme
  cd arc-theme
  ./autogen.sh --prefix=/usr && gulp && make && make install
  cd ../
  rm -rf arc-theme

  # Install Numix icons. 
  git clone https://github.com/numixproject/numix-icon-theme
  git clone https://github.com/numixproject/numix-icon-theme-circle
  #git clone https://github.com/numixproject/numix-folders
  cp -r numix-icon-theme/Numix /usr/share/icons/
  cp -r numix-icon-theme-circle/Numix-Circle /usr/share/icons/
  #cd numix-folders
  #sed -i "s/chown/#chown/g" numix-folders
  # style=6; custom; primary=3FD59F; secondary=2EAF81; tertiary=2E3436 
  #echo "style=6; custom; primary=3FD59F; secondary=2EAF81; tertiary=2E3436" 
  #./numix-folders -t
  #rm -rf numix-folders
  rm -rf numix-icon-theme
  rm -rf numix-circle-icon-theme
	
  # Override GNOME defaults. 
  sed -i 's/^icon-theme="Adwaita"/icon-theme="Numix-Circle"/g' $GLIB_OVERRIDE
  sed -i 's/^gtk-theme="Adwaita"/gtk-theme="Arc"/g' $GLIB_OVERRIDE
  sed -i 's/^theme="Adwaita"/theme="Arc"/g' $GLIB_OVERRIDE
  glib-compile-schemas /usr/share/glib-2.0/schemas/

elif test `echo "$UBUNTU_VERSION" | grep -c "14.04"` -ne 0; then
  # Install theme pack that includes Numix
  apt-get -y install shimmer-themes

  # Install Numix icons. 
  git clone https://github.com/numixproject/numix-icon-theme
  git clone https://github.com/numixproject/numix-icon-theme-circle
  cp -r numix-icon-theme/Numix /usr/share/icons/
  cp -r numix-icon-theme-circle/Numix-Circle /usr/share/icons/
  rm -rf numix-icon-theme
  rm -rf numix-circle-icon-theme
	
  # Override GNOME defaults. 
  sed -i 's/^icon-theme="Adwaita"/icon-theme="Numix-Circle"/g' $GLIB_OVERRIDE
  sed -i 's/^gtk-theme="Adwaita"/gtk-theme="Numix"/g' $GLIB_OVERRIDE
  sed -i 's/^theme="Adwaita"/theme="Numix"/g' $GLIB_OVERRIDE
  glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

cd ~/

###############################################################################
# Cleanup and exit chroot.
###############################################################################

cd ~/
rm -r rtxi
if [ "$RTXI_VERSION" == "2.0" ]; then rm -r handy-scripts; fi
rm -r *.deb
echo "" > /run/resolvconf/resolv.conf
apt-get clean
umount /proc /sys /dev/pts

echo "We are now done chrooting."
exit
