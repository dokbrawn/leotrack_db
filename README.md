# 🛰️ LEO TRACK — База данных системы мониторинга спутникового интернета

**Расчётно-графическая работа по дисциплине «Базы данных»**  
Студент: Анисимов Тимур Юрьевич | Группа: ИКС-431  
Преподаватель: Брагин Кирилл Игоревич | СибГУТИ, 2026  

---

## 📋 Описание проекта

**LEO TRACK** — реляционная база данных для системы учёта и мониторинга спутникового интернет-сервиса на базе низкоорбитального созвездия (LEO). Система автоматизирует:

- управление орбитальными плоскостями и спутниками;
- мониторинг телеметрии (аккумулятор, температура, аномалии);
- учёт абонентов, терминалов и спутниковых лучей;
- биллинг: счета, платежи, сверхлимитные начисления;
- аналитику трафика и состояния созвездия.

---

## 📁 Структура проекта

```
leotrack/
├── docker-compose.yaml          # Запуск PostgreSQL в контейнере
├── sql/
│   ├── 01_schema.sql            # DDL: таблицы, ограничения, индексы
│   ├── 02_data.sql              # Тестовые данные (100+ записей)
│   ├── 03_functions.sql         # 9 функций PL/pgSQL
│   ├── 04_triggers.sql          # 6 триггеров + вспомогательные таблицы
│   ├── 05_queries.sql           # 10 аналитических SQL-запросов
│   └── 06_demo.sql              # Демонстрационный сценарий
├── diagram/
│   └── leotrack_er.png          # ER-диаграмма (вставить скриншот из DBeaver)
└── README.md                    # Этот файл
```

---

## 🚀 Быстрый старт

### Предварительные требования
- Docker Desktop (Windows/macOS) или Docker Engine + Compose Plugin (Linux)

### Запуск

```bash
# 1. Клонировать / распаковать проект
cd leotrack

# 2. Поднять контейнер (БД автоматически инициализируется)
docker compose up -d

# 3. Проверить статус
docker compose ps

# 4. Посмотреть логи инициализации
docker compose logs leotrack_db
```

После успешного запуска PostgreSQL будет доступен на `localhost:5432`.

---

## 🔌 Подключение к БД

### psql (из терминала)

```bash
# Подключение через Docker
docker exec -it leotrack_postgres psql -U tanis -d leotrack

# Подключение напрямую (если установлен psql локально)
psql -h localhost -p 5432 -U tanis -d leotrack
```

Параметры подключения:
| Параметр | Значение   |
|----------|------------|
| Host     | `localhost` |
| Port     | `5432`     |
| Database | `leotrack` |
| User     | `tanis`    |
| Password | `123`      |

### DBeaver / DataGrip / pgAdmin

Создать новое соединение PostgreSQL с параметрами из таблицы выше.

---

## ✅ Проверка работоспособности

### Быстрая проверка данных

```sql
-- Список абонентов с тарифными планами
SELECT s.full_name, sp.plan_name, s.balance, s.status
FROM subscribers s
JOIN service_plans sp ON sp.plan_id = s.plan_id;

-- Финансовый отчёт по периодам
SELECT billing_period,
       SUM(total_amount)  AS billed_total,
       SUM(CASE WHEN status = 'paid' THEN total_amount ELSE 0 END) AS collected
FROM invoices
GROUP BY billing_period ORDER BY billing_period;
```

### Запуск демо-сценария вручную

```bash
docker exec -it leotrack_postgres \
  psql -U tanis -d leotrack -f /docker-entrypoint-initdb.d/06_demo.sql
```

### Проверка функций

```sql
SELECT * FROM get_subscriber_finance_card(1);     -- карточка абонента
SELECT * FROM get_top_revenue_subscribers(5);      -- топ-5 плательщиков
SELECT * FROM get_overdue_subscribers(0);           -- должники
SELECT recalculate_overage_cost('2026-05');        -- пересчёт превышений
```

### Проверка триггеров

