# mlops-train-automation

Автоматизація тренування ML-моделей: AWS Step Functions запускає спрощений
workflow із двох кроків — `ValidateData` → `LogMetrics`, кожен з яких
викликає окрему Lambda-функцію. Інфраструктура описана в Terraform, а
GitLab CI автоматично запускає Step Function після кожного push у гілку.

## Архітектура

```
GitLab CI (push) ──> aws stepfunctions start-execution
                              │
                              ▼
                     Step Function: train-pipeline
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              ValidateData ────────► LogMetrics
              (Lambda: validate)   (Lambda: log_metrics)
```

- **ValidateData** — умовна валідація вхідних даних (`terraform/lambda/validate.py`).
- **LogMetrics** — умовне логування результатів (`terraform/lambda/log_metrics.py`).
- Обидва кроки виконуються послідовно в межах одного `aws_sfn_state_machine`.

## Структура проєкту

```
mlops-train-automation/
├── terraform/
│   ├── main.tf          # IAM-ролі, Lambda-функції, Step Function
│   ├── data.tf           # data-джерела (caller identity, archive_file)
│   ├── terraform.tf      # провайдери (aws, archive)
│   ├── variables.tf       # вхідні змінні
│   ├── outputs.tf         # ARN Step Function та Lambda (зручно для CI)
│   └── lambda/
│       ├── validate.py
│       ├── log_metrics.py
│       ├── validate.zip
│       └── log_metrics.zip
├── .gitlab-ci.yml
└── README.md
```

## Передумови

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS CLI, налаштований доступ до облікового запису AWS
- Python 3.12 (лише для локального редагування Lambda-коду; збірка `.zip`
  виконується або вручну, або автоматично через `archive_file` в Terraform)

## 1. Створення `.zip`-архівів для Lambda

Terraform сам перепаковує архіви через `data.archive_file` при кожному
`terraform apply`, тож вручну це робити не обов'язково. Якщо потрібно
зібрати архіви вручну (наприклад, для перевірки вмісту):

```bash
cd terraform/lambda
zip validate.zip validate.py
zip log_metrics.zip log_metrics.py
```

У результаті в `terraform/lambda/` мають бути два `.py`-файли та два
відповідні `.zip`-архіви.

## 2. Розгортання інфраструктури через Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Після успішного `apply` Terraform виведе (`outputs.tf`):

- `state_machine_arn` — ARN Step Function, потрібен для GitLab CI змінної `STATE_MACHINE_ARN`;
- `validate_lambda_arn`;
- `log_metrics_lambda_arn`.

За замовчуванням стек розгортається в регіоні `eu-central-1` (змінна
`aws_region` у `variables.tf`) — за потреби перевизначте через
`-var="aws_region=..."` або `terraform.tfvars`.

## 3. Ручний запуск Step Function

### Через AWS Console

1. Відкрийте **Step Functions** → знайдіть state machine
   `mlops-train-automation-train-pipeline`.
2. Натисніть **Start execution**.
3. Вставте вхідний JSON (приклад нижче) і підтвердіть запуск.
4. Перевірте, що обидва кроки (`ValidateData`, `LogMetrics`) відпрацювали
   успішно (статус `Succeeded`), і подивіться логи в CloudWatch Logs
   (`/aws/lambda/mlops-train-automation-validate` та
   `/aws/lambda/mlops-train-automation-log-metrics`).

### Через AWS CLI

```bash
aws stepfunctions start-execution \
  --state-machine-arn "$(terraform -chdir=terraform output -raw state_machine_arn)" \
  --name "manual-$(date +%s)" \
  --input '{"source": "manual", "commit": "local-test"}'
```

## 4. GitLab CI

Файл `.gitlab-ci.yml` містить один job — `train-model`:

- Виконується на стадії `train`.
- Використовує офіційний образ `amazon/aws-cli:2.15.0`.
- Запускається автоматично на кожен `push` (`rules: $CI_PIPELINE_SOURCE == "push"`).
- Викликає `aws stepfunctions start-execution`, передаючи вхідні параметри
  у форматі JSON: джерело запуску (`gitlab-ci`) та короткий SHA коміту
  (`$CI_COMMIT_SHORT_SHA`).

Приклад JSON, який передається до Step Function із CI:

```json
{
  "source": "gitlab-ci",
  "commit": "a1b2c3d"
}
```

### Необхідні змінні GitLab CI

Додайте в **Settings → CI/CD → Variables**:

| Змінна | Опис |
|---|---|
| `STATE_MACHINE_ARN` | ARN Step Function (значення з `terraform output state_machine_arn`) |
| `AWS_ACCESS_KEY_ID` | Ключ доступу AWS (або не потрібен, якщо використовується OIDC) |
| `AWS_SECRET_ACCESS_KEY` | Секретний ключ AWS (або не потрібен при OIDC) |
| `AWS_DEFAULT_REGION` | Регіон AWS, напр. `eu-central-1` |

Якщо в GitLab налаштована OIDC-інтеграція з AWS, замість статичних
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` використовуйте тимчасові
credentials через `id_tokens` та `aws sts assume-role-with-web-identity`
у job — постійні ключі в такому разі не потрібні.

## Перевірка результату

1. `terraform apply` завершився без помилок, і в AWS існують: дві Lambda-функції,
   дві IAM-ролі, одна Step Function.
2. Ручний запуск Step Function (Console або CLI) завершується статусом
   `Succeeded` для обох кроків.
3. Push у гілку `lesson-10` тригерить job `train-model` у GitLab CI, і в
   AWS Console видно нове виконання Step Function з `source: "gitlab-ci"`.
