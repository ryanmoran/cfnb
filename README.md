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
1. What is the contract for `config.yml`? This supports `name` and `version`,
   but some buildpacks include extra `config`:
   * https://github.com/cloudfoundry/go-buildpack/blob/75249ca38f80370112c9d2aec7a2061fef1f4e97/src/go/supply/supply.go#L241-L257
   * https://github.com/cloudfoundry/dotnet-core-buildpack/blob/afb2a62e3a915c203cc02d9de53f1a100693100a/src/dotnetcore/supply/supply.go#L371
1. What should we do about the cache?

## Supporting `VCAP_SERVICES`
The current buildpacks have support for reading the `VCAP_SERVICES` environment
variable, but only so that they can support integrations by third-party
vendors. Below is a survey of the buildpacks we maintain today that reference
`VCAP_SERVICES` and how they use it.

### Python

* [AppDynamics Hook](https://github.com/cloudfoundry/python-buildpack/blob/4bcb0a6ab17567691f5a04bf7a774ae4bf6aff45/src/python/hooks/appdynamics.go#L154)
* [Dynatrace Hook](https://github.com/Dynatrace/libbuildpack-dynatrace/blob/1640532fc77fcc0ec768eeeb9af7c46bfdb4c5a6/hook.go#L190)

### Go

* [AppDynamics Hook](https://github.com/cloudfoundry/go-buildpack/blob/75249ca38f80370112c9d2aec7a2061fef1f4e97/src/go/hooks/appdynamics.go#L78)
* [Dynatrace Hook](https://github.com/Dynatrace/libbuildpack-dynatrace/blob/1640532fc77fcc0ec768eeeb9af7c46bfdb4c5a6/hook.go#L190)

### Node.js
* [AppDynamics Profile Script](https://github.com/cloudfoundry/nodejs-buildpack/blob/4f2b2a3dde0415bb922b5459f2dfa9b1e401836d/profile/appdynamics-setup.rb)
* [Contrast Security Hook](https://github.com/cloudfoundry/nodejs-buildpack/blob/4f2b2a3dde0415bb922b5459f2dfa9b1e401836d/src/nodejs/hooks/contrast_security.go#L101)
* [Dynatrace Hook](https://github.com/Dynatrace/libbuildpack-dynatrace/blob/1640532fc77fcc0ec768eeeb9af7c46bfdb4c5a6/hook.go#L190)
* [NewRelic Profile Script](https://github.com/cloudfoundry/nodejs-buildpack/blob/4f2b2a3dde0415bb922b5459f2dfa9b1e401836d/profile/newrelic-setup.sh)
* [Seeker Agent Hook](https://github.com/cloudfoundry/nodejs-buildpack/blob/4f2b2a3dde0415bb922b5459f2dfa9b1e401836d/src/nodejs/hooks/seeker_agent.go#L195)
* [Snyk Hook](https://github.com/cloudfoundry/nodejs-buildpack/blob/4f2b2a3dde0415bb922b5459f2dfa9b1e401836d/src/nodejs/hooks/snyk.go#L261)

### .Net Core
* [Dynatrace Hook](https://github.com/Dynatrace/libbuildpack-dynatrace/blob/1640532fc77fcc0ec768eeeb9af7c46bfdb4c5a6/hook.go#L190)

### Staticfile
* [Dynatrace Hook](https://github.com/Dynatrace/libbuildpack-dynatrace/blob/1640532fc77fcc0ec768eeeb9af7c46bfdb4c5a6/hook.go#L190)

## Supporting `override.yml`

The `override.yml` feature allows users to override values in the buildpack
manifest. This is mostly to include their own dependencies or override the
default values. To use the feature, users will create their own buildpack that
contains an `override.yml` file. This buildpack will then be included in the
build prior to the buildpack that it overrides. When the buildpack executes it
will simply copy its `override.yml` into its designated dependencies directory.
Later, when the buildpack that will be overridden executes, it searches the
entire dependencies directory for any `override.yml` file that may override its
manifest and then overrides its manifest to include these new settings. Once it
has overridden the manifest, it continues execution as normal.

It is not clear what the impact of not including this in our implementation
might be. The shimmed buildpacks will not have a `manifest.yml` file that can
be overridden. Instead, we would need to map this to something like our
existing [dependency
mapping](https://github.com/paketo-buildpacks/rfcs/blob/main/text/0010-dependency-mappings.md)
functionality.
