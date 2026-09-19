# max_api_client

Ruby gem для работы с MAX Bot API. Высокоуровневый `MaxApiClient::Api`,
группированный `api.raw`, загрузка медиа, объекты вложений и Long Polling.
Контракт сверяется с [max-docs](https://github.com/max-hackaton/max-docs/tree/main/bot-api)
и [документацией MAX](https://dev.max.ru/docs-api). Последняя проверка: **15 сентября 2026**.

## Установка

```ruby
# Gemfile
gem "max_api_client", git: "https://github.com/max-hackaton/max_api_client.git"
```

```bash
bundle install
```

До merge исправления доступны только в PR-ветке; для её проверки добавьте
`branch: "fix/bot-api-contract-2026-09-15"` к зависимости из Git.

## Подключение и TLS

```ruby
require "max_api_client"

api = MaxApiClient::Api.new(
  token: ENV.fetch("MAX_BOT_TOKEN"),
  open_timeout: 10,
  read_timeout: 30
)
```

По умолчанию используется `https://platform-api2.max.ru`, авторизация через
`Authorization: <token>`, проверка TLS включена. В gem включён корневой сертификат
`Russian Trusted Root CA`; он добавляется к системному хранилищу доверенных сертификатов.
Актуальные сертификаты и инструкции: <https://www.gosuslugi.ru/crt>.

Параметры `Api.new` и `Client.new`:

| Параметр | Назначение |
| --- | --- |
| `token` | Токен бота; обязателен |
| `base_url` | Адрес API; по умолчанию `https://platform-api2.max.ru` |
| `ca_file` | Дополнительный CA-файл; по умолчанию сертификат из gem, `nil` — только системные CA |
| `verify_ssl` | Проверка сертификата сервера; по умолчанию `true` |
| `open_timeout`, `read_timeout` | Таймауты соединения и чтения |
| `logger` | Логгер конкретного клиента |
| `adapter` | Альтернативный транспорт, в том числе для тестов |

Для своего сертификата передайте `ca_file: "/etc/ssl/certs/russian_trusted_root_ca.pem"`.
`verify_ssl: false` принимает любой серверный сертификат и делает соединение уязвимым
для перехвата; это только временный диагностический обход, не production-настройка.

## Бот и команды

```ruby
api.get_my_info
api.set_my_commands([{ name: "start", description: "Запустить бота" }])
api.delete_my_commands
api.raw.bots.edit_my_commands(commands: [])
```

Получение профиля: `GET /me`. Изменение и очистка команд: **`PATCH /me/commands`**,
JSON `{ commands: [...] }`; пустой массив удаляет команды, максимум 32 команды.
Метод изменения возвращает данные команд, а не полный профиль бота.

`edit_my_info(commands: ...)` сохранён как совместимый вызов endpoint команд.
Другие поля и смешанные запросы отклоняются с `ArgumentError` до обращения к API:
клиент больше не обещает менять имя, описание и аватар через старый `PATCH /me`.

Источник: [Редактирование команд](https://dev.max.ru/docs-api/methods/PATCH/me/commands).

## Чаты и администраторы

Обычные методы: `get_chat(chat_id)`, `edit_chat_info(chat_id, **extra)`,
`get_chat_membership(chat_id)`, `get_chat_admins(chat_id)`, `get_chat_members(chat_id, **extra)`,
`remove_chat_member(chat_id, user_id, block: nil)`, `get_pinned_message(chat_id)`,
`pin_message(chat_id, message_id, **extra)`, `unpin_message(chat_id)`,
`send_action(chat_id, action)` и `leave_chat(chat_id)`.

```ruby
api.get_chat(-123)
api.get_chat_members(-123, user_ids: [10, 20], count: 20)
api.remove_chat_member(-123, 42, block: false)

api.set_chat_admins(-123, [
  { user_id: 42, permissions: %w[read_all_messages write], alias: "Редактор" }
])
api.remove_chat_admin(-123, 42)
```

`set_chat_admins(chat_id, admins, marker: nil)` использует
`POST /chats/{chatId}/members/admins`. Массив `admins` и необязательный `marker`
передаются в JSON body. Повторное назначение **заменяет весь список прав** указанных
администраторов; клиент не объединяет его со старыми правами. Боту необходимо право
`add_admins`. `remove_chat_admin` вызывает
`DELETE /chats/{chatId}/members/admins/{userId}` и снимает права, не исключая участника.
Ответы `success: false` возвращаются без изменения; HTTP 200 сам по себе не означает успех операции.

Raw-эквиваленты: `api.raw.chats.set_chat_admins(chat_id:, admins:, marker: nil)` и
`api.raw.chats.remove_chat_admin(chat_id:, user_id:)`.

Источники: [Назначение администраторов](https://dev.max.ru/docs-api/methods/POST/chats/-chatId-/members/admins),
[снятие прав](https://dev.max.ru/docs-api/methods/DELETE/chats/-chatId-/members/admins/-userId-).

### Устаревшие методы и миграция

| Метод Ruby | Поведение и замена |
| --- | --- |
| `get_all_chats` / `raw.chats.get_all` | `GET /chats` снят с поддержки с июня 2026. Локальный `MaxApiClient::UnsupportedEndpointError`, без HTTP-запроса. Сохраняйте `chat_id` из Webhook-событий и поддерживайте собственный список чатов. |
| `get_chat_by_link` / `raw.chats.get_by_link` | Поиск по ссылке не предусмотрен документированным endpoint с числовым `chatId`. Локальный `UnsupportedEndpointError`. Используйте `get_chat(chat_id)`. |
| `add_chat_members` / `raw.chats.add_chat_members` | Метод ограничен с 9 сентября 2026; удаление назначено на **30 сентября 2026**. Каждый вызов предупреждает в stderr, затем отправляет прежний запрос. Не закладывайтесь на доступность метода. |

Для добавления участников клиент не вводит автоматического переключения по системной
дате: сервер определяет доступность ограниченного endpoint. Документация не обещает
готовой API-замены. `UnsupportedEndpointError` наследует `MaxApiClient::Error`.
Общий транспорт `api.raw.get/post/put/patch/delete` остаётся доступен для явных запросов;
это не гарантия поддержки устаревших маршрутов сервером.

Источники: [GET /chats](https://dev.max.ru/docs-api/methods/GET/chats),
[числовой chatId](https://dev.max.ru/docs-api/methods/GET/chats/-chatId-),
[добавление участников](https://dev.max.ru/docs-api/methods/POST/chats/-chatId-/members).

## Сообщения и видео

```ruby
api.send_message_to_chat(-123, "Привет", format: "markdown", notify: false)
api.send_message_to_user(42, "Привет", disable_link_preview: false)
api.get_messages(-123, count: 25)
api.get_messages(message_ids: %w[mid.first mid.second])
api.get_message("mid.first")
api.edit_message("mid.first", text: "Обновлено")
api.delete_message("mid.first")
api.answer_on_callback("callback-id", notification: "Готово")

video = api.get_video("video-token")
# Raw: api.raw.videos.get_by_token(video_token: "video-token")
```

`get_video` вызывает `GET /videos/{videoToken}` и возвращает полный объект: токен,
URL воспроизведения, миниатюру, размеры и длительность. `urls` и `thumbnail` могут
быть `nil`; клиент сохраняет это значение. Это получение метаданных, не загрузка файла.

`send_message_to_chat` и `send_message_to_user` возвращают вложенный объект `message`;
raw-методы — полный ответ API. Поддерживаются reply/forward, вложения и форматирование.
Существующий повтор отправки при `attachment.not.ready` сохранён; политика повторов
в этом изменении не пересматривалась.

Источник: [Информация о видео](https://dev.max.ru/docs-api/methods/GET/videos/-videoToken-).

## Комментарии к постам каналов

```ruby
api.get_comments("mid.post", after: 0, before: 1_800_000_000_000, count: 50)
api.get_comments("mid.post", comment_ids: %w[mid.first mid.second])
api.get_comment("mid.post", "mid.comment")
comment = api.send_comment("mid.post", "Комментарий", format: "markdown")
api.send_comment("mid.post", "Ответ", link: { type: "reply", mid: "mid.comment" })
api.edit_comment("mid.post", "mid.comment", text: "Исправленный комментарий")
api.delete_comment("mid.post", "mid.comment")
```

| Высокоуровневый метод | Raw-метод | HTTP |
| --- | --- | --- |
| `get_comments(message_id, **query)` | `raw.comments.get(message_id:, **query)` | `GET /messages/{messageId}/comments` |
| `get_comment(message_id, comment_id)` | `raw.comments.get_by_id(message_id:, comment_id:)` | `GET /messages/{messageId}/comments/{commentId}` |
| `send_comment(message_id, text, link: nil, format: nil)` | `raw.comments.send(message_id:, text:, link: nil, format: nil)` | `POST /messages/{messageId}/comments` |
| `edit_comment(message_id, comment_id, text:, link: nil, format: nil)` | `raw.comments.edit(message_id:, comment_id:, text:, link: nil, format: nil)` | `PUT /messages/{messageId}/comments?comment_id=...` |
| `delete_comment(message_id, comment_id)` | `raw.comments.delete(message_id:, comment_id:)` | `DELETE /messages/{messageId}/comments?comment_id=...` |

Фильтры списка: `comment_ids` (массив или CSV), `after`, `before`, `count` (1–100).
При `comment_ids` сервер игнорирует пагинацию. Клиент возвращает ответ списка целиком,
без собственной автоматической пагинации. `send_comment` извлекает объект `message`,
как отправка обычного сообщения; raw-отправка сохраняет оболочку `{ message: ... }`.
Получение одного комментария возвращает сам комментарий, изменение и удаление — результат операции.

Тело `NewCommentBody` содержит только `text`, `link`, `format`. Текст допускает `nil`
и ограничен API 4000 символами. Формат — `markdown` или `html`; гиперссылки и упоминания
пользователей в тексте комментариев не поддерживаются. Неизвестные параметры, в том числе
`attachments` и `notify`, вызывают `ArgumentError`; для `link` принимается только `reply`
(строковые и символьные ключи хэша поддерживаются). `forward` отклоняется до HTTP-запроса.
Ограничения длины текста, формата и права доступа проверяет сервер.

Для чтения нужны соответствующие права в канале, для отправки — включённые комментарии
и права `read_all_messages` + `write`. Ошибки HTTP передаются как `MaxApiClient::ApiError`.

Источники: [список](https://dev.max.ru/docs-api/methods/GET/messages/-messageId-/comments),
[получение одного](https://dev.max.ru/docs-api/methods/GET/messages/-messageId-/comments/-commentId-),
[отправка](https://dev.max.ru/docs-api/methods/POST/messages/-messageId-/comments),
[редактирование](https://dev.max.ru/docs-api/methods/PUT/messages/-messageId-/comments),
[удаление](https://dev.max.ru/docs-api/methods/DELETE/messages/-messageId-/comments),
[NewCommentBody](https://dev.max.ru/docs-api/objects/NewCommentBody).

## Подписки и Long Polling

```ruby
api.get_subscriptions
api.subscribe("https://example.com/webhook", update_types: %w[message_created bot_started], secret: "webhook-secret")
api.unsubscribe("https://example.com/webhook")

# Разработка и тесты; не запускайте одновременно с Webhook.
api.poll_updates(%w[message_created], timeout: 20).each do |update|
  puts update["update_type"]
end
```

Для production используйте Webhook. Long Polling предназначен прежде всего для
разработки и тестов. `poll_updates(types = [], marker: nil, timeout: 20,
retry_interval: 5, read_timeout: nil)` передаёт marker между запросами, добавляет запас
к read timeout и повторяет запрос при временных сетевых ошибках, 429 и 5xx.
Без блока возвращается `Enumerator`, а не объект со `stop`.
Для явной остановки создайте `MaxApiClient::Polling.new(api, types: [...])` и вызывайте
`poller.stop` из обработчика `poller.each`.

## Загрузка медиа и вложения

```ruby
image = api.upload_image(url: "https://example.com/image.png")
api.send_message_to_chat(-123, "Фото", attachments: [image.to_h])
file = api.upload_file(source: "/tmp/report.txt", timeout: 20)
```

`upload_image`, `upload_video`, `upload_audio`, `upload_file` принимают хэш опций:
`source` (путь или читаемый IO), необязательные `filename` и `timeout`.
Только изображение поддерживает внешний `url` вместо загрузки.
Связанный HTTP-метод получения адреса загрузки — `POST /uploads?type=...`.

Результаты — `ImageAttachment`, `VideoAttachment`, `AudioAttachment`, `FileAttachment`.
Дополнительно доступны `StickerAttachment`, `LocationAttachment`, `ShareAttachment`.
Используйте `to_h` при формировании массива вложений. Для ответов загрузки поддерживаются
строковые ключи JSON и символьные ключи адаптера.

## Raw API, ошибки и логирование

Группы: `api.raw.bots`, `chats`, `messages`, `videos`, `comments`, `subscriptions`, `uploads`.
Также доступны универсальные `api.raw.get/post/put/patch/delete` с путём и параметрами.
В query массивы сериализуются как CSV, `false` и `0` сохраняются, `nil` пропускается.

Неуспешный HTTP-ответ вызывает `MaxApiClient::ApiError` с `status`, `code`, `description`
и `response`. Для ответов HTTP 200 с `success: false` проверяйте тело результата сами.

```ruby
require "logger"
MaxApiClient.logger = Logger.new($stdout)
# Или Api.new(..., logger: Logger.new($stdout))
```

Логгер пишет запросы и ответы на уровне debug, заголовок Authorization маскируется.
Не публикуйте debug-логи: тела запросов и ответов могут содержать пользовательские данные.

## Разработка

```bash
git clone https://github.com/max-hackaton/max_api_client.git
cd max_api_client
bundle install
bundle exec rake test
bundle exec rake
bin/console
```

Без Bundler, когда Minitest уже установлен:

```bash
ruby -Ilib:test -e 'Dir["test/test_*.rb"].sort.each { |file| require_relative file }'
```

Тесты используют адаптер и построение Net::HTTP-запросов; настоящий токен не нужен.
Полный `rake` дополнительно запускает настроенные проверки проекта.

## Релиз

Публикация идёт через GitHub Releases и GitHub Actions. Перед релизом обновите
`lib/max_api_client/version.rb`, перенесите Unreleased в версионный раздел `CHANGELOG.md`
и после ревью включите изменения в `master`. Этот PR не меняет версию gem и не публикует релиз.

## Источники и лицензия

[Документация MAX](https://dev.max.ru/docs-api),
[TypeScript reference client](https://github.com/max-messenger/max-bot-api-client-ts).
MIT, см. [LICENSE.txt](./LICENSE.txt).
