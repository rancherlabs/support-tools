package aws

import (
	"fmt"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/aws/aws-sdk-go/service/eks/eksiface"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/iam/iamiface"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
)

func NewService() ports.AWSClientService {
	s := &serviceImpl{}
	return s
}

type serviceImpl struct {
}

func (s *serviceImpl) EKS(accessKey, secretKey, region string) (eksiface.EKSAPI, error) {
	sess, err := createSession(accessKey, secretKey, region)
	if err != nil {
		return nil, err
	}
	return eks.New(sess), nil
}

func (s *serviceImpl) IAM(accessKey, secretKey, region string) (iamiface.IAMAPI, error) {
	sess, err := createSession(accessKey, secretKey, region)
	if err != nil {
		return nil, err
	}
	return iam.New(sess), nil
}

func createSession(accessKey, secretKey, region string) (*session.Session, error) {
	cfg := aws.NewConfig()
	cfg.Credentials = credentials.NewStaticCredentials(accessKey, secretKey, "")
	cfg.Region = aws.String(region)

	cfg.CredentialsChainVerboseErrors = aws.Bool(true)
	sess, err := session.NewSessionWithOptions(session.Options{
		Config:            *cfg,
		SharedConfigState: session.SharedConfigDisable,
	})
	if err != nil {
		return nil, fmt.Errorf("creating AWS session: %w", err)
	}
	sess.Handlers.Build.PushFront(request.WithAppendUserAgent("eks-ebs-enable"))

	return sess, nil
}
