//local kube = import "https://github.com/bitnami-labs/kube-libsonnet/raw/52ba963ca44f7a4960aeae9ee0fbee44726e481f/kube.libsonnet";
local kube = import "https://raw.githubusercontent.com/bitnami-labs/kube-libsonnet/517619dcdbe8cf186a18f61d9467d812ebd3e1a1/kube.libsonnet"; //вроде работает 
        
local redis(name) = {
  svc: kube.Service(name) {
    target_pod:: $.deploy.spec.template,
  },

  deploy: kube.Deployment(name) {
    spec+: {
      template+: {
        spec+: {
          containers_: {
            hipster: kube.Container("hipster") {
              name: "server",
              ports: [{ containerPort: 50051 }],
              env: [{ name: "PORT",  value: "50051" }],
              resources: {
                requests: {
                  cpu: "100m", 
                  memory: "64Mi"
                },
                limits: {
                  cpu: "200m", 
                  memory: "128Mi"
                }
              },
              readinessProbe: {
                initialDelaySeconds: 20,
                periodSeconds: 15,
                exec: {
                  command: [
                    "/bin/grpc_health_probe",
                    "-addr=:50051",
                  ],
                }
              },
              livenessProbe: {
                initialDelaySeconds: 20,
                periodSeconds: 15,
                exec: {
                  command: [
                    "/bin/grpc_health_probe",
                    "-addr=:50051",
                  ],
                },
              },
            },
          },
        },
      },
    },
  },
};

{
  paymentservice: redis("paymentservice") {
    deploy+: { 
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              hipster+: {
                image: "gcr.io/google-samples/microservices-demo/paymentservice:v0.1.3",
              },
            },
          },      
        },
      },
    },
  }, 
  shippingservice: redis("shippingservice") {
    deploy+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              hipster+: {
                image: "gcr.io/google-samples/microservices-demo/shippingservice:v0.1.3",
              },
            },
          },
        },
      },
    },
  },
}