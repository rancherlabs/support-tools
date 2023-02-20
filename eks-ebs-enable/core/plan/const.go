package plan

const (
	defaultAudience = "sts.amazonaws.com"

	driverRoleNameFormat = "EBS_CSI_%s"

	ebsPolicyARN = "arn:aws-cn:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

	ebsAddonName = "aws-ebs-csi-driver"

	driverRoleTemplate = `{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Principal": {
				"Federated": "arn:aws-cn:iam::{{.AccountID}}:oidc-provider/oidc.eks.{{.Region}}}}.amazonaws.com.cn/id/{{.ProviderID}}"
			},
			"Action": "sts:AssumeRoleWithWebIdentity",
			"Condition": {
				"StringEquals": {
					"oidc.eks.{{.Region}}.amazonaws.com.cn/id/{{.ProviderID}}:aud": "sts.amazonaws.com",
					"oidc.eks.{{.Region}}.amazonaws.com.cn/id/{{.ProviderID}}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
				}
			}
		}
	]
}
`
)
