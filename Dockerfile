# note: this would require --privileged
# FROM ubuntu:bionic
# ARG DISTRO=bionic

ARG DISTRO=focal
ARG CLANG_MAJOR=10
ARG QT_MAJOR=514
ARG QT_VERSION=5.14.2
ARG QBS_BRANCH=v1.16.0
ARG RUNTIME_APT
ARG RUNTIME_XENIAL="libicu55 libglib2.0-0"
ARG RUNTIME_FOCAL="libicu66 libglib2.0-0 libpcre2-16-0"

FROM ubuntu:${DISTRO} AS clang_base
ARG DISTRO
ARG CLANG_MAJOR

ENV \
  APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 \
  DEBIAN_FRONTEND=noninteractive \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8

# install Clang (https://apt.llvm.org/)
RUN \
  apt-get update --quiet \
  && apt-get install --yes --quiet --no-install-recommends wget gnupg apt-transport-https ca-certificates \
  && wget -qO - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - \
  && echo "deb http://apt.llvm.org/${DISTRO}/ llvm-toolchain-${DISTRO}-${CLANG_MAJOR} main" > /etc/apt/sources.list.d/llvm.list \
  && apt-get update --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
  clang-${CLANG_MAJOR} \
  lld-${CLANG_MAJOR} \
  libc++abi-${CLANG_MAJOR}-dev \
  libc++-${CLANG_MAJOR}-dev \
  && update-alternatives --install /usr/bin/cc cc /usr/bin/clang-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld-${CLANG_MAJOR} 10 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 20 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.bfd 30 \
  && c++ --version \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

# compile & install Qbs
FROM clang_base AS qbs-build
ARG DISTRO
ARG QT_MAJOR
ARG QT_VERSION
ARG QBS_BRANCH

ENV \
  QTDIR=/opt/qt${QT_MAJOR} \
  PATH=/opt/qt${QT_MAJOR}/bin:/opt/qbs/bin:${PATH} \
  LD_LIBRARY_PATH=/opt/qt${QT_MAJOR}/lib/x86_64-linux-gnu:/opt/qt${QT_MAJOR}/lib:${LD_LIBRARY_PATH} \
  PKG_CONFIG_PATH=/opt/qt${QT_MAJOR}/lib/pkgconfig:${PKG_CONFIG_PATH}

RUN \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C65D51784EDC19A871DBDBB710C56D0DE9977759 \
  && echo "deb http://ppa.launchpad.net/beineri/opt-qt-${QT_VERSION}-${DISTRO}/ubuntu ${DISTRO} main" > /etc/apt/sources.list.d/qt.list \
  && apt-get update --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
  git \
  make \
  libgl1-mesa-dev \
  qt${QT_MAJOR}script \
  qt${QT_MAJOR}base \
  qt${QT_MAJOR}tools \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

RUN \
  cd /opt \
  && git clone --depth 1 -b ${QBS_BRANCH} https://github.com/qbs/qbs.git qbs-src \
  && cd /opt/qbs-src \
  && qmake -r qbs.pro \
  -spec linux-clang-libc++ \
  LIBS+=-lc++abi \
  QBS_INSTALL_PREFIX=/opt/qbs \
  CONFIG+=qbs_no_dev_install \
  CONFIG+=release CONFIG-=debug \
  && make -j install \
  && rm -rf /opt/qbs-src

# final qbs-clang (no Qt)
FROM clang_base AS qbs-clang
ARG DISTRO
ARG CLANG_MAJOR
ARG QT_MAJOR
ARG QBS_BRANCH
ARG RUNTIME_APT
ARG RUNTIME_FOCAL
ARG RUNTIME_XENIAL

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + Qbs ${QBS_BRANCH}"

COPY --from=qbs-build /opt/qbs /opt/qbs
COPY --from=qbs-build /opt/qt${QT_MAJOR}/bin /opt/qt${QT_MAJOR}/bin
COPY --from=qbs-build /opt/qt${QT_MAJOR}/lib /opt/qt${QT_MAJOR}/lib
ENV \
  PATH=/opt/qbs/bin:${PATH} \
  LD_LIBRARY_PATH=/opt/qt${QT_MAJOR}/lib/x86_64-linux-gnu:/opt/qt${QT_MAJOR}/lib:${LD_LIBRARY_PATH}

RUN \
  apt-get update --quiet \
  && if [ "${RUNTIME_APT}" != "" ] ; then export "RUNTIME_APT2=${RUNTIME_APT}" ; \
  elif [ "${DISTRO}" = "xenial" ] ; then export "RUNTIME_APT2=${RUNTIME_XENIAL}" ; \
  else export "RUNTIME_APT2=${RUNTIME_FOCAL}" ; \
  fi \
  && apt-get install --yes --quiet --no-install-recommends ${RUNTIME_APT2} \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/* \
  && qbs setup-toolchains --type clang /usr/bin/clang++ clang \
  && qbs config defaultProfile clang \
  && qbs config --list

ENTRYPOINT ["/opt/qbs/bin/qbs"]

# final qbs-clang-qt (with Qt)
FROM clang_base AS qbs-clang-qt
ARG DISTRO
ARG CLANG_MAJOR
ARG QT_MAJOR
ARG QT_VERSION
ARG QBS_BRANCH
ARG RUNTIME_APT
ARG RUNTIME_FOCAL
ARG RUNTIME_XENIAL

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + Qt ${QT_VERSION} + Qbs ${QBS_BRANCH}"

COPY --from=qbs-build /opt/qbs /opt/qbs
COPY --from=qbs-build /opt/qt${QT_MAJOR} /opt/qt${QT_MAJOR}
ENV \
  QTDIR=/opt/qt${QT_MAJOR} \
  PATH=/opt/qt${QT_MAJOR}/bin:/opt/qbs/bin:${PATH} \
  LD_LIBRARY_PATH=/opt/qt${QT_MAJOR}/lib/x86_64-linux-gnu:/opt/qt${QT_MAJOR}/lib:${LD_LIBRARY_PATH} \
  PKG_CONFIG_PATH=/opt/qt${QT_MAJOR}/lib/pkgconfig:${PKG_CONFIG_PATH}

RUN \
  apt-get update --quiet \
  && if [ "${RUNTIME_APT}" != "" ] ; then export "RUNTIME_APT2=${RUNTIME_APT}" ; \
  elif [ "${DISTRO}" = "xenial" ] ; then export "RUNTIME_APT2=${RUNTIME_XENIAL}" ; \
  else export "RUNTIME_APT2=${RUNTIME_FOCAL}" ; \
  fi \
  && apt-get install --yes --quiet --no-install-recommends ${RUNTIME_APT2} \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/* \
  && qbs setup-toolchains --detect \
  && qbs setup-qt /opt/qt${QT_MAJOR}/bin/qmake qt${QT_MAJOR} \
  && qbs config defaultProfile qt${QT_MAJOR} \
  && qbs config --list

ENTRYPOINT ["/opt/qbs/bin/qbs"]
