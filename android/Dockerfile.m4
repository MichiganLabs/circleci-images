#
format(`# DO NOT MODIFY THIS FILE.  THIS FILE HAS BEEN AUTOGENERATED')
#
FROM openjdk:8-jdk-slim

LABEL maintainer="jfriend@michiganlabs.com"

# Initial Command run as `root`.

ADD https://raw.githubusercontent.com/circleci/circleci-images/master/android/bin/circle-android /bin/circle-android
RUN chmod +rx /bin/circle-android

# Skip the first line of the Dockerfile template (FROM ${BASE})
syscmd(`tail -n +2 ../shared/images/Dockerfile-basic.template')

# Now commands run as user `circleci`

# Switching user can confuse Docker's idea of $HOME, so we set it explicitly
ENV HOME /home/circleci

RUN sudo apt-get update -qqy && sudo apt-get install -qqy \
        python-dev \
        python-setuptools \
        apt-transport-https \
        lsb-release

RUN sudo apt-get install gcc-multilib && \
    sudo easy_install -U pip && \
    sudo pip uninstall crcmod && \
    sudo pip install -U crcmod

ARG sdk_version=sdk-tools-linux-3859397.zip
ARG android_home=/opt/android/sdk

# SHA-256 444e22ce8ca0f67353bda4b85175ed3731cae3ffa695ca18119cbacef1c1bea0

RUN sudo apt-get update && \
    sudo apt-get install --yes \
        xvfb lib32z1 lib32stdc++6 build-essential \
        libcurl4-openssl-dev libglu1-mesa libxi-dev libxmu-dev \
        libglu1-mesa-dev

# Install Ruby
RUN cd /tmp && wget -O ruby-install-0.6.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.6.1.tar.gz && \
    tar -xzvf ruby-install-0.6.1.tar.gz && \
    cd ruby-install-0.6.1 && \
    sudo make install && \
    ruby-install --cleanup ruby 2.4.3 && \
    rm -r /tmp/ruby-install-*

ENV PATH ${HOME}/.rubies/ruby-2.4.3/bin:${PATH}
RUN echo 'gem: --env-shebang --no-rdoc --no-ri' >> ~/.gemrc && gem install bundler

# Install crashlytics tooklit
RUN mkdir -p $HOME/Library/CrashlyticsAndroid && \
    curl --silent --show-error --location --fail --retry 3 --output /tmp/crashlytics.zip https://ssl-download-crashlytics-com.s3.amazonaws.com/android/ant/crashlytics.zip && \
    unzip /tmp/crashlytics.zip -d $HOME/Library/CrashlyticsAndroid && \
    rm -f /tmp/crashlytics.zip

# Download and install Android SDK
RUN sudo mkdir -p ${android_home} && \
    sudo chown -R circleci:circleci ${android_home} && \
    curl --silent --show-error --location --fail --retry 3 --output /tmp/${sdk_version} https://dl.google.com/android/repository/${sdk_version} && \
    unzip -q /tmp/${sdk_version} -d ${android_home} && \
    rm /tmp/${sdk_version}

# Set environmental variables
ENV ANDROID_HOME ${android_home}
ENV ADB_INSTALL_TIMEOUT 120
ENV PATH=${ANDROID_HOME}/emulator:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${PATH}

RUN mkdir ~/.android && echo '### User Sources for Android SDK Manager' > ~/.android/repositories.cfg

RUN yes | sdkmanager --licenses && sdkmanager --update

# Update SDK manager and install system image, platform and build tools
RUN sdkmanager \
  "tools" \
  "platform-tools" \
  "emulator"

RUN sdkmanager \
  "build-tools;28.0.0" \
  "build-tools;28.0.2"

# API_LEVEL string gets replaced by m4
RUN sdkmanager "platforms;android-API_LEVEL"
