# Setup build arguments
ARG AWS_CLI_VERSION=1.25.50
ARG TERRAFORM_VERSION=1.3.1
ARG PYTHON_MAJOR_VERSION=3.9
ARG DEBIAN_VERSION=bullseye-20220801-slim
ARG DEBIAN_FRONTEND=noninteractive

# Download Terraform binary
FROM debian:${DEBIAN_VERSION} as terraform
ARG TARGETARCH
ARG TERRAFORM_VERSION
RUN apt-get update
RUN apt-get install --no-install-recommends -y curl
RUN apt-get install --no-install-recommends -y ca-certificates=20210119
RUN apt-get install --no-install-recommends -y unzip=6.0-26+deb11u1
RUN apt-get install --no-install-recommends -y gnupg=2.2.27-2+deb11u2
WORKDIR /workspace
RUN curl --silent --show-error --fail --remote-name https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip
COPY security/hashicorp.asc ./
COPY security/terraform_${TERRAFORM_VERSION}** ./
RUN gpg --import hashicorp.asc
RUN gpg --verify terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig terraform_${TERRAFORM_VERSION}_SHA256SUMS
RUN sha256sum --check --strict --ignore-missing terraform_${TERRAFORM_VERSION}_SHA256SUMS
RUN unzip -j terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip

# Install AWS CLI using PIP
FROM debian:${DEBIAN_VERSION} as aws-cli
ARG AWS_CLI_VERSION
ARG PYTHON_MAJOR_VERSION
RUN apt-get update
RUN apt-get install -y --no-install-recommends python3=${PYTHON_MAJOR_VERSION}.2-3
RUN apt-get install -y --no-install-recommends python3-pip=20.3.4-4+deb11u1
RUN pip3 install --no-cache-dir setuptools==64.0.1
RUN pip3 install --no-cache-dir awscli==${AWS_CLI_VERSION}

# Install ROSA CLI from COPY
FROM debian:${DEBIAN_VERSION} as rosa
COPY rosa/rosa-linux.tar.gz /tmp/rosa-linux.tar.gz
RUN cd /tmp/;tar xvf rosa-linux.tar.gz

# Install HELM
FROM debian:${DEBIAN_VERSION} as helm
RUN apt-get update
RUN apt-get install -y --no-install-recommends git
RUN apt-get install --no-install-recommends -y curl
RUN apt-get install --no-install-recommends -y ca-certificates=20210119
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
RUN chmod 700 get_helm.sh
RUN ./get_helm.sh

# Install oc
FROM debian:${DEBIAN_VERSION} as oc
RUN apt-get update
RUN apt-get install --no-install-recommends -y curl
RUN apt-get install --no-install-recommends -y ca-certificates=20210119
WORKDIR /workspace
RUN curl --silent --show-error --fail --remote-name https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
RUN tar xvf openshift-client-linux.tar.gz

# Build final image
FROM debian:${DEBIAN_VERSION} as build
LABEL maintainer="bgauduch@github"
ARG PYTHON_MAJOR_VERSION
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates=20210119\
    git \
    jq=1.6-2.1 \
    python3=${PYTHON_MAJOR_VERSION}.2-3 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_MAJOR_VERSION} 1
RUN apt-get install --no-install-recommends -y zsh
WORKDIR /workspace
COPY --from=terraform /workspace/terraform /usr/local/bin/terraform
COPY --from=aws-cli /usr/local/bin/aws* /usr/local/bin/
COPY --from=aws-cli /usr/local/lib/python${PYTHON_MAJOR_VERSION}/dist-packages /usr/local/lib/python${PYTHON_MAJOR_VERSION}/dist-packages
COPY --from=aws-cli /usr/lib/python3/dist-packages /usr/lib/python3/dist-packages
COPY --from=rosa /tmp/rosa /usr/local/bin/rosa
COPY --from=helm /usr/local/bin/helm /usr/local/bin/helm
COPY --from=oc /workspace/oc /usr/local/bin/oc
COPY --from=oc /workspace/kubectl /usr/local/bin/kubectl 

RUN groupadd --gid 1001 nonroot \
  # user needs a home folder to store aws credentials
  && useradd --gid nonroot --create-home --uid 1001 nonroot \
  && chown nonroot:nonroot /workspace
USER nonroot

CMD ["bash"]
