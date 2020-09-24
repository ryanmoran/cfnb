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

## Questions for further investigation
1. How does the `detect` metadata API work? What should we send to it?
1. Does this work if the buildpack is specified directly via `cf push myapp -b <buildpack>`?
1. What does support for sidecar buildpacks look like?
1. How can this function in multi-buildpack support? What happens if it is intermingled with v2 and v3 buildpacks?
1. How can we support `$VCAP_SERVICES`?
