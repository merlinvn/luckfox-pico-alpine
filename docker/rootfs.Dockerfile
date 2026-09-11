FROM arm32v7/alpine:3.20

COPY bootstrap.sh /bootstrap.sh
RUN chmod 0755 /bootstrap.sh

ENTRYPOINT ["/bootstrap.sh"]
