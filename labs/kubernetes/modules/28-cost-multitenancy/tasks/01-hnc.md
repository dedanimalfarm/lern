# Задание 1: Иерархические Namespaces (HNC)

HNC (Hierarchical Namespace Controller) строит ДЕРЕВО namespace'ов: политики и
RBAC родителя автоматически распространяются на детей. Иерархию задают двумя
способами:

- **HierarchyConfiguration** — объект `hierarchy` в ДОЧЕРНЕМ ns со
  `spec.parent` (для уже существующих namespace);
- **SubnamespaceAnchor** — «якорь» в РОДИТЕЛЬСКОМ ns, по которому HNC сам
  создаёт дочерний namespace.

> ⚠️ Аннотацию `hnc.x-k8s.io/subnamespace-of` вручную НЕ ставят — её
> поддерживает сам контроллер для субнеймспейсов, иерархию она не задаёт.

## Практика

```bash
kubectl create namespace parent-ns
kubectl create namespace child-ns

# Вложить существующий child-ns в parent-ns:
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: child-ns
spec:
  parent: parent-ns
YAML

# Выдаём права ОДИН раз на родителя:
kubectl create rolebinding team-edit -n parent-ns --clusterrole=edit --user=dev-lead

# ...и через пару секунд они есть и у ребёнка:
kubectl get rolebinding team-edit -n child-ns
```

Создайте субнеймспейс через якорь и убедитесь, что HNC сам создал ns и
проставил служебную аннотацию:

```bash
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata:
  name: team-a-dev
  namespace: parent-ns
YAML

kubectl get ns team-a-dev -o jsonpath='{.metadata.annotations.hnc\.x-k8s\.io/subnamespace-of}{"\n"}'
kubectl get rolebinding team-edit -n team-a-dev   # права приехали и сюда
```

Проверьте «защиту от дурака»: попробуйте назначить родителем несуществующий
namespace — валидирующий вебхук HNC откажет сразу
(`requested parent "..." does not exist`).
