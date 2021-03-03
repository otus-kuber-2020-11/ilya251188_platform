## 6. kubernetes-templating
<details>
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

## 7. kubernetes-operators
<details>

### CR & CRD
1. Создал cr и crd 
2. Добавляем валидатор для CR \
P.S в версии k8s `Major:"1", Minor:"18+", GitVersion:"v1.18.12-gke.1200"`,
включен `preserveUnknownFields` для поддержки обратной совместимости и поле usless_data не приводите к ошибке
валидации CR. \
Добавил:
```yaml
preserveUnknownFields: false
```
3. Добавил в зависмости поля `spec` и его содержимое:
```yaml
  validation:
    openAPIV3Schema:
      type: object
      required: ["spec"]
.......
       spec:
          type: object
          required: ["image", "database", "password", "storage_size"]
```

### Контроллер
1. Создаем файлы шаблонов для манифестов 
2. Копипастим  оператор 
3. Ставим зависимости
```shell
pip install --upgrade pip kopf kubernetes jinja2
```
**Вопрос: почему объект создался, хотя мы создали CR, до того, как запустили контроллер?** \
_Конртроллер подписывается на уведомления.\
Уведолмения апи-сервером отправляет не только об только создаваемых ресусрах, но и о уже существующих.

4. Создаем образ с контроллером
5. Добавили манифесты для деплоя оператора

```shell
k get jobs.batch
NAME                         COMPLETIONS   DURATION   AGE
backup-mysql-instance-job    1/1           1s         5m1s
restore-mysql-instance-job   1/1           46s        3m57s
```
```shell
kubectl exec -it $MYSQLPOD -- mysql -potuspassword -e "select * from test;" otus-database
mysql: [Warning] Using a password on the command line interface can be insecure.
+----+-------------+
| id | name        |
+----+-------------+
|  1 | some data   |
|  2 | some data-2 |
+----+-------------+
```
</details>

## 8. Kubernetes-monitoring
<details>

 1. Создаем namespace для prometheus
```shell
k create ns prometheus
```


2. Добавляем репозитрий prometheus-stack
```shell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

```

3. Выгружаем values файл
```shell
helm show values prometheus-community/kube-prometheus-stack > values.yaml
```

4. Устанавливаем prometheus-stack
```shell
helm install -n prometheus prometheus prometheus-community/kube-prometheus-stack -f ./values.yaml
```

5. Создаем NS nginx
```shell
k create ns nginx
```

6. Пишем маниесты для запуска nginx (каталог kubernetes-monitoring/nginx)

7. Применяем манифесты
```shell
k apply -f nginx/nginx-cm.yaml -f nginx/nginx-svc.yaml -f nginx/nginx-deployment.yaml
```

Проверяем что сервис запустился
```shell
k get all -n nginx
NAME                                    READY   STATUS    RESTARTS   AGE
pod/nginx-deployment-6857fdcbf7-jrrkd   1/1     Running   0          11s
pod/nginx-deployment-6857fdcbf7-trf4q   1/1     Running   0          11s
pod/nginx-deployment-6857fdcbf7-xcspx   1/1     Running   0          11s

NAME                TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)           AGE
service/nginx-svc   ClusterIP   10.40.2.82   <none>        80/TCP,8080/TCP   13s

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-deployment   3/3     3            3           13s

NAME                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-deployment-6857fdcbf7   3         3         3       13s
```

8. Добавлем в шаблон пода nginx контейнер с nginx-opertor'ом и прменяем 
```shell
k apply -f nginx/nginx-deployment.yaml
```   
9. Добавлеям additionalServiceMonitors в values чарта 
```yaml
  additionalServiceMonitors:
      - name: "nginx-operator"
        selector:
          matchLabels:
            svc: nginx
        namespaceSelector:
          matchNames:
            - nginx
        endpoints:
          - port: "operator"
            targetPort: 9113
            path: /metrics
```
Обновляем манифесты 
```shell
helm upgrade --install -n prometheus prometheus prometheus-community/kube-prometheus-stack -f values.yaml
```
Скриншот дашборда для nginx
![Alt text](./kubernetes-monitoring/images/2021-01-19_02-45-24.png?raw=true "Grafana")

Таже ресусрсы доступны по ссылкам: \
http://grafana.34.122.143.57.nip.io (pwd in values.yaml) \
http://prometheus.34.122.143.57.nip.io/graph
</details>

