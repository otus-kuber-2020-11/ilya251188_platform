**Kubernetes-templating**

**chartmuseum** 
  1. Включить API заменив значение переменной окружения\
`DISABLE_API: false`
  2. Добавить репозиторий в helm \
`helm repo add chartmuseum https://chartmuseum.34.67.51.134.nip.io`
  3. Загрузить в репоизторий чарт, я можно через curl дибо через плагин push для хельма \
`helm push ./chartmuseum chartmuseum`
  4. Обновить кэш репозиторев helm \
`helm repo update`
  5. Устновить пакет из chartmuseum \
`helm install test-chart  chartmuseum/chartmuseum -f ./chartmuseum/values.yaml -n test`
  PS: Так же можно включить аторизацию по логину/паролю или по access token но я не стал заморачиваться ибо в задании не требуется)
     
