package plan

import (
	"context"
	"crypto/sha1"
	"crypto/tls"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"path"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSCreateOIDCProviderStep(plan *enableEBSPlan) planner.Procedure {
	return &awsCreateOIDCProviderStep{
		plan: plan,
	}
}

type awsCreateOIDCProviderStep struct {
	plan *enableEBSPlan
}

func (s *awsCreateOIDCProviderStep) Name() string {
	return "aws_create_oidc_provider"
}

func (s *awsCreateOIDCProviderStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}

	ports := s.plan.Ports

	iamService, err := ports.AWS.IAM(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting IAM client: %w", err)
	}

	output, err := iamService.ListOpenIDConnectProvidersWithContext(ctx, &iam.ListOpenIDConnectProvidersInput{})
	if err != nil {
		return nil, fmt.Errorf("listing oidc providers: %w", err)
	}

	id := path.Base(*s.plan.AWSEKSDetails.Identity.Oidc.Issuer)

	for _, prov := range output.OpenIDConnectProviderList {
		if strings.Contains(*prov.Arn, id) {
			s.plan.OIDCProviderARN = *prov.Arn
			return nil, nil
		}
	}

	thumprint, err := s.getIssuerThumprint(ctx)
	if err != nil {
		return nil, fmt.Errorf("getting issuer tumpriint: %w", err)
	}

	input := &iam.CreateOpenIDConnectProviderInput{
		ClientIDList:   []*string{aws.String(defaultAudience)},
		ThumbprintList: []*string{&thumprint},
		Url:            s.plan.AWSEKSDetails.Identity.Oidc.Issuer,
		Tags:           []*iam.Tag{},
	}

	createOutput, err := iamService.CreateOpenIDConnectProviderWithContext(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("creating oidc provider: %w", err)
	}
	s.plan.OIDCProviderARN = *createOutput.OpenIDConnectProviderArn

	return nil, nil
}

func (s *awsCreateOIDCProviderStep) getIssuerThumprint(ctx context.Context) (string, error) {
	issuerURL, err := url.Parse(*s.plan.AWSEKSDetails.Identity.Oidc.Issuer)
	if err != nil {
		return "", fmt.Errorf("parsing issuer url: %w", err)
	}
	if issuerURL.Port() == "" {
		issuerURL.Host += ":443"
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
				MinVersion:         tls.VersionTLS12,
			},
			Proxy: http.ProxyFromEnvironment,
		},
	}
	resp, err := client.Get(issuerURL.String())
	if err != nil {
		return "", fmt.Errorf("querying oidc issuer endpoint %s: %w", issuerURL.String(), err)
	}
	defer resp.Body.Close()

	if resp.TLS == nil || len(resp.TLS.PeerCertificates) == 0 {
		return "", errors.New("unable to get OIDS issuers cert")
	}

	root := resp.TLS.PeerCertificates[len(resp.TLS.PeerCertificates)-1]
	return fmt.Sprintf("%x", sha1.Sum(root.Raw)), nil
}
