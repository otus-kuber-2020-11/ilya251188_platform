**Kubernetes-templating**

## **chartmuseum**

1. Включить API заменив значение переменной окружения
```python
DISABLE_API: false
```
  2. Добавить репозиторий в helm 
```shell
helm repo add chartmuseum https://chartmuseum.34.122.143.57.nip.io
```
  3. Загрузить в репоизторий чарт, я можно через curl дибо через плагин push для хельма 
```shell
helm push ./chartmuseum chartmuseum
```
  4. Обновить кэш репозиторев helm 
```shell
helm repo update
```
  5. Устновить пакет из chartmuseum \
```shell
helm install test-chart  chartmuseum/chartmuseum -f ./chartmuseum/values.yaml -n test
```
PS: Так же можно включить аторизацию по логину/паролю или по access token но я не стал заморачиваться ибо в задании не требуется)



Генерируем скелет инвентори 
```
docker run -t --rm -v $(pwd):/src:delegated deepmind/kapitan init --directory hipster-shop
```

Копируем библиотеки из экземпляров капитана
```
cp -r lib ~/DevOps/Otus/ilya251188_platform/kubernetes-templating/jsonnet/hipster-shop/ 
```
Меняем строку шаблона для корректного создания манифеста deployment
```
Deployment(name): $._Object("extensions/v1beta1", "Deployment", name)
>>
 Deployment(name): $._Object("apps/v1", "Deployment", name)
```

## **Kapitan**

Описываем таргет для компилятора капитана
```yaml
# cat inventory/targets/hipster-shop.yml
classes:
  - cartservice

parameters:
  target_name: prod
  namespace: hipster-shop 
  ```
  
Описываем перменные для компиляции манифеста 
```yaml
# cat inventory/classes/cartservice.yml
parameters:
  cartservice:
    image: "gcr.io/google-samples/microservices-demo/cartservice:v0.1.3"
    env:
      - name: REDIS_ADDR
        value: "redis-cart-master:6379"
      - name: PORT
        value: "7070"
      - name: LISTEN_ADDR
        value: "0.0.0.0"
    port: 7070
    namespace: hipster-shop
    resources:
      requests:
        cpu: 200m
        memory: 64Mi
      limits:
        cpu: 300m
        memory: 128Mi

  kapitan:
    vars:
      target: ${target_name}
      namespace: hipster-shop
    compile:
      - output_path: manifest
        input_type: jsonnet
        output_type: yaml
        input_paths:
          - components/cartservice/main.jsonnet
```

Описываем jsonnet-шаблоны для сервиса и деплоймента
```json
# cat components/cartservice/deployment.jsonnet


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
```

```json
# cat components/cartservice/service.jsonnet


local kube = import "lib/kube.libjsonnet";
local deployment = import "./deployment.jsonnet";

local svc = kube.Service("cartservice") {
target_pod:: deployment.cartservice.spec.template,
target_container_name:: "server",
type: "ClusterIP",
};


{
cartservice: svc
}
```

```json
# cat components/cartservice/main.jsonnet


local svc = import "./service.jsonnet";
local deployment = import "./deployment.jsonnet";


{
"service": svc.cartservice,
"deployment": deployment.cartservice,
}
```

Компилируем манифесты 
```shell
docker run -t --rm -v $(pwd):/src:delegated deepmind/kapitan compile
```

Применяем манифесты
```shell
cd compiled/prod/manifest/
```
```shell
 kubectl appl -f ./deployment.yaml -f ./service.yaml
```