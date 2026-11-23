ARG BASE_IMAGE=debian:sid
FROM ${BASE_IMAGE}
# docker-in-docker stops on the sid codename forky, so this rewrites it to trixie.
# On other images, the codename is not forky and the file keeps its content.
RUN sed -i 's/VERSION_CODENAME=forky/VERSION_CODENAME=trixie/' /etc/os-release
