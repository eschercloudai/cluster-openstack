{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "infrastructureApiVersion" -}}
infrastructure.cluster.x-k8s.io/v1alpha5
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "labels.common" -}}
{{- include "labels.commonWithoutVersion" . }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
helm.sh/chart: {{ include "chart" . | quote }}
{{- end -}}

{{/*
Common labels without version
*/}}
{{- define "labels.commonWithoutVersion" -}}
app: {{ include "name" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
cluster.x-k8s.io/cluster-name: {{ include "resource.default.name" . | quote }}
eschercloud.ai/cluster: {{ include "resource.default.name" . | quote }}
eschercloud.ai/organization: {{ .Values.organization | quote }}
{{- end -}}

{{/*
Create a name stem for resource names
When resources are created from templates by Cluster API controllers, they are given random suffixes.
Given that Kubernetes allows 63 characters for resource names, the stem is truncated to 47 characters to leave
room for such suffix.
*/}}
{{- define "resource.default.name" -}}
{{ .Values.clusterName }}
{{- end -}}

{{- define "kubeletExtraArgs" -}}
{{- .Files.Get "files/kubelet-args" -}}
{{- end -}}

{{- define "kubeProxyFiles" }}
- path: /etc/gs-kube-proxy-config.yaml
  permissions: "0600"
  content: |
    {{- .Files.Get "files/etc/gs-kube-proxy-config.yaml" | nindent 4 }}
- path: /etc/gs-kube-proxy-patch.sh
  permissions: "0700"
  content: |
    {{- .Files.Get "files/etc/gs-kube-proxy-patch.sh" | nindent 4 }}
{{- end -}}

{{- define "kubeProxyPreKubeadmCommands" -}}
- bash /etc/gs-kube-proxy-patch.sh
{{- end -}}

{{- define "nodeName" -}}
{{- if .Values.ignition.enable -}}
__REPLACE_NODE_NAME__
{{- else -}}
'{{ `{{ local_hostname }}` }}'
{{- end -}}
{{- end -}}

# In Flatcar kubeadm configuration is in different directory because /run
# can't be provisioned with ignition.
{{- define "nodeNameReplacePreKubeadmCommands" -}}
{{- if .Values.ignition.enable }}
- bash -c "sed -i 's/__REPLACE_NODE_NAME__/$(hostname -s)/g' /etc/kubeadm.yml"
{{- end }}
{{- end -}}


{{/*
Updates in KubeadmConfigTemplate will not trigger any rollout for worker nodes.
It is necessary to create a new template with a new name to trigger an upgrade.
See https://github.com/kubernetes-sigs/cluster-api/issues/4910
See https://github.com/kubernetes-sigs/cluster-api/pull/5027/files
*/}}
{{- define "kubeAdmConfigTemplateRevision" -}}
{{- $inputs := (dict "kubeletExtraArgs" (include "kubeletExtraArgs" .)) }}
{{- mustToJson $inputs | toString | quote | sha1sum | trunc 8 }}
{{- end -}}

{{/*
OpenStackMachineTemplate is immutable. We need to create new versions during upgrades.
Here we are generating a hash suffix to trigger upgrade when only it is necessary by
using only the parameters used in openstack_machine_template.yaml.
*/}}
{{- define "osmtRevision" -}}
{{- $inputs := (dict
  "cloudName" .Values.cloudName
  "cloudConfig" .Values.cloudConfig
  "nodeCIDR" .Values.nodeCIDR
  "networkName" .Values.networkName
  "subnetName" .Values.subnetName
  "infrastructureApiVersion" ( include "infrastructureApiVersion" . )
  "bootFromVolume" .bootFromVolume
  "diskSize" .diskSize
  "flavor" .flavor
  "image" .image
  "name" .name ) }}
{{- mustToJson $inputs | toString | quote | sha1sum | trunc 8 }}
{{- end -}}

{{- define "osmtRevisionByClass" -}}
{{- $outerScope := . }}
{{- range .Values.nodeClasses }}
{{- if eq .name $outerScope.class }}
{{- include "osmtRevision" . }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "osmtRevisionOfControlPlane" -}}
{{- $outerScope := . }}
{{- include "osmtRevision" (set (merge $outerScope .Values.controlPlane) "name" "control-plane") }}
{{- end -}}

{{/*
Create a name for a cluster component.
*/}}
{{- define "openstack-cluster.componentName" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{- printf "%s-%s" $ctx.Release.Name $componentName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the secret containing the cloud credentials.
*/}}
{{- define "cluster-openstack.cloudCredentialsSecretName" -}}
{{- if .Values.cloudConfig -}}
{{- .Values.cloudConfig -}}
{{- else -}}
{{ include "openstack-cluster.componentName" (list . "cloud-credentials") -}}
{{- end -}}
{{- end -}}
