#!/bin/bash

VERSION=${1:-blue}

if [ "$VERSION" != "blue" ] && [ "$VERSION" != "green" ]; then
    echo "Usage: ./build-and-push.sh [blue|green]"
    exit 1
fi

echo "🔨 Building $VERSION version..."

cd ../app
cp src/main/resources/static/index-${VERSION}.html src/main/resources/static/index.html

docker build -t chucthien03/banking-demo:${VERSION} .

echo "✅ Built chucthien03/banking-demo:${VERSION}"
echo ""
echo "📤 Pushing to Docker Hub..."
docker push chucthien03/banking-demo:${VERSION}

echo ""
echo "✅ Done! To deploy:"
echo "  kubectl set image deployment/banking-good banking=chucthien03/banking-demo:${VERSION}"