## 9. Kubernetes-logging
<details>

#### Подготовка
Создал новый кластер в gcp
```shell
k get node
NAME                                     STATUS                     ROLES    AGE     VERSION
gke-logiing-default-pool-1a619026-dtpg   Ready                      <none>   5m44s   v1.16.15-gke.6000
gke-logiing-infra-pool-07e8b735-0vl5     Ready                      <none>   5m46s   v1.16.15-gke.6000
gke-logiing-infra-pool-07e8b735-4dws     Ready                      <none>   5m46s   v1.16.15-gke.6000
gke-logiing-infra-pool-07e8b735-ljrf     Ready                      <none>   5m46s   v1.16.15-gke.6000
```

Поставил hipster-hope
```shell
k create ns microservices-demo

k apply -f https://raw.githubusercontent.com/express42/otus-platform-snippets/master/Module-02/Logging/microservices-demo-without-resources.yaml -n m
icroservices-demo

kgp -n microservices-demo -o wide
NAME                                     READY   STATUS             RESTARTS   AGE     IP          NODE                                     NOMINATED NODE   READINESS GATES
adservice-cb695c556-mn56r                1/1     Running            0          2m15s   10.8.4.20   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
cartservice-f4677b75f-d5z8q              1/1     Running            2          2m17s   10.8.4.16   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
checkoutservice-664f865b9b-jgnc5         1/1     Running            0          2m19s   10.8.4.11   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
currencyservice-bb9d998bd-hcvsm          1/1     Running            0          2m16s   10.8.4.18   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
emailservice-6756967b6d-crgfl            1/1     Running            0          2m19s   10.8.4.10   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
frontend-766587959d-2jd9s                1/1     Running            0          2m18s   10.8.4.13   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
loadgenerator-9f854cfc5-p9wr4            0/1     CrashLoopBackOff   3          2m17s   10.8.4.17   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
paymentservice-57c87dc78b-b2fsg          1/1     Running            0          2m18s   10.8.4.14   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
productcatalogservice-9f5d68b54-x59d9    1/1     Running            0          2m17s   10.8.4.15   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
recommendationservice-57c49756fd-rhzc8   1/1     Running            0          2m19s   10.8.4.12   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
redis-cart-5f75fbd9c7-qsvt4              1/1     Running            0          2m16s   10.8.4.21   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
shippingservice-689c6457cd-27vcw         1/1     Running            0          2m16s   10.8.4.19   gke-logiing-default-pool-1a619026-dtpg   <none>           <none>
```

#### EFK

Добавляем репо
```shell
helm repo add elastic https://helm.elastic.co

helm repo update
```

Ставим чарты 
```shell
k create ns observability

helm install -n observability elasticsearch elastic/elasticsearch

helm install -n observability kibana elastic/kibana

helm install -n observability fluent-bit stable/fluent-bit
```

Правим values для elasticsearch и обновляем манифесты
```shell
helm show values elastic/elasticsearch > kubernetes-logging/elasticsearch.values.yaml

helm upgrade --install -n observability elasticsearch elastic/elasticsearch -f kubernetes-logging/elasticsearch.values.yaml

NAME                             READY   STATUS    RESTARTS   AGE   IP          NODE                                     NOMINATED NODE   READINESS GATES
elasticsearch-master-0           1/1     Running   0          36m   10.8.2.2    gke-logiing-infra-pool-07e8b735-ljrf     <none>           <none>
elasticsearch-master-1           1/1     Running   0          38m   10.8.1.2    gke-logiing-infra-pool-07e8b735-4dws     <none>           <none>
elasticsearch-master-2           1/1     Running   0          39m   10.8.0.2    gke-logiing-infra-pool-07e8b735-0vl5     <none>           <none>
```

Ставим ingress
```shell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm repo update

k create ns nginx-ingress

helm show values ingress-nginx/ingress-nginx > kubernetes-logging/nginx-ingress.values.yaml

helm upgrade --install -n nginx-ingress nginx-ingress ingress-nginx/ingress-nginx -f kubernetes-logging/nginx-ingress.values.yaml

kgp -n nginx-ingress -o wide
NAME                                                      READY   STATUS    RESTARTS   AGE     IP         NODE                                   NOMINATED NODE   READINESS GATES
nginx-ingress-ingress-nginx-controller-5865bbc6f6-kp5n9   1/1     Running   0          2m53s   10.8.2.4   gke-logiing-infra-pool-07e8b735-ljrf   <none>           <none>
nginx-ingress-ingress-nginx-controller-5865bbc6f6-q24qd   1/1     Running   0          2m8s    10.8.1.4   gke-logiing-infra-pool-07e8b735-4dws   <none>           <none>
nginx-ingress-ingress-nginx-controller-5865bbc6f6-tdldm   1/1     Running   0          2m33s   10.8.0.4   gke-logiing-infra-pool-07e8b735-0vl5   <none>           <none>
```

