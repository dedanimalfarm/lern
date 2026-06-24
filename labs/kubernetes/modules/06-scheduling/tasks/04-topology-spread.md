# Дополнительная задача: Topology Spread Constraints

Настройте равномерное распределение реплик Deployment по нодам (zone или hostname).

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: spread-app
```