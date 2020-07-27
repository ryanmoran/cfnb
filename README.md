# Cloud (Foundry) Native Buildpacks

This is a spike on a tool to repackage Cloud Native Buildpacks as Cloud Foundry Buildpacks.

## Usage
1. Download a CNB buildpackage (eg. a [Ruby release](https://github.com/paketo-community/ruby/releases)).
1. Download a [lifecycle](https://github.com/buildpacks/lifecycle/releases).
1. Run
   ```
   package.sh \
     --buildpack /path/to/buildpackage.cnb \
     --lifecycle /path/to/lifecycle.tgz \
     --output /tmp/buildpack.zip
   ```
1. Upload the created buildpack to a Cloud Foundry.
1. Push your app.
