ARG BASE_IMAGE=debian:sid
FROM ${BASE_IMAGE}
# The rewrite of the devops-cli dev container: docker-in-docker stops on the sid codename.
# On other images, the codename is not forky and the file keeps its content.
RUN sed -i 's/VERSION_CODENAME=forky/VERSION_CODENAME=trixie/' /etc/os-release
