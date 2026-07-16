# max_api_client

Ruby gem для работы с Max Bot API.

## Состояние

Текущая реализация на Ruby включает  API-клиент со следующими возможностями:

- высокоуровневый `MaxApiClient::Api`
- низкоуровневый `MaxApiClient::RawApi`
- сгруппированные методы для bot/chat/message/subscription/upload
- вспомогательные объекты вложений для результатов загрузки

## Установка

Добавьте gem в проект:

```ruby
# Gemfile
gem "max_api_client", git: "git@github.com:Ziaw/max_api_client.git"
```

```bash
bundle install
```

## Адрес API и сертификат Минцифры

По умолчанию клиент использует актуальный адрес `https://platform-api2.max.ru`.
В gem включён корневой сертификат `Russian Trusted Root CA`, поэтому TLS-цепочка
MAX проверяется вместе с обычным системным хранилищем доверенных сертификатов.
По умолчанию проверка TLS включена.

Актуальные сертификаты и инструкции по их системной установке опубликованы
на Госуслугах: <https://www.gosuslugi.ru/crt>.

Обычное подключение не требует дополнительных настроек:

```ruby
api = MaxApiClient::Api.new(
  token: ENV.fetch("MAX_BOT_TOKEN")
)
```

Доступные параметры подключения:

- `base_url` — адрес MAX API, по умолчанию `https://platform-api2.max.ru`;
- `ca_file` — путь к дополнительному доверенному CA-файлу;
- `verify_ssl` — проверять сертификат сервера, по умолчанию `true`;
- `open_timeout` — таймаут установления соединения;
- `read_timeout` — таймаут чтения ответа.

Эти параметры поддерживают как `MaxApiClient::Api`, так и
`MaxApiClient::Client`.

### Подключение собственного сертификата

Передайте путь к актуальному сертификату Минцифры в формате PEM:

```ruby
api = MaxApiClient::Api.new(
  token: ENV.fetch("MAX_BOT_TOKEN"),
  ca_file: "/etc/ssl/certs/russian_trusted_root_ca.pem"
)
```

Чтобы использовать только системное хранилище сертификатов, передайте
`ca_file: nil`.

### Игнорирование неверного сертификата

Если окружение временно не может проверить сертификат, отключите проверку
параметром `verify_ssl: false`:

```ruby
api = MaxApiClient::Api.new(
  token: ENV.fetch("MAX_BOT_TOKEN"),
  verify_ssl: false
)
```

`verify_ssl: false` принимает любой серверный сертификат и делает соединение
уязвимым для перехвата. Используйте эту настройку только как временный обходной
вариант. Для постоянной настройки передайте актуальный сертификат через
`ca_file` или установите его в системное хранилище.

Полный пример настройки:

```ruby
api = MaxApiClient::Api.new(
  token: ENV.fetch("MAX_BOT_TOKEN"),
  base_url: "https://platform-api2.max.ru",
  ca_file: MaxApiClient::Client::DEFAULT_CA_FILE,
  verify_ssl: true,
  open_timeout: 10,
  read_timeout: 30
)
```

## Справочник API

### Методы бота

Методы доступные через `MaxApiClient::Api`, порт официального клиента <https://github.com/max-messenger/max-bot-api-client-ts>, названия сохранены, poller собственный:

- `get_my_info`
- `edit_my_info(**extra)`
- `set_my_commands(commands)`
- `delete_my_commands`

`set_my_commands(commands)` это короткий хелпер над `edit_my_info(commands: ...)`.
Он принимает массив команд и отправляет его в поле `commands` профиля бота.

Ожидается массив хэшей с данными команды, например:

```ruby
api.set_my_commands([
  { name: "start", description: "Запустить бота" },
  { name: "help", description: "Показать справку" }
])
```

`delete_my_commands` делает то же самое, но передаёт пустой массив и тем самым очищает список команд.

Соответствующие HTTP-маршруты:

- `GET /me`
- `PATCH /me`

Типовые сценарии:

- получить текущий профиль бота;
- обновить имя, описание, аватар и команды бота;
- опубликовать или очистить подсказки команд для пользователей.

### Методы чатов

Методы Ruby, доступные через `MaxApiClient::Api`:

- `get_all_chats(**extra)`
- `get_chat(chat_id)`
- `get_chat_by_link(chat_link)`
- `edit_chat_info(chat_id, **extra)`
- `get_chat_membership(chat_id)`
- `get_chat_admins(chat_id)`
- `add_chat_members(chat_id, user_ids)`
- `get_chat_members(chat_id, **extra)`
- `remove_chat_member(chat_id, user_id)`
- `get_pinned_message(chat_id)`
- `pin_message(chat_id, message_id, **extra)`
- `unpin_message(chat_id)`
- `send_action(chat_id, action)`
- `leave_chat(chat_id)`

Соответствующие HTTP-маршруты:

