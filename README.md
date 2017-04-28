master:[![Build status](https://ci.appveyor.com/api/projects/status/k6d7snrsx1neqjcm/branch/master?svg=true)](https://ci.appveyor.com/project/chmadole/autopatchdsc/branch/master)
dev:[![Build status](https://ci.appveyor.com/api/projects/status/k6d7snrsx1neqjcm/branch/dev?svg=true)](https://ci.appveyor.com/project/chmadole/autopatchdsc/branch/dev)

# AutoPatchDSC

This resource provides automated patch installation during a defined maintenance window, with patches provided by WSUS. It is designed for use with WaitForAll, WaitForAny, and WaitForAny DSC Resources to facilitate orchestration of rebooting nodes within a Highly Available (HA) configuration. Alternatively, a controller script may be used to orchestrate HA reboots. AutoPatchDSC was designed to patch SharePoint farms with mirror/witness configured SQL servers. However, the resource should be adaptable for farms of any type and SQL clusters.

## Resources

* [AutoPatchInstall](#AutoPatchInstall): Provides a mechanism to install patches within a defined maintenance window. 

* [AutoPatchServices](#AutoPatchServices): Provides a mechanism to control required services for use with rebooting. 

* [AutoPatchReboot](#AutoPatchReboot): Provides a mechanism to reboot servers within a defined maintenance window.

This project has adopted the [Microsoft Open Source Code of Conduct](
  https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](
  https://opensource.microsoft.com/codeofconduct/faq/) 
or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions 
or comments.
