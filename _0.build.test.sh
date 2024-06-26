#!/bin/bash
[[ -z "$PLATFORMS_ALPINE" ]] || BUILD_TARGET_PLATFORMS=$PLATFORMS_ALPINE
[[ -z "$BUILD_TARGET_PLATFORMS" ]] && BUILD_TARGET_PLATFORMS="linux/amd64,linux/arm64"
_platform_tag() { echo "$1"|sed 's~/~_~g' ;};
_oneline()               { tr -d '\n' ; } ;
_buildx_arch()           { case "$(uname -m)" in aarch64) echo linux/arm64;; x86_64) echo linux/amd64 ;; armv7l|armv7*) echo linux/arm/v7;; armv6l|armv6*) echo linux/arm/v6;;  esac ; } ;

test -e dropbear-src || git clone https://github.com/mkj/dropbear.git dropbear-src

mkdir builds
startdir=$(pwd)

#IMAGETAG_SHORT=alpine
[[ -z "$IMAGETAGS" ]] && IMAGETAGS="alpine ubuntu-focal ubuntu-bionic"
for IMAGETAG_SHORT in $IMAGETAGS;do
REGISTRY_HOST=ghcr.io
REGISTRY_PROJECT=thefoundation-builder
PROJECT_NAME=hardened-dropbear
[[ -z "$GH_IMAGE_NAME" ]] && IMAGETAG=${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}
[[ -z "$GH_IMAGE_NAME" ]] || IMAGETAG="$GH_IMAGE_NAME":${IMAGETAG_SHORT}




#docker build . --progress plain -f Dockerfile.alpine -t $IMAGETAG
for BUILDARCH in linux/amd64 linux/arm64;do
TARGETARCH=$(_platform_tag $BUILDARCH  )
TARGETDIR=builds/${IMAGETAG_SHORT}"_"$TARGETARCH
echo "building to "$TARGETDIR
(
mkdir -p "$TARGETDIR"
cd "$TARGETDIR"
mkdir build
(
    cd build
    cp ${startdir}/build-bear.sh . -v
    test -e ccache.tgz && rm ccache.tgz
    docker export $(docker create --name cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH} ${IMAGETAG}_${TARGETARCH}_builder /bin/false ) |tar xv ccache.tgz ;docker rm cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH}
     test -e ccache.tgz ||    (  (echo FROM ${IMAGETAG}_${TARGETARCH}_builder;echo RUN echo yocacheme) | timeout 5000 time docker buildx build  --output=type=local,dest=/tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH}   --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache_baseimage  --cache-from ${IMAGETAG}_${TARGETARCH}_baseimage --cache-from ${IMAGETAG}_${TARGETARCH}_builder --cache-from ${IMAGETAG}_${TARGETARCH}_buildcache -t  ${IMAGETAG}_${TARGETARCH}_extract $buildstring -f - ) ;
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
     mkdir -p   builder_baseimage/build
     #grep -v -e COPY -e build-bear "${DFILENAME}"  > "${DFILENAME}_baseimage"      
     #cp "${DFILENAME}_baseimage" "builder_baseimage/${DFILENAME}_baseimage"

     BSIMGTAG=${IMAGETAG}_${TARGETARCH}_baseimage
     RLIMGTAG=${IMAGETAG}_${TARGETARCH}_builder
     BSICACHE=${IMAGETAG}_${TARGETARCH}_baseimage_cache
     RLICACHE=${IMAGETAG}_${TARGETARCH}_builder_cache
     echo "GENERATE dockerfile_BASE for Dockerfile.${IMAGETAG_SHORT} $BUILDARCH"
     grep -v -e COPY -e build-bear "${DFILENAME}"  > "builder_baseimage/Dockerfile.${IMAGETAG_SHORT}_baseimage"
     echo "GENERATE dockerfile_REAL for Dockerfile.${IMAGETAG_SHORT} $BUILDARCH"
     ( echo "FROM ${BSIMGTAG}";grep -v -e ^FROM -e "apk add" -e "apt " -e "apt-get" "${DFILENAME}")  > "Dockerfile.${IMAGETAG_SHORT}_real" 

     echo "BUILD_BASEIMAGE for Dockerfile.${IMAGETAG_SHORT} $BUILDARCH"
     (   cd builder_baseimage/;   timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-from ${BSICACHE}  --cache-from ${RLICACHE}  --cache-to ${BSICACHE}  -t   ${BSIMGTAG} $buildstring -f "Dockerfile.${IMAGETAG_SHORT}_baseimage" 
         cd .. 
         rm -rf builder_baseimage
     )
     
     # second image name _builder is the full thingy ( will be large . .)
     echo "BUILD_REAL_IMAGE for Dockerfile.${IMAGETAG_SHORT} $BUILDARCH"

     timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-from ${BSICACHE}  --cache-from ${RLICACHE}  --cache-to ${RLICACHE}  -t   ${RLIMGTAG} $buildstring -f "Dockerfile.${IMAGETAG_SHORT}_real"  ;
     #docker rmi ${IMAGETAG}_${TARGETARCH}_builder
     ### our arch ..
     mkdir -p /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/||true
     docker export $(docker create --name cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH} ${RLIMGTAG} /bin/false ) |tar xvz /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz ;docker rm cicache_${IMAGETAG//[:\/]/_}_${TARGETARCH};
     #docker rmi ${IMAGETAG}_${TARGETARCH}_builder
##### multi arch
     #test -e binaries.tgz ||    (  timeout 5000 time docker buildx build  --output=type=local,dest=/tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder   --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH}  --cache-from ${BSICACHE}  --cache-from ${RLICACHE}  --cache-to ${RLICACHE}  -t   ${RLIMGTAG}  $buildstring -f "Dockerfile.${IMAGETAG_SHORT}_real" ) ;
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz || echo "ERROR: NO BINARIES"
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz || exit 1
### final (prod) image
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz && cp /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz &&  (  (grep ^FROM "${DFILENAME}" |tail -n1;echo "ADD hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz /";echo "RUN (dropbear --help 2>&1 || true )|grep -e ommand -e assword"  ) |timeout 5000 time docker buildx build  --output=type=registry,push=true --push  --progress plain --network=host --memory-swap -1 --memory 1024 --platform=${BUILDARCH} --cache-from ${BSICACHE}  --cache-from ${RLICACHE}  --cache-to ${RLICACHE}  -t ${IMAGETAG}_${TARGETARCH} $buildstring -f - );
     test -e build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz && rm build/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz
     test -e /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz && mv /tmp/buildout_${IMAGETAG}_${TARGETARCH}_builder/binaries.tgz ${startdir}/hardened-dropbear-$IMAGETAG_SHORT.$TARGETARCH.tar.gz
     docker rmi ${RLIMGTAG} 
    ) 2>&1
     
)  2>&1|sed 's/^/'$(echo ${IMAGETAG}_${TARGETARCH}|sed 's~/~_~g;s/. \+://g')':/g' &
done
done
wait 
echo
df -m
echo
docker image ls|grep hardened-dropbear
echo
cd "${startdir}"
#find |grep tar.gz |grep hardened-dropbear || exit 1
find ${startdir} |grep tar.gz |grep hardened-dropbear ||exit 1