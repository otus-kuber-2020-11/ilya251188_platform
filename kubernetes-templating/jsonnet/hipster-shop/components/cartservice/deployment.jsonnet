local kube = import "lib/kube.libjsonnet";
local kap = import "lib/kapitan.libjsonnet";
local inv = kap.inventory();

local myContainers = kube.Container("server") {
  image: inv.parameters.cartservice.image,
  env: inv.parameters.cartservice.env,
  resources: inv.parameters.cartservice.resources,
  ports_+: {
    grpc: {containerPort: inv.parameters.cartservice.port}
  }
};

local deployment = kube.Deployment("cartservice") {
  spec+: {
    selector: {
      matchLabels: {
        app: "cartservice",
      },  
    },      
    template+: {
      metadata: {
        labels: {
          app: "cartservice",
        },
      },
      spec+: {
        containers_+: {
         cartservice: myContainers
         },
      }
    },
  },
};

{
  cartservice: deployment
}