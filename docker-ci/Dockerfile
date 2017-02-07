FROM docker:1.11

# set labels for builder
LABEL build.publish.majorversion="1"
LABEL build.publish.minorversion="1.11"
LABEL build.publish.imagebase="docker"

ENV AWSCLI_VER 1.11.38
ENV ENVELOPE_VERSION 0.3.1
ENV LANG en_US.UTF-8

# Install required packages
RUN apk add --no-cache \
      make \
      git


# Install required packages for golang
RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      git \
      gnupg \
      groff \
      less \
      make \
      python \
      py-pip \
      unzip

# Install the AWS packages
RUN \
    mkdir -p /aws && \
    # Install and upgrade Pip
    pip install --upgrade pip && \
    # Install AWS cli
    pip install awscli==${AWSCLI_VER} && \
    apk --purge -v del py-pip

# Add some full 360 bits
RUN \
  mkdir -p /root/.gnupg \
  && echo "allow-loopback-pinentry" >> /root/.gnupg/gpg-agent.conf \
  && echo "pinentry-mode loopback" >> /root/.gnupg/gpg.conf \
  && curl -s -o /tmp/envelope.zip \
       http://releases.full360.com/envelope/envelope_${ENVELOPE_VERSION}_linux_amd64.zip \
  && unzip /tmp/envelope.zip -d /usr/local/bin/ \
  && rm /tmp/envelope.zip

RUN curl -s -o /usr/local/share/ca-certificates/full360-root-ca.crt \
       http://pki.full360.com/full360-root-ca.crt  \
    && update-ca-certificates \