Обновляем кибану
```shell
helm show values elastic/kibana > kubernetes-logging/kibana.values.yaml
 
helm upgrade --install -n observability kibana elastic/kibana -f kubernetes-logging/kibana.values.yaml
```

Теперь кибана доступна по ссылке http://kibana.104.155.18.162.xip.io

Обновляем fluent-bit
```shell
helm show values stable/fluent-bit > kubernetes-logging/fluent-bit.values.yaml

helm upgrade --install -n observability fluent-bit stable/fluent-bit -f kubernetes-logging/fluent-bit.values.yaml
```

#### EFK :star:

Не осилил. 

Как я понял можно использовать парсер для json формата (https://docs.fluentbit.io/manual/pipeline/parsers/json) с декодером (https://docs.fluentbit.io/manual/pipeline/parsers/decoders)
но настроить так и не вышло.

#### Мониторинг ElasticSearch

Устанавливаем prometheus-stack с включенным инрессом для графаны (grafana.104.155.18.162.xip.io) и nodeSelector'ами и tollerations для сервисов alertmanager и prometheus
```shell
helm upgrade --install -n observability prom-stack prometheus-community/kube-prometheus-stack -f kubernetes-logging/prometheus-stack.yaml
```

Устанавливаем elasticsearch-exporter
```shell
helm upgrade --install elasticsearch-exporter stable/elasticsearch-exporter --set es.uri=http://elasticsearch-master:9200 --set serviceMonitor.enabled=true --namespace=observability
```

Добавляем additionalServiceMonitors для сбора метрик с сервиса elasticsearch-exporter
```yaml
 additionalServiceMonitors:
    - name: "elastic-operator"
      selector:
         matchLabels:
            release: elasticsearch-exporter
      namespaceSelector:
         matchNames:
            - observability
      endpoints:
         - port: http
           targetPort: 9108
           interval: 10s
           path: /metrics
```

Апдейтим prometheus-stack
```shell
helm upgrade --install -n observability prom-stack prometheus-community/kube-prometheus-stack -f kubernetes-logging/prometheus-stack.yaml
```

Выводим одну ноду из infra-pool в drain-mode
```shell
k drain gke-logiing-infra-pool-07e8b735-0vl5 --ignore-daemonsets --delete-emptydir-data
```
И еще одну 

Смотрим что эластик сломался.

Включаем ingress для alermanager

Добавляем правило алертинга из ДЗ
```yaml
prometheusRule:
  enabled: true
  labels: {}
  rules:
    - alert: ElasticsearchTooFewNodesRunning
      expr: elasticsearch_cluster_health_number_of_nodes{service="{{ template "elasticsearch-exporter.fullname" . }}"} < 3
      for: 5m
      labels:
        severity: critical
      annotations:
        description: There are only {{ "{{ $value }}" }} < 3 ElasticSearch nodes running
        summary: ElasticSearch running on less than 3 nodes
```

Применяем
```shell
helm upgrade --install elasticsearch-exporter stable/elasticsearch-exporter -n observability -f kubernetes-logging/elastic-exporter.yaml
```

#### EFK | nginx ingress

Fluent-bit запустился на ноде из default-pool, добавляем toleration для вбора нод с меткой node-role=infra
```yaml
tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule
```

Меняем формат лога на json
```yaml
  config:
    log-format-escape-json: "true"
    log-format-upstream: '{"time": "$time_iso8601", "remote_addr": "$proxy_protocol_addr", "x_forward_for": "$proxy_add_x_forwarded_for", "request_id": "$req_id",
      "remote_user": "$remote_user", "bytes_sent": $bytes_sent, "request_time": $request_time, "status": $status, "vhost": "$host", "request_proto": "$server_protocol",
      "path": "$uri", "request_query": "$args", "request_length": $request_length, "duration": $request_time,"method": "$request_method", "http_referrer": "$http_referer",
      "http_user_agent": "$http_user_agent" }'
```

Рисуем дашборд по ответам от ингесс-контроллеров
Правлю поля так как их у меня почему то-нет:

kubernetes.labels.app : nginx-ingress -> kubernetes.labels.app_kubernetes_io/name: ingress-nginx

#### Loki

Устанавливаем loki

```shell
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm show values grafana/loki-stack > kubernetes-logging/loki.values.yaml
```
```yaml
loki:
  enabled: true

promtail:
  enabled: true
```

```shell
helm upgrade --install -n observability loki grafana/loki-stack -f kubernetes-logging/loki.values.yaml
```

Добавляем создание datasource для loki в prometheus-stack 
```yaml
  additionalDataSources:
    - name: loki
      access: proxy
      type: loki
      url: http://loki:3100
```

Добавляем toleration для promtail чтбы он завелся на нодах infra-pool где живет ингресс
```yaml
promtail:
  enabled: true
  tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule
```

Включаем сервис для предоставления метрик 
```yaml
metrics:
    port: 10254
    # if this port is changed, change healthz-port: in extraArgs: accordingly
    enabled: true

.....

    serviceMonitor:
      enabled: true
      additionalLabels: {}
      namespace: ""
      namespaceSelector: {}
      # Default: scrape .Release.Namespace only
      # To scrape all, use the following:
      # namespaceSelector:
      #   any: true
      scrapeInterval: 30s
      # honorLabels: true
      targetLabels: []
      metricRelabelings: []
```

Прометей его не увидел добавил ему свой СА
```yaml
    - name: "nginx-ingress-ingress-nginx-controller"
      selector: 
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
      namespaceSelector:
        matchNames:
          - nginx-ingress
      endpoints:
        - port: metrics
```

Настроили дашборд показывающий логи ingress-controller и успешные статусы ответа от nginx

#### k8s-event-logger

Поставил утилиту 
```shell
helm install -n observability k8s-event-logger ./chart
```

Евенты подхватил loki в кибане от fluent bit событий что то не увидел
![Alt text](./kubernetes-logging/screenshots/grafana.png?raw=true "Grafana")

![Alt text](./kubernetes-logging/screenshots/kibana.png?raw=true "kibana")

#### Audit logging | Задание со :star:

Добавляем в манифесты кубера файл audit-policy.yaml:
```shell
ll /etc/kubernetes/manifests/
total 32
drwxr-xr-x 1 root root 4096 Feb 16 23:20 ./
drwxr-xr-x 1 root root 4096 Feb 16 23:12 ../
-rw-r--r-- 1 root root 2218 Feb 16 23:20 audit-policy.yaml
-rw------- 1 root root 2297 Feb 16 23:12 etcd.yaml
-rw------- 1 root root 4029 Feb 16 23:12 kube-apiserver.yaml
-rw------- 1 root root 3339 Feb 16 23:12 kube-controller-manager.yaml
-rw------- 1 root root 1385 Feb 16 23:12 kube-scheduler.yaml
```

Добавляем в манфиест апи сервера подгрузку политик и вольюмы для записи логов 

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --audit-log-path=/var/log/audit.log
..........

volumeMounts:
..........

   - mountPath: /etc/kubernetes/audit-policy.yaml
     name: audit
     readOnly: true
   - mountPath: /var/log/audit.log
     name: audit-log
     readOnly: false
..........

volumes:
..........

- name: audit
  hostPath:
     path: /etc/kubernetes/manifests/audit-policy.yaml
     type: File
- name: audit-log
  hostPath:
     path: /var/log/kubernetes-audit.log
     type: FileOrCreate
```

Доавляем сбор лога в fluentbit
```yaml
audit:
  enable: true
  input:
    memBufLimit: 35MB
    parser: docker
    tag: kube-audit.*
    path: /var/log/kubernetes-audit.log
    bufferChunkSize: 2MB
    bufferMaxSize: 10MB
    skipLongLines: On
    key: kubernetes-audit
```

Результат
![Alt text](./kubernetes-logging/screenshots/audit-log.png?raw=true "Audit")

#### Host logging | Задание со :star:

Добавляем запись логов journald 
```yaml
  systemd:
    enabled: true
    maxEntries: 1000
    readFromTail: true
    stripUnderscores: false
    tag: host.*
```

</details>