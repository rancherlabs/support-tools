# Fleet | Registration Resource Cleanup

This is a cleanup script to work around a known Fleet bug whereby patching a downstream cluster, for instance when re-deploying a Fleet agent in such a cluster, causes new resources to be created without obsolete resources being deleted. Ultimately, this clutters the upstream cluster.

This script retrieves all cluster registration resources, orders them by cluster then by creation timestamp, and deletes all but the youngest cluster registration for each cluster. This causes obsolete cluster registrations and their child resources to be deleted.