#!/bin/bash
[[ -z "$PLATFORMS_ALPINE" ]] || BUILD_TARGET_PLATFORMS=$PLATFORMS_ALPINE
[[ -z "$BUILD_TARGET_PLATFORMS" ]] && BUILD_TARGET_PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7"

_platform_tag() { echo "$1"|sed 's~/~_~g' ;};
_oneline()               { tr -d '\n' ; } ;
_buildx_arch()           { case "$(uname -m)" in aarch64) echo linux/arm64;; x86_64) echo linux/amd64 ;; armv7l|armv7*) echo linux/arm/v7;; armv6l|armv6*) echo linux/arm/v6;;  esac ; } ;

test -e dropbear-src || git clone https://github.com/mkj/dropbear.git dropbear-src

mkdir builds
startdir=$(pwd)

#IMAGETAG_SHORT=alpine
for IMAGETAG_SHORT in alpine ubuntu-bionic;do
REGISTRY_HOST=ghcr.io
REGISTRY_PROJECT=thefoundation-builder
PROJECT_NAME=hardened-dropbear
[[ -z "$GH_IMAGE_NAME" ]] && IMAGETAG=$( echo "${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}" |tr  '[:upper:]' '[:lower:]' )
[[ -z "$GH_IMAGE_NAME" ]] || IMAGETAG=$( echo $GH_IMAGE_NAME":"${IMAGETAG_SHORT} |tr  '[:upper:]' '[:lower:]' )




#docker build . --progress plain -f Dockerfile.alpine -t $IMAGETAG
ALLARCH=$(_buildx_arch)
for BUILDARCH in $ALLARCH ;do
TARGETARCH=$(_platform_tag $BUILDARCH  )
TARGETDIR=builds/${IMAGETAG_SHORT}"_"$TARGETARCH
echo "building to "$TARGETDIR
mkdir -p "$TARGETDIR"
cd "$TARGETDIR"
mkdir build
(
    cd build
    cp ${startdir}/build-bear.sh . -v
    test -e ccache.tgz && rm ccache.tgz
    docker export $(docker create --name cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH} ${IMAGETAG}_${TARGETARCH}_builder /bin/false ) |tar xv ccache.tgz ;docker rm cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH}
     test -e ccache.tgz ||    (  (echo FROM ${IMAGETAG}_${TARGETARCH}_builder;echo RUN echo yocacheme) | timeout 5000 time docker buildx build  --output=type=local,dest=/tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH}   --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage   --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache -t  ${IMAGETAG}_${TARGETARCH}_builder $buildstring -f - ) ;
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder && test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}/ccache.tgz && mv /tmp/buildout_${IMAGETAG}_${TARGETARCH}/ccache.tgz .
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder && rm -rf "/tmp/buildout_${IMAGETAG}_${TARGETARCH}"    
    test -e ccache.tgz || ( mkdir .tmpempty ;echo 123 .tmpempty/file;tar cvzf ccache.tgz .tmpempty )
    test -e dropbear-src || cp -rau ${startdir}/dropbear-src .
    test -e .tmpempty && rm -rf .tmpempty
)


buildstring=build
DFILENAME=$startdir/Dockerfile.${IMAGETAG_SHORT}
echo "singlearch-build for "$BUILDARCH
echo timeout 5000 time docker buildx build  --output=type=registry,push=true --push   --pull --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-to ${IMAGETAG}_${TARGETARCH}_buildcache  --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache -t  ${IMAGETAG}_${TARGETARCH}_builder $buildstring -f "${DFILENAME}" 
     (
     test -e binaries.tgz && rm binaries.tgz
     ## first image named _baseimage does only apt/apk installs
     grep -v -e COPY -e build-bear "${DFILENAME}"  > "${DFILENAME}_baseimage" 
     mkdir  builder_baseimage
     mkdir  builder_baseimage/build
     mv "${DFILENAME}_baseimage" builder_baseimage/"${DFILENAME}_baseimage"
     (   cd builder_baseimage/;   timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-to ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage  --cache-from ${IMAGETAG}_${TARGETARCH}_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache -t  ${IMAGETAG}_${TARGETARCH}_baseimage $buildstring -f "${DFILENAME}_baseimage" )
     rm -rf builder_baseimage 

     # second image name _builder is the full thingy ( will be large . .)
     ( echo "FROM ${IMAGETAG}_${TARGETARCH}_baseimage";grep -v -e ^FROM -e "apk add" -e "apt " -e "apt-get" "${DFILENAME}")  > "${DFILENAME}_real" 
     
     timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-to ${IMAGETAG}_${TARGETARCH}_buildcache  --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage  --cache-from ${IMAGETAG}_${TARGETARCH}_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache  -t  ${IMAGETAG}_${TARGETARCH}_builder $buildstring -f "${DFILENAME}_real"  ;
     docker rmi ${IMAGETAG}_${TARGETARCH}_builder
     ### our arch ..
     docker export $(docker create --name cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH} ${IMAGETAG}_${TARGETARCH}_builder /bin/false ) |tar xv binaries.tgz ;docker rm cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH};docker rmi ${IMAGETAG}_${TARGETARCH}_builder
##### multi arch
     test -e binaries.tgz ||    (  timeout 5000 time docker buildx build  --output=type=local,dest=/tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder   --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH}  --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage  --cache-from ${IMAGETAG}_${TARGETARCH}_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache  -t  ${IMAGETAG}_${TARGETARCH}_builder $buildstring -f "${DFILENAME}_real" ) ;
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder && test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz && mv /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz .
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder && rm -rf "/tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder"
     test -e binaries.tgz || echo "ERROR: NO BINARIES"
### final (prod) image
     test -e binaries.tgz && cp binaries.tgz build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz &&  (  (grep ^FROM "${DFILENAME}" |tail -n1;echo "ADD hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz /";echo "RUN (dropbear --help 2>&1 || true )|grep -e ommand -e assword"  ) |timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage  --cache-from ${IMAGETAG}_${TARGETARCH}_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache  -t  ${IMAGETAG}_${TARGETARCH} $buildstring -f - );
     test -e build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz && rm build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz
     test -e binaries.tgz && mv binaries.tgz ${startdir}/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz
     
    ) &
     

done
done
wait 
echo
df -m
echo
docker image ls|grep hardened-dropbear
echo
cd "${startdir}"
find |grep tar.gz |grep hardened-dropbear || exit 1