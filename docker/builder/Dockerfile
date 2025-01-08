FROM debian:12
LABEL authors="Michael Ketchel <michael.ketchel@gmail.com>"

RUN apt update && apt satisfy --yes " \
    kpartx, \
    bash, \
    parted, \
    dosfstools, \
    wget, \
    libext2fs2, \
    zlib1g, \
    sudo, \
    unzip, \
    cpio, \
    advancecomp, \
    vim \
    "

ENV EDITOR=vim
WORKDIR /mnt

CMD ["bash"]