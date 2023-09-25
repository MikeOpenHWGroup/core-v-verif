# AWS Workflow for CORE-V-VERIF

AWS is used to automate all activities which require access to the licenses provided by OpenHW Group's partners.

For CORE-V-VERIF this currently means the licenses for Siemens EDA's Questasim SystemVerilog simulator.

Some constraints:
- AWS' credentials are available only in the context of the main repository. This means that an AWS job cannot be started from the context of a pull request.
- As per license agreement, the tools can be used only by OpenHW Group's members. This means that their usage must triggered by OpenHW Group staff
- `master` branch must always be clean (no experiments)

## Proposed workflow

- The project has a Continuous Integration branch (`ci`)
- Each PR must target `ci`
- Each PR triggers the `check_target` action, which verifies that target branch
- Each PR is checked and merged by an OpenHW Group member, resulting in a commit to `ci`
- Each push to `ci` triggers the `aws` action, which starts the AWS CodeBuild job
- A successful run of `aws` (and therefore of the related AWS CodeBuild) results in an automatic merge of the `ci` branch to `dev`

## Notes, open points

- What happens if `aws` fails?
At the moment, nothing. The repository owner has to analyze the cause of the failure and decide whether to rerun the action or to revert the commit

- Why not implementing an automatic revert upon failure?
This idea could apparently make the workflow cleaner, but it could also make it much more complex. A CodeBuild job could fail for reasons which are independent from the quality of the code (e.g. licensing issues): in these cases, an autorevert would make the flow a bit more complex.
