# Release signing and download warnings

Maintainer guidance, checked against Microsoft documentation on 2026-10-16.
The published 0.2.5 Setup was verified as `NotSigned`. The manual workflow below
is prepared, but service authentication and actual signing remain untested until
the maintainer provisions a validated signing identity. Check each release's
signature and build proof before describing it as signed.

## Identify the warning

Capture the exact wording, product, detection name (if any), file version and
SHA256. An uncommon-download or unrecognized-app warning can mean insufficient
reputation. A malware or potentially unwanted application detection needs its
own investigation. Neither a checksum nor one clean scan proves a file harmless.
Microsoft documents these separate outcomes in its
[Edge SmartScreen guidance](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-security-smartscreen).

For a suspected incorrect Microsoft detection, use the official
[Microsoft Security Intelligence submission portal](https://www.microsoft.com/en-us/wdsi/filesubmission),
choose **Software developer**, select the affected product, and submit the exact
flagged file with the detection details and source/build evidence. Track the
result before calling the detection resolved. This is not a guaranteed way to
obtain SmartScreen reputation for an otherwise unknown download. Use the relevant
vendor's review process for another antivirus product.

## Recommended signing route

For an eligible individual maintainer, evaluate **Microsoft Artifact Signing**
(formerly Trusted Signing). Microsoft advertises pricing starting around
**US$9.99/month**; confirm the current price and obtain the maintainer's approval
before creating billable resources. Sign releases with a consistent trusted
publisher identity. Signing displays the validated publisher and can help trust
carry across releases, but **does not guarantee immediate removal of warnings**.
EV certificates no longer bypass SmartScreen, and self-signed certificates are
not a public-distribution solution. See
[Microsoft's signing and reputation guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

Prerequisites include:

- An individual developer located in the **United States or Canada**.
- A paid Azure subscription and Microsoft Entra tenant. Free, trial and sponsored
  subscriptions are unsupported.
- An Azure billing account with Account Type **Individual**, with legal name and
  address matching identity documentation; identity validation in the Azure
  portal and a Public Trust certificate profile. The publisher uses validated
  legal identity, not an arbitrary project nickname.
- Time for validation: Microsoft lists **1–20 business days**, possibly longer,
  and says validation cannot be expedited.

See the [Artifact Signing setup requirements](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)
and [Artifact Signing FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq).

## Full payload signing sequence for a future release

The initial workflow below preserves the approved ZIP and signs only the outer
EXE. Signing the payload scripts requires a newly finalized archive and the
following broader release sequence.

1. Finalize and review sources. Sign and timestamp supported executable payload
   files, including the PowerShell installer scripts, before final payload
   checksums and ZIP creation. Validate that signed scripts still pass the
   bundle's content checks. An outer EXE signature does not sign extracted files.
2. Build Setup with the finalized ZIP, then sign and timestamp the staged EXE
   before computing its final SHA256 and publishing any build proof.
3. Verify the final files' signatures, publisher and timestamps. Derive the
   proof's `signed` value from successful verification; do not merely change the
   currently hardcoded `false` in `setup/Build-Setup.ps1`.
4. Run the installer and regression checks on the exact signed release. Publish
   those same immutable bytes and their final hashes, then verify the downloaded
   copies and update the release's signing description accurately.

Keep Windows, browser and antivirus protections enabled throughout validation.

## Initial manual workflow: outer EXE only

`.github/workflows/sign-setup.yml` builds from the finalized **0.2.6** ZIP and the
SHA256 entered by the maintainer. It preserves that ZIP byte-for-byte, signs only
the outer Setup EXE, then validates its publisher, timestamp and embedded archive.
The helper records the actual signature status of each embedded PowerShell
script. **Unsigned inner scripts stay unsigned; Smart App Control acceptance is
not guaranteed.** The workflow runs Setup regression tests and saves a review
artifact. It creates no Azure resources, changes no downloads and publishes no
release. Gameplay testing remains manual.

Before the first run, complete these bindings after approving any service cost:

1. Create a Public Trust certificate profile after identity validation completes.
   Create a Microsoft Entra application/service principal for this repository.
2. Configure its GitHub federated credential with issuer
   `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`, and subject
   `repo:SimpleNeb/Subsistence-Kevin:environment:release-signing`.
3. Grant that identity **Artifact Signing Certificate Profile Signer** on the
   specific certificate profile. This workflow does not need Azure Owner or
   Contributor access. Follow Microsoft's
   [OIDC setup](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
   and [profile-scoped role assignment](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles).
4. Create the GitHub environment `release-signing`, restrict deployments to
   `main`, and configure a required maintainer reviewer. Store the three Azure
   identifiers as environment secrets and the four service settings as
   environment variables:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `AZURE_CLIENT_ID` | Application/client ID of the federated identity |
| Secret | `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Existing paid subscription ID |
| Variable | `ARTIFACT_SIGNING_ENDPOINT` | Official regional HTTPS endpoint, such as `https://eus.codesigning.azure.net/` |
| Variable | `ARTIFACT_SIGNING_ACCOUNT` | Existing signing account name |
| Variable | `ARTIFACT_SIGNING_PROFILE` | Validated Public Trust profile name |
| Variable | `EXPECTED_SIGNER_SUBJECT` | Exact full certificate Subject string from the validated profile's public certificate |

Do not add a client secret, private key, identity document or billing information
to the repository. The expected subject is an exact comparison, including its
format and ordering; it is not just the publisher's display name.

Run **Prepare signed Setup for review** from `main`, enter the independently
approved 0.2.6 ZIP hash, and explicitly approve using the paid signing service.
The environment approval and configured identity must also be ready. The job
fails before Azure login if approval or required configuration is absent.
Afterward, download the review artifact, inspect its proof and test the exact
`-signed.exe` in the game before deciding to publish it under a new immutable
download URL. The ZIP and any existing unsigned EXE remain unchanged.

The integration follows the
[official Artifact Signing action](https://github.com/Azure/artifact-signing-action)
and uses immutable action revisions verified on 2026-10-16: Artifact Signing
v2.0.0, Azure Login v3.1.0, Checkout v7.0.1 and Upload Artifact v7.0.2. Actual
service authentication, successful signing and a signed-file test run have not
yet been demonstrated; preparation and rejection checks can run locally without
creating or contacting a signing service.
