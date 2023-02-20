package ports

import (
	"context"
	"crypto/tls"
	"io"

	"github.com/aws/aws-sdk-go/service/eks/eksiface"
	"github.com/aws/aws-sdk-go/service/iam/iamiface"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/models"
)

type RancherService interface {
	GetClusterDetails(ctx context.Context, clusterName string) (*models.EKSClusterDetails, error)
}

type AWSClientService interface {
	EKS(accessKey, secretKey, region string) (eksiface.EKSAPI, error)
	IAM(accessKey, secretKey, region string) (iamiface.IAMAPI, error)
}

type HttpClient interface {
	Do(req *Request) (Response, error)
	Get(url string, headers map[string]string) (Response, error)
	Post(url string, body string, headers map[string]string) (Response, error)
	Put(url string, body string, headers map[string]string) (Response, error)
}

type Request struct {
	URL     string
	Body    *string
	Method  string
	Headers map[string]string
}

type Response interface {
	ResponseCode() int
	Body() io.ReadCloser
	Headers() map[string]string
	TLS() *tls.ConnectionState
}
