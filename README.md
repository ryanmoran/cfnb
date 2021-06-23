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
1. How can we support `$VCAP_SERVICES`?
1. What is `override.yml` and how does it play with this?
1. What is the contract for `config.yml`? This supports `name` and `version`,
   but some buildpacks include extra `config`:
   * https://github.com/cloudfoundry/go-buildpack/blob/75249ca38f80370112c9d2aec7a2061fef1f4e97/src/go/supply/supply.go#L241-L257
   * https://github.com/cloudfoundry/dotnet-core-buildpack/blob/afb2a62e3a915c203cc02d9de53f1a100693100a/src/dotnetcore/supply/supply.go#L371
1. What should we do about the cache?
