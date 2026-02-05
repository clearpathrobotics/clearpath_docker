FROM ros:jazzy-ros-base AS cpr-jazzy-ros-base

# Fix issue with new ubuntu user
RUN userdel -r ubuntu

ENV DEBIAN_FRONTEND=noninteractive
RUN echo '\
  APT::Install-Recommends "0";\n\
  APT::Install-Suggests "0";\n\
  ' > /etc/apt/apt.conf.d/01norecommend

RUN apt-get update && apt-get install -y \
  wget \
  git \
  python3-yaml \
  curl \
  && apt-get upgrade -y --with-new-pkgs \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

# # Index both private and public images
WORKDIR /etc/ros/rosdep
# Random fork below for python3.  Should make our own fork from that.
RUN git clone https://github.com/mikekaram/rosdep-generator.git \
  && python3 rosdep-generator/rosdep-generator \
  --org clearpathrobotics \
  --repo public-rosdistro \
  --distro jazzy \
  && rm -rf rosdep-generator
RUN echo "yaml file:///etc/ros/rosdep/clearpathrobotics-public-rosdistro-jazzy.yaml jazzy" > /etc/ros/rosdep/sources.list.d/90-clearpathrobotics-public-rosdistro-jazzy.list

RUN wget https://packages.clearpathrobotics.com/public.key -qO - | apt-key add -
RUN sh -c 'echo "deb https://packages.clearpathrobotics.com/stable/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/clearpath-latest.list'
RUN wget https://raw.githubusercontent.com/clearpathrobotics/public-rosdistro/master/rosdep/50-clearpath.list -O /etc/ros/rosdep/sources.list.d/50-clearpath.list

ENV DEBIAN_FRONTEND=

LABEL com.clearpathrobotics.vendor="Clearpath Robotics"

FROM cpr-jazzy-ros-base AS cpr-jazzy-dev
RUN apt-get update && apt-get install -y \
  python3-pip \
  python3-pep8 \
  python3-autopep8 \
  pylint \
  bash-completion \
  nano \
  vim \
  inetutils-ping \ 
  ros-build-essential \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create a non-root user
RUN groupadd --gid $USER_GID $USERNAME \
  && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \

  ENV DEBIAN_FRONTEND=noninteractive
  # [Optional] Add sudo support for the non-root user
  && apt-get update \
  && apt-get install -y sudo \
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME\
  && chmod 0440 /etc/sudoers.d/$USERNAME \
  # Cleanup
  && rm -rf /var/lib/apt/lists/* \
  && echo "source /usr/share/bash-completion/completions/git" >> /home/$USERNAME/.bashrc \
  && echo "if [ -f /opt/ros/${ROS_DISTRO}/setup.bash ]; then source /opt/ros/${ROS_DISTRO}/setup.bash; fi" >> /home/$USERNAME/.bashrc

# set bash history location so it can be stored locally
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME /commandhistory \
    && echo "$SNIPPET" >> "/home/$USERNAME/.bashrc"

ENV DEBIAN_FRONTEND=
