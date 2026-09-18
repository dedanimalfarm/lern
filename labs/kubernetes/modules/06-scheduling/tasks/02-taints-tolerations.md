# 02-taints-tolerations

## Задача
Добавить taint на ноду и разрешить подам садиться через toleration.

## Команды
```bash
kubectl taint nodes <node-name> dedicated=lab:NoSchedule
kubectl -n lab apply -f manifests/taints/deploy.yaml
```
## Ожидаемый результат
- Поды **без** toleration на затейнченную ноду не планируются; поды из
  `manifests/taints/deploy.yaml` с toleration `dedicated=lab:NoSchedule` — планируются.
- Вы объяснили, что toleration лишь *разрешает* ноду, а не притягивает к ней (для
  притяжения нужен nodeSelector/affinity), и чем `NoSchedule` отличается от `NoExecute`.
- После задания снять taint: `kubectl taint nodes <node-name> dedicated-`.