```sql
-- Должен упасть с ошибкой (баланс < -5000)
UPDATE subscribers SET balance = -9999 WHERE sub_id = 7;

-- Проверить журнал аудита
SELECT * FROM subscriber_audit ORDER BY audit_id DESC LIMIT 5;
```

---

## 🗄️ Схема базы данных

| Таблица                  | Записей | Описание                                  |
|--------------------------|---------|-------------------------------------------|
| `orbital_planes`         | 5       | Орбитальные плоскости созвездия           |
| `satellites`             | 10      | Спутники с NORAD ID и статусом            |
| `satellite_beams`        | 10      | Лучи покрытия каждого спутника            |
| `service_plans`          | 7       | Тарифные планы (Explorer → Government)   |
| `subscribers`            | 12      | Абоненты с балансом и статусом            |
| `subscriber_terminals`   | 12      | Наземные терминалы с геолокацией          |
| `beam_coverage`          | 10      | Назначение терминалов на лучи             |
| `data_sessions`          | 17      | Детализация трафика (байты, латентность)  |
| `telemetry`              | 10+     | Телеметрия спутников                      |
| `invoices`               | 24      | Счета по периодам с overage-начислениями  |
| `payments`               | 16      | Платежи (card/bank/crypto/voucher/cash)   |
| `plan_changes`           | 4       | История смены тарифов                     |

Вспомогательные (создаются в `04_triggers.sql`):
- `subscriber_audit` — журнал изменений абонентов
- `invoice_archive` — архив удалённых счетов
- `satellite_health_log` — лог аномалий телеметрии

---

## 📊 Ограничения целостности (обоснование)

### CHECK-ограничения
- `altitude_km BETWEEN 200 AND 2000` — допустимые высоты LEO-орбит (км)
- `balance >= -5000.00` — максимально допустимый долг абонента
- `status IN ('active','blocked','suspended','cancelled')` — конечный автомат статусов
- `sla_uptime_pct BETWEEN 0 AND 100` — корректный диапазон процентов
- `due_date >= issue_date` — срок оплаты не раньше выставления счёта
- `end_time > start_time` — корректность временного диапазона сессии

### UNIQUE-ограничения
- `subscribers(email)`, `subscribers(phone)` — идентификаторы клиента уникальны
- `subscriber_terminals(serial_number)` — серийный номер оборудования уникален
- `satellites(norad_id)` — международный идентификатор спутника
- `invoices(sub_id, billing_period)` — один счёт на абонента в месяц

### Стратегия индексации
Индексы созданы для полей с **высокой селективностью** и **частым использованием** в фильтрах:
- `idx_subs_status` / `idx_subs_balance` — фильтрация должников и заблокированных
- `idx_sessions_terminal_start` (составной) — быстрая выборка последних сессий терминала
- `idx_tlm_anomaly` (partial, `WHERE anomaly_flag = TRUE`) — только аномальные записи, экономия места
- `idx_tlm_sat_time` (составной) — телеметрия конкретного спутника за период
- `idx_inv_status` / `idx_inv_period` — биллинговые выборки по статусу и периоду

---

## 🧹 Очистка данных (сброс)

```bash
# Остановить контейнер и удалить volume с данными
docker compose down -v

# Повторный запуск с чистой инициализацией
docker compose up -d
```

> ⚠️ Команда `down -v` **безвозвратно удаляет** все данные БД. Используйте только для полного сброса.

---

## 📂 SQL-файлы — краткое содержание

| Файл             | Содержание |
|------------------|------------|
| `01_schema.sql`  | CREATE TABLE (12 таблиц), CHECK/UNIQUE/FK, 17+ индексов |
| `02_data.sql`    | INSERT: 100+ строк тестовых данных |
| `03_functions.sql`| 9 функций PL/pgSQL (скалярные и table-returning) |
| `04_triggers.sql`| 3 вспомогательные таблицы + 6 триггеров |
| `05_queries.sql` | 10 аналитических запросов с JOIN/CTE/HAVING/ORDER BY |
| `06_demo.sql`    | Демонстрация всех функций и триггеров с проверкой |
