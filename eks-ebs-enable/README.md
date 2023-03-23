# EBS CSI Driver Installer

> NOTE: only use this tool as directed by SUSE support. Any usage outside of this is unsupported.

## Purpose

Starting with EKS v1.23 you are required to use the out-of-tree drivers for EBS backed volumes. This support tool can be used to enable the the **Amazon EBS CSI Driver** via an EKS addon.

When run this will do the following per cluster:

- Lookup the cluster details in Rancher
- Get the AWS creds for the cluster from Rancher (if not using explicit creds)
- Get the EKS cluster details from AWS
- Creates an OIDC provider for the EKS cluster
- Create a new IAM role for the cluster to use with the EBS addon (named `EBS_CSI_<CLUSTERNAME>` )
- Attaches the EBS policy to the new role
- Installs the EBS CSI addon for the EKS cluster using the created role
- Waits for the addon to be `active` (or timesout)

The tool is idempotent so it can be run multiple times against the same cluster (even if the last run failed).

> NOTE: this tool only runs against standard AWS regions (and not US GovCloud or China regions)

## Requirements

You will need specific permissions to enable the addon. These permissions are currently outside the recommended set of permissions for Rancher.

There are 2 options to supply these permissions

### Option 1 - augment the permissions used when provisioning the cluster

The IAM user who's credentials where used to provision the cluster can be augumented by adding the following permissions (via a policy). To do this with the `aws` cli you can run the following command to create the policy:

```shell
aws iam create-policy --policy-name Rancher_Support_EKSEBS --policy-document \
'{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeAddonConfiguration",
                "eks:UpdateAddon",
                "eks:ListAddons",
                "iam:CreateOpenIDConnectProvider",
                "eks:DescribeAddon",
                "iam:ListOpenIDConnectProviders",
                "eks:DescribeIdentityProviderConfig",
                "eks:DeleteAddon",
                "eks:CreateAddon",
                "eks:DescribeAddonVersions",
                "sts:AssumeRoleWithWebIdentity",
                "eks:AssociateIdentityProviderConfig",
                "eks:ListIdentityProviderConfigs"
            ],
            "Resource": "*"
        }
    ]
}'

```

You can then attach this policy to the IAM user of the AWS credentials used by Rancher:

```shell
aws iam attach-user-policy --user-name <USERNAME> --policy-arn "arn:aws:iam::<ACCOUNT_ID>:policy/Rancher_Support_EKSEBS
```

You will need to replace `<USERNAME>` with the IAM user that the Rancher credentials belong to and also `<ACCOUNT_ID>` with your AWS account id.

### Option 2 - permissions just for this tool

Create a new IAM policy with the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "eks:DescribeAddonConfiguration",
                "eks:UpdateAddon",
                "eks:ListAddons",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "eks:DescribeAddon",
                "iam:CreateOpenIDConnectProvider",
                "iam:PassRole",
                "eks:DescribeIdentityProviderConfig",
                "eks:DeleteAddon",
                "iam:ListOpenIDConnectProviders",
                "iam:ListAttachedRolePolicies",
                "eks:CreateAddon",
                "eks:DescribeCluster",
                "eks:DescribeAddonVersions",
                "sts:AssumeRoleWithWebIdentity",
                "eks:AssociateIdentityProviderConfig",
                "eks:ListIdentityProviderConfigs"
            ],
            "Resource": "*"
        }
    ]
}
```

Then create a new IAM user and attach the policy you just created. Then create a new access key and use the id and secret later.

## Building

The tool needs to be built. This done by doing the following:

1. Clone the repo
2. Change directory into this folder
3. Run the following

```shell
make release-local
```

4. The **dist** folder contains:
    1. archives for linux, macOS and windows
    2. Linux packages in deb, rpm, apk format
    3. SBOMs for the archives

## Usage

1. Create an API key in Rancher.The key can be scoped per cluster or with no scope. Its easier to have no scope as you can use the same API key for all cluster upgrades.
   1. Note down the **Bearer Token** API key
   2. Note down the API Endpoint
2. Open a terminal
3. Export environment variables for the key and endpoint

```bash
export RANCHER_TOKEN="<YOUR BEARER TOKEN FROM ABOVE>"
export RANCHER_API="<YOUR RANCHER API ENDPOINT>"
export KUBECONFIG="<YOUR RANCHER KUBECONFIG PATH>"
```

> If you are going to use the existing AWS credentials in Rancher (option 1 above) then you will need to use the `--kubeconfig` flag to point to the kubeconfig file for your Rancher clusters.

1. Enable the addon for a cluster using one of the following commands depending on with iam permissions option you went with:
    1. option 1 (augmenting existing permissions)

    ```shell
    eks-ebs-enable enable \
        --endpoint $RANCHER_API \
        --bearer-token $RANCHER_TOKEN \
        --kubeconfig $KUBECONFIG \
        --cluster richtest1 \
        --debug
    ```

    2. option 2 (separate permissions)

    ```shell
    eks-ebs-enable enable \
        --endpoint $RANCHER_API \
        --bearer-token $RANCHER_TOKEN \
        --cluster richtest1 \
        --explicit-creds \
        --access-key-id "<AWS_ACCESS_KEY_ID_VALUE>" \
        --access-key-secret "<AWS_ACCESS_KEY_SECRET_VALUE>" \
        --debug

    ```
