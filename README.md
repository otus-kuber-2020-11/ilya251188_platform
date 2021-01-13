## Home Works
<details><summary>6. kubernetes-templating</summary>
1. Разрнут кластер Kubernetes Engine в GCP

2. Установлены готовые чарты nginx-ingress, cert-manager, chartmuseum, harbor посредством утилиты helm3

3. Создан ресурс ClusterIssuer для корректно работы cert-menager'а
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: snake251188@mail.ru
    server: https://acme-v02.api.letsencrypt.org/directory
    preferredChain: "ISRG Root X1"
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: letsencrypt
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
      - http01:
          ingress:
            class: nginx
```

4. Описан файл values.yaml для генерации ssl сертификата и создания ингресса chart-museum'a
   https://chartmuseum.34.122.143.57.nip.io

## Cahrtmuseum HWStar
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
5. Устновить пакет из chartmuseum
```shell
helm install test-chart  chartmuseum/chartmuseum -f ./chartmuseum/values.yaml -n test
```
PS: Так же можно включить аторизацию по логину/паролю или по access token но я не стал заморачиваться ибо в задании не требуется)


### Harbor
Для арбора написаны файлы values включающие ingress и генерацию сертификатов
https://harbor.34.122.143.57.nip.io/

## HelmFile
Описан деплой компонентов cert-manager, nginx-ingress, harbor посредством helmfile
Манифест лежит в каталоге kubernetes-templating/helmfile
Запуск
```shell
cd kubernetes-templating/helmfile
helmfile apply
```
## Chart

Написан helm chart  для сервиса frontend, манифесты лежат в папке kubernetes-templating/frontend
**Проверка**
```shell
helm install -n hipster-shop fronend ./frontend
```

Чарт frontend добавлен в зависимости к hipstershop
Для чарта hipster-shop добавлена зависимость от community chart stable/redis
**Проверка**
```shell
cd kubernetes-templating/
helm dependency update ./hipster-shop
helm install -n hipster-shop hipster-shop ./hipster-shop/
```

## Helm-secrets
Устновлены пакеты
```shell
brew install sops
brew install gnupg2
brew install gnu-getopt
```

Устновлен helm plugin
```shell
helm plugin install https://github.com/futuresimple/helm-secrets --version 2.0.2
```
Сгенерирован ключ и зашифрован файл секрктов,  лежит в каталоге  `kubernetes-templating/frontend/secrets.yaml`

## Kubecfg
Написаны шаблон деплоя на jsonnet для сервисов paymentservice и shippingservice
```shell
cd kubernetes-templating/kubecfg/
kubecfg update services.jsonnet --namespace hipster-shop
```

## Kapitan
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
</details>