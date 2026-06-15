{{- /*gotype:github.com/e2b-dev/infra/packages/orchestrator/pkg/template/build/core/rootfs.templateModel*/ -}}
{{ .WriteFile "/etc/resolv.conf" 0o644 }}

nameserver {{ .Nameserver }}
nameserver 223.6.6.6
options use-vc timeout:2 attempts:3
