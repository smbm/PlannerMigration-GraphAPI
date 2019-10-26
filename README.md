# Planner Migration - Graph API

This rather crude script successfully migrated 99.9% of our Plans, Buckets and Tasks from one MS Online tenant to another.

It has some pre-requisites in order to work:
You must have all users and groups synced already, we had other native Powershell scripts to do this.
You must have a service account user present in every unified group that has a plan, the script will run as this user.
You need to register your application in Azure AD and set up ClientID key and Client secrets.
You will need a bunch of delegated permissions for this app:

*  Group.Read.All
*  Group.ReadWrite.All
*  Tasks.Read
*  Tasks.Read.Shared
*  Tasks.ReadWrite
*  Tasks.ReadWrite.Shared
*  User.Read
*  User.ReadBasic.All 

I set the same permissions in both tenants but you may want it slightly more restricted in the source.

This script works but was hacked together with a time frame in mind, there is most definitely room for improvement.
More functions could be implemented and the ones that are there could be made more generic.
It is what I like to call "just enough script to get the job done".
We only needed to run this script once so I approached the point of diminishing returns rapidly. Although it should run fine to do an incremental after the initial run so I will probably run it again.
Submissions for improvements would definitely be welcome.

The one and only time I ran it there were a couple of errors thrown up in the buckets and tasks sections that I think were to do with malformed JSON payloads.
If I can figure out which ones failed then I will attempt to diagnose more and get into it.

I did also observe a condition whereby a plan could have more than one ID which threw earlier versions of the script off.
I have corrected for this now and I suspect that the bucket and tasks issues described above were also down to this.

**As always it should be run entirely at your own risk, I would definitely recommend a thorough audit before letting it loose against you production environment.**

This script builds upon the immensely helpful stuff I gleaned from here: 
https://www.thelazyadministrator.com/2019/07/22/connect-and-navigate-the-microsoft-graph-api-with-powershell/
