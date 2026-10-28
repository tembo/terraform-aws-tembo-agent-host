package test

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	teststructure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	region    = "us-east-2"
	namespace = "tembo"
)

func cleanup(t *testing.T, opts *terraform.Options, tempTestFolder string) {
	terraform.Destroy(t, opts)
	os.RemoveAll(tempTestFolder)
}

func options(t *testing.T, vars map[string]any) (*terraform.Options, string) {
	tempTestFolder := teststructure.CopyTerraformFolderToTemp(t, "../../", "examples/complete")

	return &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		VarFiles:     []string{"fixtures." + region + ".tfvars"},
		Vars:         vars,
	}, tempTestFolder
}

// TestExamplesComplete applies examples/complete in AWS: a VPC, an EKS
// cluster without nodes and the module.
func TestExamplesComplete(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())
	id := "eg-ue2-test-agent-host-" + randID

	opts, tempTestFolder := options(t, map[string]any{"attributes": []string{randID}})
	defer cleanup(t, opts, tempTestFolder)

	terraform.InitAndApply(t, opts)

	clusterName := terraform.Output(t, opts, "cluster_name")
	serviceAccount := terraform.Output(t, opts, "service_account_name")
	controllerRoleARN := terraform.Output(t, opts, "controller_role_arn")

	assert.Equal(t, id+"-cluster", clusterName)
	assert.Equal(t, "tembo-host-controller", serviceAccount)
	assert.True(t, strings.HasSuffix(controllerRoleARN, ":role/"+id+"-controller"), controllerRoleARN)
	assert.Equal(t, id+"-host", terraform.Output(t, opts, "host_instance_profile_name"))
	assert.Equal(t, map[string]string{
		"hosts.tembo.io/cluster":   clusterName,
		"hosts.tembo.io/namespace": namespace,
	}, terraform.OutputMap(t, opts, "ownership_tags"))

	// The controller's service account is bound to its role.
	cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	require.NoError(t, err)
	associations, err := eks.NewFromConfig(cfg).ListPodIdentityAssociations(context.Background(), &eks.ListPodIdentityAssociationsInput{
		ClusterName:    aws.String(clusterName),
		Namespace:      aws.String(namespace),
		ServiceAccount: aws.String(serviceAccount),
	})
	require.NoError(t, err)
	assert.Len(t, associations.Associations, 1)

	// A second plan finds nothing to change.
	assert.Equal(t, 0, terraform.PlanExitCode(t, opts))
}

// TestExamplesCompleteDisabled applies examples/complete with enabled = false,
// which creates nothing.
func TestExamplesCompleteDisabled(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())

	opts, tempTestFolder := options(t, map[string]any{
		"attributes": []string{randID},
		"enabled":    false,
	})
	defer cleanup(t, opts, tempTestFolder)

	results := terraform.InitAndApply(t, opts)

	assert.Contains(t, results, "Resources: 0 added, 0 changed, 0 destroyed.")
}