- `GET /chats`
- `GET /chats/{chat_id}`
- `GET /chats/{chat_link}`
- `PATCH /chats/{chat_id}`
- `GET /chats/{chat_id}/members/me`
- `GET /chats/{chat_id}/members/admins`
- `POST /chats/{chat_id}/members`
- `GET /chats/{chat_id}/members`
- `DELETE /chats/{chat_id}/members`
- `GET /chats/{chat_id}/pin`
- `PUT /chats/{chat_id}/pin`
- `DELETE /chats/{chat_id}/pin`
- `POST /chats/{chat_id}/actions`
- `DELETE /chats/{chat_id}/members/me`

Типовые сценарии:

- получить список чатов, доступных боту;
- найти чат по идентификатору или публичной ссылке;
- изменить заголовок, иконку и метаданные чата;
- управлять участниками и администраторами;
- читать, устанавливать и снимать закреплённые сообщения;
- отправлять статус набора текста и другие действия отправителя;
- выходить из чата.

### Методы сообщений

Методы Ruby, доступные через `MaxApiClient::Api`:

- `send_message_to_chat(chat_id, text, **extra)`
- `send_message_to_user(user_id, text, **extra)`
- `get_messages(chat_id, **extra)`
- `get_message(message_id)`
- `edit_message(message_id, **extra)`
- `delete_message(message_id, **extra)`
- `answer_on_callback(callback_id, **extra)`

Соответствующие HTTP-маршруты:

- `POST /messages`
- `GET /messages`
- `GET /messages/{message_id}`
- `PUT /messages`
- `DELETE /messages`
- `POST /answers`

Поддерживаемые возможности:

- отправка обычного текста в чат или напрямую пользователю;
- дополнительный payload для форматирования, reply-ссылок и вложений;
- редактирование и удаление сообщений;
- ответы на callback-кнопки;
- автоматический повтор запроса, если вложение после загрузки ещё не готово.

### Методы подписок

Методы Ruby, доступные через `MaxApiClient::Api`:

- `get_subscriptions`
- `subscribe(url, update_types: nil, secret: nil)`
- `unsubscribe(url)`
- `poll_updates(types = [], marker: nil, timeout: 20, retry_interval: 5, read_timeout: nil, &block)`

Соответствующие HTTP-маршруты:

- `GET /subscriptions`
- `POST /subscriptions`
- `DELETE /subscriptions`
- `GET /updates`

Типовые сценарии:

- получить список активных webhook-подписок бота;
- создать webhook-подписку на нужные типы обновлений;
- удалить подписку по URL webhook;
- использовать polling через `poll_updates`, если webhook не нужен.

Пример long polling:

```ruby
poller = api.poll_updates(%w[message_created], timeout: 20)

poller.each do |update|
  puts update["update_type"]
  # poller.stop if нужно остановить цикл
end
```

`poll_updates` автоматически:

- передаёт `marker` между запросами;
- поднимает HTTP `read_timeout` выше API `timeout`;
- повторяет запрос после временных сетевых ошибок, `429` и `5xx`.

### Методы загрузки

Методы Ruby, доступные через `MaxApiClient::Api`:

- `upload_image(options)`
- `upload_video(options)`
- `upload_audio(options)`
- `upload_file(options)`

Связанный HTTP-маршрут:

- `POST /uploads`

Вспомогательные классы вложений:

- `ImageAttachment`
- `VideoAttachment`
- `AudioAttachment`
- `FileAttachment`
- `StickerAttachment`
- `LocationAttachment`
- `ShareAttachment`

### Доступ к Raw API

Низкоуровневый доступ через `api.raw` поддерживает:

- `get`
- `post`
- `put`
- `patch`
- `delete`

## Логирование

Если нужен отладочный лог HTTP-обмена, можно задать глобальный логгер:

```ruby
MaxApiClient.logger = Logger.new($stdout)
```

Либо передать логгер в конкретный клиент:

```ruby
api = MaxApiClient::Api.new(token: ENV.fetch("MAX_BOT_TOKEN"), logger: Logger.new($stdout))
```

Если логгер задан, клиент пишет в `debug` данные запроса и ответа.

## Разработка

Склонируйте репозиторий и установите зависимости:

```bash
git clone git@github.com:Ziaw/max_api_client.git
cd max_api_client
bundle install
```

Полезные команды:

```bash
bundle exec rake test
bin/console
```


## Релиз

Релиз публикуется через GitHub Releases и GitHub Actions.

Перед релизом:

1. Обновите версию в `lib/max_api_client/version.rb`.
2. Перенесите изменения из `Unreleased` в `CHANGELOG.md`.
3. Закоммитьте изменения в `master`.

## Приоритеты реализации

Рекомендуемый порядок развития Ruby-клиента:

1. HTTP-клиент и слой ошибок.
2. Интерфейс raw-запросов.
3. Высокоуровневая обёртка `Api` для bot, chat, message и update endpoints.
4. Механизм загрузки файлов и объекты вложений. (вы находитесь здесь)
5. Опциональный bot framework с polling, context и middleware.

## Источники

- Официальная документация Max Bot API: <https://dev.max.ru/>
- TypeScript reference client: <https://github.com/max-messenger/max-bot-api-client-ts>

## Лицензия

Проект распространяется по лицензии MIT. См. [`LICENSE.txt`](./LICENSE.txt).
