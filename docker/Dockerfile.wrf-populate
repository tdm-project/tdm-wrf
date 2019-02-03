FROM alpine:latest

COPY populate /populate
RUN apk add --no-cache curl bash\
    && chmod a+x /populate

ENTRYPOINT ["/populate"]

