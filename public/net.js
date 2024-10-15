import { h, render, Component, createRef } from "https://esm.sh/preact@10.20.2"
import htm from "https://esm.sh/htm@3.1.1"
import dayjs from "https://esm.sh/dayjs@1.11.11"
import relativeTime from "https://esm.sh/dayjs@1.11.11/plugin/relativeTime"
import utc from "https://esm.sh/dayjs@1.11.11/plugin/utc"
import Pusher from "https://esm.sh/pusher-js@8.4.0-rc2"
import Toastify from "https://esm.sh/toastify-js@1.12.0"

dayjs.extend(relativeTime)
dayjs.extend(utc)
const html = htm.bind(h)

let intervalWithBackoffNextId = 0
const intervalWithBackoffIntervals = {}

function setIntervalWithBackoff(func, delay, backoff, max) {
  const id = ++intervalWithBackoffNextId
  intervalWithBackoffIntervals[id] = true
  const startTime = new Date()
  const runFuncAndScheduleNext = () => {
    if (!intervalWithBackoffIntervals[id]) return
    func()
    delay += backoff
    if (new Date() - startTime < max) {
      console.log(`waiting ${delay} till next update`)
      setTimeout(runFuncAndScheduleNext, delay)
    } else {
      console.log(`stopped updating after ${max}`)
    }
  }
  setTimeout(runFuncAndScheduleNext, delay)
  return id
}

function clearIntervalWithBackoff(id) {
  delete intervalWithBackoffIntervals[id]
}

const BLANK_EDITING_ENTRY = {
  num: null,
  call_sign: "",
  preferred_name: "",
  remarks: "",
  notes: "",
}

class Net extends Component {
  state = {
    checkins: [],
    coords: [],
    messages: [],
    messagesCount: 0,
    monitors: [],
    favorites: [],
    lastUpdatedAt: null,
    editing: { ...BLANK_EDITING_ENTRY },
    info: null,
    error: null,
    lastUpdatedAt: null,
    monitoringThisNet: this.props.monitoringThisNet,
    reverseMessages: localStorage.getItem("reverseMessages") === "true",
  }

  formRef = createRef()

  componentDidMount() {
    this.updateData(true)
    this.startUpdatingRegularly()
    const pusher = new Pusher(this.props.pusher.key, {
      channelAuthorization: {
        endpoint: this.props.pusher.authEndpoint,
      },
      cluster: this.props.pusher.cluster,
    })
    const channel = pusher.subscribe(this.props.pusher.channel)
    channel.bind("net-updated", ({ updatedAt, changes }) => {
      if (this.state.fetchInFlight) return
      if (updatedAt === this.state.lastUpdatedAt) return

      console.log(`Channel indicates net needs update (changes: ${changes}).`)
      this.updateData()

      // resync the update interval
      clearIntervalWithBackoff(window.updateInterval)
      this.startUpdatingRegularly()
    })
    channel.bind("message", ({ message }) => {
      console.log({ message, userCallSign: this.props.userCallSign })
      const hidden =
        message.blocked && message.call_sign !== this.props.userCallSign
      if (this.state.monitoringThisNet && !hidden) {
        this.showMessageNotification(message)
        this.setState({ messages: [...this.state.messages, message] })
      }
    })
  }

  startUpdatingRegularly() {
    const minute = 60 * 1000
    const hour = 60 * minute
    window.updateInterval = setIntervalWithBackoff(
      this.updateData.bind(this),
      this.props.updateInterval * 1000,
      0,
      3 * hour
    )
  }

  async updateData(initialLoad = false) {
    try {
      if (this.state.fetchInFlight) return
      this.setState({ fetchInFlight: true })
      const response = await fetch(`/net/${this.props.netId}/details`)
      this.setState({ fetchInFlight: false })

      if (response.status !== 200) {
        location.reload() // show closed-net page or redirect
      } else {
        const data = await response.json()
        if (!initialLoad) this.showNotifications(data)
        this.setState(data)
      }
    } catch (error) {
      console.error(`Error updating data: ${error}`)
    }
  }

  showNotifications({ checkins, messages }) {
    const existingCallSigns = this.state.checkins
      .map((c) => c.call_sign)
      .filter((c) => present(c))

    const updatedCallSigns = checkins
      .map((c) => c.call_sign)
      .filter((c) => present(c))

    const newCallSigns = updatedCallSigns.filter(
      (c) => !existingCallSigns.includes(c)
    )

    if (newCallSigns.length > 0) {
      newCallSigns.forEach((callSign) => {
        if (present(callSign)) {
          Toastify({
            text: `${callSign} checked in`,
            duration: 3000,
            style: {
              background: "#f93",
            },
          }).showToast()
        }
      })
    }

    if (messages.length > this.state.messages.length) {
      const newMessages = messages.slice(this.state.messages.length)
      newMessages.forEach(this.showMessageNotification.bind(this))
    }
  }

  showMessageNotification(message) {
    let text = message.message
    if (text.length > 50) text = `${text.substring(0, 50)}...`
    Toastify({
      text: `${message.call_sign}: ${text}`,
      duration: 3000,
      style: {
        background: "#39f",
      },
    }).showToast()
  }

  render() {
    return html`
      <header class="flex">
        <div class="header-col-grow">
          ${this.renderClubBreadcrumbs()}

          <h1>${this.props.net.name}</h1>

          ${this.renderNetControls()} ${this.renderNetDetails()}
        </div>

        <div class="header-col">
          <a href=${this.props.clubUrl}>
            <img class="club-logo" src=${this.props.clubLogo} />
          </a>
        </div>
      </header>

      <${Map} coords=${this.state.coords} />

      <p class="timestamps">
        Current time: <${CurrentTime} /> (Last updated${" "}
        ${formatTimeWithDayjs(this.state.lastUpdatedAt, true)})
      </p>

      <h2>Log</h2>

      <${Checkins}
        netId=${this.props.netId}
        checkins=${this.state.checkins}
        favorites=${this.state.favorites}
        onEditEntry=${this.handleEditEntry.bind(this)}
        removeCheckinFromMemory=${this.removeCheckinFromMemory.bind(this)}
        highlightCheckinInMemory=${this.highlightCheckinInMemory.bind(this)}
        isLogger=${this.props.isLogger}
      />

      ${this.props.isLogger &&
      h(LogForm, {
        ...this.state.editing,
        ref: this.formRef,
        netId: this.props.netId,
        nextNum: this.nextNum(),
        info: this.state.info,
        error: this.state.error,
        onCallSignInput: this.handleCallSignInput.bind(this),
        onPreferredNameInput: this.handleEditingValueInput.bind(
          this,
          "preferred_name"
        ),
        onNotesInput: this.handleEditingValueInput.bind(this, "notes"),
        onRemarksInput: this.handleEditingValueInput.bind(this, "remarks"),
        onSubmit: this.handleLogFormSubmit.bind(this),
        onClear: this.handleLogFormClear.bind(this),
      })}

      <div class="h2-with-controls">
        <h2>Messages</h2>
        ${this.state.monitoringThisNet &&
        html`<label>
          <input
            type="checkbox"
            id="reverse-messages"
            checked=${this.state.reverseMessages}
            onClick=${this.handleReverseMessagesToggle.bind(this)}
          />
          Reverse messages
        </label>`}
      </div>

      <${Messages}
        messages=${this.state.messages}
        monitoringThisNet=${this.state.monitoringThisNet}
        messagesCount=${this.state.messagesCount}
        netId=${this.props.netId}
        userCallSign=${this.props.userCallSign}
        isLogger=${this.props.isLogger}
        reverseMessages=${this.state.reverseMessages}
        onToggleMonitorNet=${this.handleToggleMonitorNet.bind(this)}
      />

      <h2>Monitors</h2>

      <${Monitors} monitors=${this.state.monitors} />
    `
  }

  renderClubBreadcrumbs() {
    if (!this.props.club) return ""
    if (!this.props.club.about_url) return ""

    let name = this.props.club.full_name
    if (!name) name = this.props.club.name

    return html`
      <div class="net-breadcrumbs">
        <a href=${this.props.clubUrl}>${name}</a>
      </div>
    `
  }

  renderNetControls() {
    if (this.state.closingNet) {
      return html`closing net...`
    }

    if (this.props.isLogger) {
      return html`
        <div>
          <button
            onClick=${() => {
              location.href = `/net/${this.props.netId}/log`
            }}
          >
            Download log</button
          >${" "}
          <button
            onClick=${() => {
              if (confirm("Are you sure you want to CLOSE this net?")) {
                this.setState({ closingNet: true })
                fetch(`/close-net/${this.props.netId}`, {
                  method: "POST",
                }).then((response) => {
                  if (response.ok) location.href = "/"
                  else response.text().then((text) => alert(text))
                })
              }
            }}
          >
            Close net!</button
          >${" "}
          <button
            onClick=${() => {
              if (
                confirm(
                  "Wait! Only use this button if someone else is taking over logging for the net. (If you are the only logger for this net, then you should 'Close net' when you are done.)"
                )
              ) {
                fetch(`/stop-logging/${this.props.netId}`, {
                  method: "POST",
                }).then((response) => {
                  if (response.ok) location.reload()
                  else response.text().then((text) => alert(text))
                })
              }
            }}
          >
            Stop logging
          </button>
        </div>
      `
    }

    if (
      !this.props.isLogger &&
      this.props.canLogForClub &&
      this.state.wantsToLogThisNet
    ) {
      return html`
        <form
          action="/start-logging/${this.props.netId}"
          method="POST"
          class="inline"
        >
          <input
            type="password"
            name="net_password"
            placeholder="password"
            required
            maxlength="20"
          />
          <input type="submit" value="Start logging" />
          <br />
          <span
            class="linkish"
            onClick=${() => this.setState({ wantsToLogThisNet: false })}
            >cancel</span
          >
        </form>
      `
    }

    return ""
  }

  renderNetDetails() {
    return html`
      <p>
        ${[
          this.props.net.frequency,
          this.props.net.mode,
          this.props.net.band,
          `started at ${formatTimeWithDayjs(this.props.net.started_at)}`,
          this.props.net.host,
        ].join(" | ")}
        ${!this.props.isLogger &&
        this.props.canLogForClub &&
        !this.state.wantsToLogThisNet &&
        html`${" "}|${" "}
          <span
            class="linkish"
            onClick=${() => this.setState({ wantsToLogThisNet: true })}
            >start logging</span
          >`}
      </p>
    `
  }

  nextNum() {
    const checkins = this.state.checkins.filter(
      (checkin) =>
        present(checkin.call_sign) ||
        present(checkin.remarks) ||
        present(checkin.notes)
    )
    return Math.max(...checkins.map((checkin) => checkin.num), 0) + 1
  }

  handleReverseMessagesToggle() {
    const newValue = !this.state.reverseMessages
    this.setState({ reverseMessages: newValue })
    localStorage.setItem("reverseMessages", newValue.toString())
  }

  handleCallSignInput(call_sign) {
    this.setState({
      editing: { ...this.state.editing, call_sign },
    })
    if (window.inputTimeout) clearTimeout(window.inputTimeout)
    window.inputTimeout = setTimeout(async () => {
      if (this.state.editing.call_sign.length >= 4) {
        this.fetchStationInfo()
      } else {
        this.clearStationInfo()
      }
    }, 800)
  }

  async handleToggleMonitorNet() {
    await this.updateData()
  }

  async clearStationInfo(info = null) {
    await this.setState({
      info,
      editing: { ...this.state.editing, preferred_name: "", notes: "" },
    })
  }

  async fetchStationInfo() {
    try {
      const response = await fetch(
        `/station/${encodeURIComponent(this.state.editing.call_sign)}?${
          this.props.club ? `club_id=${this.props.club.id}` : ""
        }`
      )
      if (response.status === 200) {
        const existingCheckins = this.state.checkins.filter(
          (c) =>
            c.call_sign.toUpperCase() ===
            this.state.editing.call_sign.toUpperCase()
        )

        const info = await response.json()
        await this.setState({
          info: {
            ...info,
            existingCheckins,
          },
          editing: {
            ...this.state.editing,
            preferred_name:
              presence(info.preferred_name) || info.first_name.split(/\s+/)[0],
            notes: presence(info.notes) || "",
          },
        })
      } else if (response.status === 404) {
        await this.clearStationInfo(false)
      } else {
        await this.clearStationInfo(null)
        console.error(`Error fetching station: ${error}`)
      }
    } catch (error) {
      await this.clearStationInfo(null)
      console.error(`Error fetching station: ${error}`)
    }
  }

  handleEditingValueInput(prop, value) {
    this.setState({ editing: { ...this.state.editing, [prop]: value } })
  }

  async handleLogFormSubmit() {
    if (window.inputTimeout) clearTimeout(window.inputTimeout)

    const { call_sign, remarks } = this.state.editing
    if (!present(call_sign) && !present(remarks)) return

    this.setState({ submitting: true, error: null })

    if (!this.state.info) await this.fetchStationInfo()
    const info = this.state.info

    const name = [info.first_name, info.last_name].filter((n) => n).join(" ")

    const payload = {
      ...info,
      id: this.props.netId,
      num: this.state.editing.num,
      preferred_name: this.state.editing.preferred_name,
      remarks: this.state.editing.remarks,
      notes: this.state.editing.notes,
      name: name,
      checked_in_at: dayjs().format(),
    }
    if (!info.call_sign) payload.call_sign = this.state.editing.call_sign

    this.addOrUpdateCheckinInMemory(payload)
    try {
      const response = await fetch(
        `/log/${this.props.netId}/${
          this.state.editing.num ? this.state.editing.num : "new" // a little sloppy to pass "new" here, but it works: the :num is overwritten by the payload anyway.
        }`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
          body: JSON.stringify(payload),
        }
      )
      if (response.status === 200) {
        this.handleLogFormClear()
        return true
      } else {
        console.error(`response status was ${response.status}`)
        try {
          const data = await response.json()
          this.setState({
            error: `There was an error: ${JSON.stringify(data)}`,
          })
        } catch (_) {
          this.setState({
            error: `There was an unknown error (${response.status})`,
          })
        }
        this.removeCheckinFromMemory(this.props.num)
        return false
      }
    } catch (error) {
      console.error(error)
      this.setState({ error: `There was an error: ${error}` })
      this.removeCheckinFromMemory(this.props.num)
      return false
    }
  }

  handleLogFormClear() {
    this.setState({
      editing: { ...BLANK_EDITING_ENTRY },
      info: null,
    })
  }

  handleEditEntry(num) {
    const entry = this.state.checkins.find((c) => c.num === num)
    this.setState({ editing: entry })
    this.formRef.current.focus()
  }

  addOrUpdateCheckinInMemory(entry) {
    const index = this.state.checkins.findIndex((c) => c.num === entry.num)
    if (!entry.num || index === -1) {
      entry.num = this.nextNum()
      this.setState({ checkins: [...this.state.checkins, entry] })
    } else {
      const checkins = [...this.state.checkins]
      checkins[index] = entry
      this.setState({ checkins })
    }
  }

  removeCheckinFromMemory(num) {
    const index = this.state.checkins.findIndex((c) => c.num === num)

    if (this.state.checkins.length <= 1) {
      this.setState({ checkins: [] })
      return
    }

    const checkins = [
      ...this.state.checkins.slice(0, index),
      ...this.state.checkins
        .slice(index + 1)
        .map((checkin) => ({ ...checkin, num: checkin.num - 1 })),
    ]
    this.setState({ checkins })
  }

  highlightCheckinInMemory(num) {
    const checkins = this.state.checkins.map((checkin) => ({
      ...checkin,
      currently_operating: checkin.num === num,
    }))
    this.setState({ checkins })
  }
}

class Map extends Component {
  componentDidMount() {
    buildNetMap()
    updateNetMapCoords(this.props.coords)
  }

  componentDidUpdate() {
    maybeUpdateNetMapCoords(this.props.coords)
  }

  render() {
    return html`<div id="net-map"></div>`
  }
}

class Checkins extends Component {
  render() {
    if (this.props.checkins.length === 0)
      return html`<p><em>no check-ins yet</em></p>`

    return html`
      <div class="table-wrapper">
        <table id="checkins-table">
          <thead>
            <tr>
              <th>Num</th>
              <th>Image</th>
              <th>Call Sign</th>
              <th>Name</th>
              <th>Time</th>
              <th>Grid Square</th>
              <th>Status</th>
              <th>City</th>
              <th>County</th>
              <th>State</th>
              <th>Country</th>
            </tr>
          </thead>
          <tbody>
            ${this.props.checkins.map((checkin, index) =>
              h(CheckinRow, {
                ...checkin,
                index,
                netId: this.props.netId,
                favorited: this.props.favorites.indexOf(checkin.call_sign) > -1,
                onEditEntry: this.props.onEditEntry,
                removeCheckinFromMemory: this.props.removeCheckinFromMemory,
                highlightCheckinInMemory: this.props.highlightCheckinInMemory,
                isLogger: this.props.isLogger,
              })
            )}
          </tbody>
        </table>
      </div>
    `
  }
}

class CheckinRow extends Component {
  state = {
    editing: false,
    deleting: false,
    deletingTimeout: null,
  }

  async handleEdit(e) {
    e.preventDefault()
    this.props.onEditEntry(this.props.num)
  }

  async handleDelete(e) {
    e.preventDefault()
    if (this.state.deleting) {
      clearTimeout(this.state.deletingTimeout)
      const response = await fetch(
        `/log/${this.props.netId}/${this.props.num}`,
        {
          method: "DELETE",
          headers: {
            "X-Requested-With": "XMLHttpRequest",
          },
        }
      )
      if (response.status === 200) {
        this.props.removeCheckinFromMemory(this.props.num)
      }
      this.setState({ deleting: false, deletingTimeout: null })
    } else {
      const deletingTimeout = setTimeout(() => {
        this.setState({ deleting: false, deletingTimeout: null })
      }, 3000)
      this.setState({ deleting: true, deletingTimeout })
    }
  }

  async handleHighlight(e) {
    e.preventDefault()
    const response = await fetch(
      `/highlight/${this.props.netId}/${this.props.num}`,
      {
        method: "PATCH",
        headers: {
          "X-Requested-With": "XMLHttpRequest",
        },
      }
    )
    if (response.status === 200) {
      this.props.highlightCheckinInMemory(this.props.num)
    } else {
      console.error(`Error highlighting entry: ${response.status}`)
    }
  }

  render() {
    return [this.renderDetails(), this.renderRemarksAndNotes()]
  }

  renderDetails() {
    if (!present(this.props.call_sign)) return null

    return html`<tr class="details ${this.rowClass()}">
      <td>${this.props.num} ${this.renderLoggerControls()}</td>
      <td class="avatar-cell">
        <a
          href="/station/${encodeURIComponent(this.props.call_sign)}/image"
          style="text-decoration:none"
        >
          <${Avatar} ...${this.props} />
        </a>
      </td>
      <td>
        <${Favorite}
          callSign=${this.props.call_sign}
          favorited=${this.props.favorited}
        />${" "}
        <a
          href="https://www.qrz.com/db/${encodeURIComponent(
            this.props.call_sign
          )}"
        >
          ${this.props.call_sign}
        </a>
      </td>
      <td>${stationName(this.props)}</td>
      <td>${formatTimeWithDayjs(this.props.checked_in_at, true)}</td>
      <td>${this.props.grid_square}</td>
      <td>${this.props.status}</td>
      <td>${this.props.city}</td>
      <td>${this.props.county}</td>
      <td>${this.props.state}</td>
      <td>${this.props.country}</td>
    </tr>`
  }

  renderRemarksAndNotes() {
    if (!present(this.props.remarks) && !present(this.props.notes)) return null

    return html`
      <tr class="remarks ${this.rowClass()}">
        ${present(this.props.call_sign)
          ? html`<td></td>`
          : html`<td>${this.props.num} ${this.renderLoggerControls()}</td>`}
        <td></td>
        <td colspan="9" class="can-wrap">
          ${this.props.remarks}
          ${present(this.props.remarks) &&
          present(this.props.notes) &&
          html`<br />`}
          ${this.props.notes &&
          html`<em>Station Notes: ${this.props.notes}</em>`}
        </td>
      </tr>
    `
  }

  renderLoggerControls() {
    if (!this.props.isLogger) return null

    return html`
      <button class="logger-control" onclick=${this.handleEdit.bind(this)}>
        <span class="material-symbols-outlined">edit</span>
      </button>
      ${" "}
      <button
        onclick=${this.handleDelete.bind(this)}
        class=${`logger-control ${this.state.deleting && "danger"}`}
      >
        <span class="material-symbols-outlined">delete</span>
        ${this.state.deleting && " (click again to delete)"}
      </button>
      ${" "}
      <button class="logger-control" onclick=${this.handleHighlight.bind(this)}>
        <span class="material-symbols-outlined">highlight</span>
      </button>
    `
  }

  rowClass() {
    let classes = [this.props.index % 2 == 0 ? "even" : "odd"]
    if (this.props.currently_operating) classes.push("currently-operating")
    if (new String(this.props.status).indexOf("(c/o)") > -1)
      classes.push("checked-out")
    return classes.join(" ")
  }
}

class Avatar extends Component {
  state = { error: false }
  render() {
    if (this.state.error) return null

    return html`
      <img
        src="/station/${encodeURIComponent(this.props.call_sign)}/image"
        style="max-height:40px;max-width:40px"
        onerror="${() => this.setState({ error: true })}"
      />
    `
  }
}

class Favorite extends Component {
  state = {
    favorited: this.props.favorited,
  }

  handleClick() {
    favorite(this.props.callSign, null, this.state.favorited)
    this.setState({ favorited: !this.state.favorited })
  }

  render() {
    if (!present(this.props.callSign)) return null

    return html`
      <img
        src="/images/${this.state.favorited
          ? "star-solid.svg"
          : "star-outline.svg"}"
        class="favorite-star"
        onclick="${(e) => this.handleClick(e)}"
      />
    `
  }
}

class Messages extends Component {
  state = {
    messageInput: "",
    sendingMessage: null,
    messageCountBeforeSend: 0,
    error: null,
  }

  componentDidUpdate() {
    if (
      this.state.sendingMessage &&
      this.props.messages.length != this.state.messageCountBeforeSend
    )
      this.setState({ sendingMessage: null })
  }

  render() {
    if (this.state.loading) return html`<p><em>loading...</em></p>`

    if (!this.props.monitoringThisNet)
      return html`
        <p>
          <em>
            ${this.props.messagesCount}${" "}
            ${pluralize("message", this.props.messagesCount)}. </em
          >${" "} Click below to participate.<br />
          <button onClick=${this.handleMonitorNet.bind(this)}>
            Monitor this Net
          </button>
        </p>
      `

    return this.props.reverseMessages
      ? [this.renderForm(), this.renderLog(), this.renderStopMonitoringForm()]
      : [this.renderLog(), this.renderForm(), this.renderStopMonitoringForm()]
  }

  renderMessage(message, index) {
    const timestamp = formatTimeWithDayjs(message.sent_at, true)
    return html`<div
      class="chat-message ${index % 2 == 0 ? "chat-even" : "chat-odd"}"
    >
      <span
        class="chat-sender"
        style="color: ${getUniqueColor(message.call_sign)}"
      >
        ${message.call_sign} - ${message.name}
      </span>
      ${" "}
      <span class="chat-timestamp">${timestamp}</span>
      <br />
      <span
        class="chat-message-text"
        dangerouslySetInnerHTML=${{ __html: this.formatText(message.message) }}
      />
    </div>`
  }

  formatText(text) {
    const sanitized = text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")

    let formatted = sanitized.replace(
      /https?:\/\/[^\s,;()'"<>[\]{}]+(?=\s|$|[.,;!?)])?/gi,
      (url) => {
        return `<a href="${url}" target="_blank">${url}</a>`
      }
    )
    let formattedNext
    for (;;) {
      formattedNext = formatted
        .replace(/\[(p|b|u)\]([^\[]*)\[\/\1\]/, "<$1>$2</$1>")
        .replace(
          /\[big\]([^\[]*)\[\/big\]/,
          "<span style='font-size:larger'>$1</span>"
        )
      if (formattedNext === formatted) break
      formatted = formattedNext
    }
    return formatted
  }

  renderLog() {
    if (this.props.messages.length === 0)
      return html`<p><em>no messages yet</em></p>`

    const messages = this.props.reverseMessages
      ? [...this.props.messages].reverse()
      : this.props.messages

    return html`
      <div class="blue-screen">
        ${messages.map((message, index) => this.renderMessage(message, index))}
        ${this.state.sendingMessage &&
        this.renderMessage(
          {
            message: this.state.sendingMessage,
            call_sign: this.props.userCallSign,
            name: "sending...",
            sent_at: new Date(),
          },
          this.props.messages.length
        )}
      </div>
    `
  }

  handleMonitorNet() {
    this.setState({ loading: true })
    fetch(`/monitor/${this.props.netId}`, { method: "POST" })
      .then((response) => response.json())
      .then(async (data) => {
        if (data.ok) {
          await this.props.onToggleMonitorNet()
          this.setState({ loading: false })
        } else if (data.status === 404) {
          location.reload()
        } else {
          alert("Error monitoring net")
          this.setState({ loading: false })
        }
      })
  }

  handleUnmonitorNet() {
    this.setState({ loading: true })
    fetch(`/unmonitor/${this.props.netId}`, { method: "POST" })
      .then((response) => response.json())
      .then(async (data) => {
        if (data.ok) {
          await this.props.onToggleMonitorNet()
          this.setState({ loading: false })
        } else if (data.status === 404) {
          location.reload()
        } else {
          alert("Error unmonitoring net")
          this.setState({ loading: false })
        }
      })
  }

  async handleSubmit(e) {
    e.preventDefault()
    this.setState({
      sendingMessage: this.state.messageInput,
      messageCountBeforeSend: this.props.messagesCount,
      messageInput: "",
    })
    try {
      const response = await fetch(`/message/${this.props.netId}`, {
        method: "POST",
        headers: {
          "Content-Type":
            "application/x-www-form-urlencoded;charset=ISO-8859-1",
          "X-Requested-With": "XMLHttpRequest",
        },
        body: "message=" + encodeURIComponent(this.state.messageInput),
      })
      if (response.ok) {
        this.setState({ error: null })
      } else {
        const body = await response.text()
        let error
        try {
          error = JSON.parse(body)
          if (error.error) error = error.error
        } catch (_) {
          error = body
        }
        this.setState({ error, sendingMessage: null })
      }
    } catch (error) {
      console.error(error)
      this.setState({ error })
    }
  }

  renderForm() {
    return html`
      ${this.state.error && html`<p class="error">${this.state.error}</p>`}
      <form onsubmit=${(e) => this.handleSubmit(e)}>
        <input
          oninput=${(e) => this.setState({ messageInput: e.target.value })}
          value=${this.state.messageInput}
          type="text"
          name="message"
          placeholder="type your message"
          style="width:calc(100% - 100px)"
        />
        <input type="submit" value="Send" />
      </form>
    `
  }

  renderStopMonitoringForm() {
    if (this.props.isLogger) return null

    return html`
      <div>
        <button onclick=${this.handleUnmonitorNet.bind(this)}>
          Stop monitoring this Net
        </button>
      </div>
    `
  }
}

class Monitors extends Component {
  render() {
    return html`
      <div class="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Call Sign</th>
              <th>Name</th>
              <th>Version</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            ${this.props.monitors.map(
              (monitor) =>
                html`<tr>
                  <td>${monitor.call_sign}</td>
                  <td>${monitor.name}</td>
                  <td>${monitor.version}</td>
                  <td>
                    <span class=${monitor.status}>${monitor.status}</span>
                  </td>
                </tr>`
            )}
          </tbody>
        </table>
      </div>
    `
  }
}

class LogForm extends Component {
  inputRef = createRef()

  focus() {
    this.inputRef.current.focus()
  }

  render() {
    return html`
      ${this.renderHeader()}
      <form
        onsubmit=${async (e) => {
          e.preventDefault()
          const success = await this.props.onSubmit(e)
          if (success) this.focus()
        }}
        class="log-form"
      >
        <div class="columns">
          <div class="column">
            <label>
              Call Sign:<br />
              <input
                ref=${this.inputRef}
                name="call_sign"
                value=${this.props.call_sign}
                oninput=${(e) => this.props.onCallSignInput(e.target.value)}
                autocomplete="off"
                autofocus
              />
            </label>
            <label>
              Preferred Name:<br />
              <input
                name="preferred_name"
                value=${this.props.preferred_name}
                oninput=${(e) =>
                  this.props.onPreferredNameInput(e.target.value)}
                autocomplete="off"
                autofocus
              />
            </label>
          </div>
          <div class="column">
            <label>
              Remarks (saved to this net only):<br />
              <input
                name="remarks"
                value=${this.props.remarks}
                oninput=${(e) => this.props.onRemarksInput(e.target.value)}
                autocomplete="off"
              />
            </label>
            <label>
              Station Notes (saved for next time):<br />
              <input
                name="notes"
                value=${this.props.notes}
                oninput=${(e) => this.props.onNotesInput(e.target.value)}
                autocomplete="off"
              />
            </label>
          </div>
        </div>
        <div>
          <input type="submit" value=${this.props.num ? "Update" : "Add"} />
        </div>
        <div class="log-form-info">
          ${this.renderInfo()} ${this.renderClear()}
        </div>
      </form>
    `
  }

  renderHeader() {
    if (this.props.num) return html`<h2>Edit Log Entry ${this.props.num}</h2>`

    return html`<h2>Add Log Entry (${this.props.nextNum})</h2>`
  }

  renderInfo() {
    if (this.props.error)
      return html`<em class="error">${this.props.error}</em>`

    if (this.props.info === null) return null
    if (this.props.info === false)
      return html`<em class="warning">not found</em>`

    const { city, state, country } = this.props.info
    return html`
      <span>
        ${stationName(this.props)}, ${city}, ${state} (${country})
        ${this.renderLastCheckin()}
      </span>
    `
  }

  renderLastCheckin() {
    const lastCheckin =
      this.props.info.existingCheckins.length > 0 &&
      this.props.info.existingCheckins[
        this.props.info.existingCheckins.length - 1
      ]

    if (!lastCheckin) return null

    return html`<br />
      <span class="notice">
        Already checked in ${dayjs(lastCheckin.checked_in_at).fromNow()}
      </span>`
  }

  renderClear() {
    if (
      !present(this.props.call_sign) &&
      !present(this.props.remarks) &&
      !present(this.props.notes)
    )
      return null

    return html`<span
      class="linkish"
      onclick=${() => {
        this.props.onClear()
        this.focus()
      }}
    >
      cancel
    </span>`
  }
}

class CreateNetForm extends Component {
  state = {
    club_id: "",
    net_name: "",
    net_password: "",
    frequency: "",
    band: "",
    mode: "",
    net_control: this.props.net_control,
    submitting: false,
    errorFields: {},
    errorMessage: null,
    closedNets: [],
  }

  guessStuffFromFrequency(frequencyValue) {
    const freq = parseFloat(frequencyValue)
    if (freq == 0.0) return

    let band = ""
    if (freq >= 420.0 && freq <= 450.0) band = "70cm"
    else if (freq >= 219.0 && freq <= 225.0) band = "1.25cm"
    else if (freq >= 144.0 && freq <= 148.0) band = "2m"
    else if (freq >= 50.0 && freq <= 54.0) band = "6m"
    else if (freq >= 28.0 && freq <= 29.7) band = "10m"
    else if (freq >= 24.89 && freq <= 24.99) band = "12m"
    else if (freq >= 21.0 && freq <= 21.45) band = "15m"
    else if (freq >= 14.0 && freq <= 14.35) band = "20m"
    else if (freq >= 10.1 && freq <= 10.15) band = "30m"
    else if (freq >= 7.0 && freq <= 7.3) band = "40m"
    else if (freq >= 3.5 && freq <= 4.0) band = "80m"
    else if (freq >= 1.8 && freq <= 2.0) band = "160m"
    if (band != "") this.setState({ band })

    let mode = ""
    if (band === "70cm") {
      if (freq == 446.0) mode = "FM"
    } else if (band === "2m") {
      if (freq >= 145.2 && freq <= 145.5) mode = "FM"
      else if (freq >= 146.4 && freq <= 146.58) mode = "FM"
      else if (freq >= 147.42 && freq <= 147.57) mode = "FM"
      else if (freq >= 144.2 && freq <= 144.275) mode = "SSB"
    }
    if (mode !== "") this.setState({ mode })
  }

  handleSubmit(e) {
    e.preventDefault()

    if (this.state.submitting) return
    this.setState({ submitting: true })

    fetch("/create-net", {
      method: "POST",
      body: JSON.stringify({
        club_id: this.state.club_id,
        net_name: this.state.net_name,
        net_password: this.state.net_password,
        frequency: this.state.frequency,
        band: this.state.band,
        mode: this.state.mode,
        net_control: this.state.net_control,
      }),
    })
      .then((response) => {
        if (response.redirected) {
          window.location.href = response.url
        }
        return response.json()
      })
      .then((data) => {
        if (data.error) {
          const errorFields = {}
          data.fields.forEach((field) => (errorFields[field] = true))
          this.setState({
            errorMessage: data.error,
            errorFields,
            submitting: false,
          })
        }
      })
  }

  fetchClosedNets() {
    fetch(`/group/${this.state.club_id}/nets.json`)
      .then((r) => r.json())
      .then((nets) => this.setState({ closedNets: nets }))
  }

  render() {
    return html`
      <form onsubmit=${(e) => this.handleSubmit(e)}>
        ${this.renderClubSelect()}
        <label class="${this.state.errorFields.net_name ? "error" : ""}">
          Name of Net:<br />
          <input
            name="net_name"
            value=${this.state.net_name}
            onchange=${(e) => this.setState({ net_name: e.target.value })}
            required
            maxlength="32"
          />
          ${this.state.closedNets.length > 0 &&
          html`<p>Chose a previously-used net name:</p>
            <ul>
              ${this.state.closedNets.map(
                (net) =>
                  html`<li>
                    <span
                      class="linkish"
                      onClick=${() =>
                        this.setState({
                          net_name: net.name,
                          frequency: net.frequency,
                          band: net.band,
                          mode: net.mode,
                        })}
                      >${net.name}</span
                    >${" "} (${net.frequency})
                  </li>`
              )}
            </ul>`}
        </label>
        <label class="${this.state.errorFields.net_password ? "error" : ""}">
          Password:<br />
          <input
            type="password"
            name="net_password"
            placeholder="something secure"
            value=${this.state.net_password}
            onchange=${(e) => this.setState({ net_password: e.target.value })}
            required
            maxlength="20"
          />
        </label>
        <label class="${this.state.errorFields.frequency ? "error" : ""}">
          Frequency in MHz:<br />
          <input
            id="frequency"
            name="frequency"
            placeholder="146.52"
            value=${this.state.frequency}
            oninput=${(e) => {
              this.setState({ frequency: e.target.value })
              this.guessStuffFromFrequency(e.target.value)
            }}
            required
            maxlength="16"
          />
        </label>
        <label class="${this.state.errorFields.band ? "error" : ""}">
          Band:<br />
          <select
            id="band"
            name="band"
            value=${this.state.band}
            onchange=${(e) => this.setState({ band: e.target.value })}
          >
            <option value=""></option>
            <option>70cm</option>
            <option>1.25m</option>
            <option>2m</option>
            <option>6m</option>
            <option>10m</option>
            <option>12m</option>
            <option>15m</option>
            <option>17m</option>
            <option>20m</option>
            <option>30m</option>
            <option>40m</option>
            <option>60m</option>
            <option>80m</option>
            <option>160m</option>
            <option>(Custom)</option></select
          ><br />
          ${this.state.band == "(Custom)" &&
          html`
            <input name="band" placeholder="Band" required maxlength="10" />
          `}
        </label>
        <label class="${this.state.errorFields.mode ? "error" : ""}">
          Mode:<br />
          <select
            id="mode"
            name="mode"
            value=${this.state.mode}
            onchange=${(e) => this.setState({ mode: e.target.value })}
          >
            <option value=""></option>
            <option>SSB</option>
            <option>AM</option>
            <option>FM</option>
            <option>CW</option>
            <option>DIGITAL</option>
            <option>(Custom)</option></select
          ><br />
          ${this.state.mode == "(Custom)" &&
          html`
            <input name="mode" placeholder="Mode" required maxlength="10" />
          `}
        </label>
        <label class="${this.state.errorFields.net_control ? "error" : ""}">
          Net Control:<br />
          <input
            name="net_control"
            value=${this.state.net_control}
            onchange=${(e) => this.setState({ net_control: e.target.value })}
            placeholder="call sign here"
            required
            maxlength="20"
          />
        </label>
        <input
          type="submit"
          value="START NET NOW"
          disabled=${this.state.submitting}
        />
        ${this.state.errorMessage &&
        html`<p class="error">
          ${this.state.errorMessage.replace(/_/g, " ")}
        </p>`}
      </form>
    `
  }

  renderClubSelect() {
    return html`
      <label class="${this.state.errorFields.club_id ? "error" : ""}">
        Group or Club:<br />
        <select
          name="club_id"
          value=${this.state.club_id}
          onchange=${(e) => {
            this.setState({ club_id: e.target.value }, () => {
              this.fetchClosedNets()
            })
          }}
        >
          <option value=""></option>
          ${this.props.clubs.map(
            (club) => html`<option value=${club.id}>${club.name}</option>`
          )}
        </select>
      </label>
      <p>
        <em
          >If your club is not listed above, you may find it${" "}
          <a href="/groups">here</a>.</em
        >
      </p>
    `
  }
}

class CreateNet extends Component {
  state = { formVisible: false }

  render() {
    if (this.props.clubs.length === 0)
      return html`<p>
        <em
          >You are not a member of any groups or clubs. Please go find and join
          one${" "} <a href="/groups">here</a>.</em
        >
      </p>`

    return html`
      <p>
        <input
          id="understand"
          type="checkbox"
          onclick=${() =>
            this.setState({ formVisible: !this.state.formVisible })}
        />
        <label for="understand">I understand, please let me start a net.</label>
      </p>

      ${this.state.formVisible ? h(CreateNetForm, this.props) : null}
    `
  }
}

class CurrentTime extends Component {
  state = { time: new Date() }

  componentDidMount() {
    window.currentTimeInterval = setInterval(
      () => this.setState({ time: new Date() }),
      1000
    )
  }

  componentWillUnmount() {
    if (window.currentTimeInterval) clearInterval(window.currentTimeInterval)
  }

  render() {
    return formatTimeWithDayjs(this.state.time, true)
  }
}

function stationName({ name, preferred_name, info }) {
  if (!name && info) name = `${info.first_name} ${info.last_name}`

  if (
    !present(preferred_name) ||
    !present(name) ||
    name.match(new RegExp(`^${preferred_name}( |$)`, "i"))
  )
    return name

  return `(${preferred_name}) ${name}`
}

function formatTimeWithDayjs(time, timeOnly) {
  if (!time) return null

  let timeFormat = "HH:mm:ss"
  const formatOption = document.querySelector("body").dataset.timeFormat
  if (formatOption === "local_12") timeFormat = "hh:mm:ss a"
  else if (formatOption === "utc_24") timeFormat = "HH:mm:ss UTC"

  let d = dayjs(time)
  if (formatOption.match(/utc/)) d = d.utc()

  if (timeOnly) return d.format(timeFormat)

  return d.format(`YYYY-MM-DD ${timeFormat}`)
}

function present(value) {
  if (!value) return false

  if (typeof value === "string") return value.trim().length > 0

  return true
}

function presence(value) {
  if (!present(value)) return null

  return value
}

function pluralize(word, count) {
  if (count == 1) return word

  return `${word}s`
}

function hashCode(str) {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i)
    hash = (hash << 5) - hash + char
    hash |= 0 // Convert to 32bit integer
  }
  return hash
}

function hashToRgb(hash) {
  // Ensure the color is within a valid RGB range
  const r = (hash & 0xff0000) >> 16
  const g = (hash & 0x00ff00) >> 8
  const b = hash & 0x0000ff
  return [r, g, b]
}

function rgbToHex(r, g, b) {
  return `#${[r, g, b]
    .map((x) => {
      const hex = x.toString(16).padStart(2, "0")
      return hex
    })
    .join("")}`
}

function adjustLightness(r, g, b, targetLightness) {
  // Convert RGB to HSL
  const rNorm = r / 255
  const gNorm = g / 255
  const bNorm = b / 255
  const max = Math.max(rNorm, gNorm, bNorm)
  const min = Math.min(rNorm, gNorm, bNorm)
  const lightness = (max + min) / 2

  // Calculate adjustment factor
  const factor = targetLightness / lightness
  const adjustedR = Math.min(Math.max(Math.round(rNorm * factor * 255), 0), 255)
  const adjustedG = Math.min(Math.max(Math.round(gNorm * factor * 255), 0), 255)
  const adjustedB = Math.min(Math.max(Math.round(bNorm * factor * 255), 0), 255)

  return [adjustedR, adjustedG, adjustedB]
}

function getUniqueColor(username, targetLightness = 0.4) {
  const hash = hashCode(username)
  const [r, g, b] = hashToRgb(hash)
  const [adjustedR, adjustedG, adjustedB] = adjustLightness(
    r,
    g,
    b,
    targetLightness
  )
  return rgbToHex(adjustedR, adjustedG, adjustedB)
}

const components = { Net, CreateNet }

document.querySelectorAll("[data-component]").forEach((elm) => {
  const name = elm.dataset.component
  const props = elm.dataset.props ? JSON.parse(elm.dataset.props) : {}
  elm.innerHTML = ""
  render(html`<${components[name]} ...${props} />`, elm)
})

function updatePage() {
  fetch(location.href, {
    headers: {
      "X-Requested-With": "XMLHttpRequest",
    },
  })
    .then((resp) => {
      if (resp.redirected) location.href = "/"
      else if (resp.status != 200) location.reload()
      return resp.text()
    })
    .then((html) => {
      const newDocument = new DOMParser().parseFromString(html, "text/html")
      newDocument.querySelectorAll(".update-in-place").forEach((newElm) => {
        if (newElm.id) {
          formatTimes(newElm)
          updateCurrentTime(newElm)
          const existingElm = document.getElementById(newElm.id)
          existingElm.parentNode.replaceChild(newElm, existingElm)
        }
      })
      const netMapElm = newDocument.getElementById("net-map")

      if (netMapElm) {
        maybeUpdateNetMapCoords(JSON.parse(netMapElm.dataset.coords || "null"))
      }
    })
}

function maybeUpdateNetMapCoords(coords) {
  // find new coords
  const newCoords = []

  if (coords) {
    const existingCoords = new Set(
      window.netMapCoords.map((coord) => JSON.stringify(coord))
    )
    coords.forEach((coord) => {
      const string = JSON.stringify(coord)
      if (existingCoords.has(string)) existingCoords.delete(string)
      else newCoords.push(coord)
    })

    if (existingCoords.size > 0) {
      // something was removed so just rebuild the whole map
      window.netMapCoords = []
      netMap.remove()
      buildNetMap()
      updateNetMapCoords(coords)
    } else if (newCoords.length > 0) {
      updateNetMapCoords(newCoords)
    }
  }

  // redraw all centers
  const netMapElm = document.getElementById("net-map")
  const centersAttribute = netMapElm.dataset.centers
  if (centersAttribute) {
    const centers = JSON.parse(centersAttribute)
    updateNetMapCenters(centers)
  }
}

function buildNetMap() {
  window.netMap = L.map("net-map", { zoomSnap: 0.5 }).setView(
    [38.53, -100.25],
    4
  )
  netMap.attributionControl.setPrefix("")
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution:
      '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(netMap)

  window.netMapOms = new OverlappingMarkerSpiderfier(netMap)
  const popup = new L.Popup({ offset: [0, -30] })
  netMapOms.addListener("click", (marker) => {
    popup.setContent(marker.desc)
    popup.setLatLng(marker.getLatLng())
    netMap.openPopup(popup)
  })
}

function updateNetMapCoords(coords) {
  window.netMapCoords = (window.netMapCoords || []).concat(coords)
  if (coords === null) return

  coords.forEach(({ lat, lon, callSign, name }) => {
    const marker = L.marker([lat, lon])
    if (callSign)
      marker.desc = `<a href="https://www.qrz.com/db/${callSign}" target="_blank">${callSign}</a> ${name}`
    netMap.addLayer(marker)
    netMapOms.addMarker(marker)
  })
  if (netMapCoords.length > 0)
    netMap.fitBounds(netMapCoords, { maxZoom: 6, padding: [50, 50] })
}

function updateNetMapCenters(centers) {
  window.netMapCenters = window.netMapCenters || []
  netMapCenters.forEach((c) => c.remove())
  window.netMapCenters = []
  centers.forEach((center) => {
    if (center && center.latitude && center.longitude && center.radius) {
      const circle = L.circle([center.latitude, center.longitude], {
        color: "red",
        fillColor: "#f99",
        fillOpacity: center.radius < 100000 ? 0.9 : 0.3,
        stroke: false,
        radius: center.radius,
      }).addTo(netMap)
      if (center.url && center.name) {
        circle.bindPopup(`<a href='${center.url}'>${center.name}</a>`)
      }
      circle.on("mouseover", (e) => {
        circle.setStyle({ fillColor: "#ff9" })
      })
      circle.on("mouseout", (e) => {
        circle.setStyle({ fillColor: "#f99" })
      })
      netMapCenters.push(circle)
    }
  })
  if (centers.length > 0) {
    const bounds = L.latLngBounds(
      centers.map((c) => L.latLng(c.latitude, c.longitude))
    )
    centers.forEach((center) => {
      if (center.latitude && center.longitude && center.radius) {
        bounds.extend(
          L.latLng(center.latitude, center.longitude).toBounds(center.radius)
        )
      }
    })
    netMap.fitBounds(bounds, { maxZoom: 5, padding: [50, 50] })
  }
}

function formatTimes(parent) {
  parent = parent || document.body
  parent.querySelectorAll(".time").forEach((elm) => {
    const time = new Date(elm.dataset.time)
    const timeOnly = elm.classList.contains("time-only")
    elm.innerHTML = formatTimeWithDayjs(time, timeOnly)
  })
}

function updateCurrentTime(parent) {
  parent = parent || document.body
  parent.querySelectorAll(".current-time").forEach((elm) => {
    const time = new Date()
    elm.innerHTML = formatTimeWithDayjs(time, true)
  })
}

document.addEventListener("readystatechange", (event) => {
  if (event.target.readyState === "complete") {
    updateCurrentTime()
    setInterval(updateCurrentTime, 1000)
  }
})

function favorite(call_sign, elm, unfavorite) {
  const func = unfavorite ? "unfavorite" : "favorite"
  fetch(`/${func}/${call_sign}`, {
    method: "POST",
    headers: {
      "X-Requested-With": "XMLHttpRequest",
    },
  })
    .then((data) => data.json())
    .then((json) => {
      if (json.error) alert(json.error)
      else if (elm) elm.outerHTML = json.html
    })
    .catch(console.error)
}

window.favorite = favorite
window.buildNetMap = buildNetMap
window.updateNetMapCenters = updateNetMapCenters
window.setIntervalWithBackoff = setIntervalWithBackoff
window.updatePage = updatePage
window.formatTimes = formatTimes

formatTimes()

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("a[data-method]").forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault()
      const form = document.createElement("form")
      form.method = link.dataset.method
      form.action = link.href
      document.querySelector("body").appendChild(form)
      form.submit()
    })
  })
})

function buildStatCharts() {
  let elm = document.getElementById("user_chart_hourly")
  if (elm) {
    const user_data_hourly = JSON.parse(elm.dataset.data)
    const active_user_data_hourly = user_data_hourly.active_users
    const new_user_data_hourly = user_data_hourly.new_users
    Plotly.newPlot(
      "user_chart_hourly",
      [active_user_data_hourly, new_user_data_hourly],
      { title: "active users", barmode: "stack" }
    )
  }

  elm = document.getElementById("net_chart_hourly")
  if (elm) {
    const net_data_hourly = JSON.parse(elm.dataset.data)
    net_data_hourly.marker = { color: "orange" }
    Plotly.newPlot("net_chart_hourly", [net_data_hourly], { title: "nets" })
  }

  elm = document.getElementById("user_chart_daily")
  if (elm) {
    const user_data_daily = JSON.parse(elm.dataset.data)
    const active_user_data_daily = user_data_daily.active_users
    const new_user_data_daily = user_data_daily.new_users
    Plotly.newPlot(
      "user_chart_daily",
      [active_user_data_daily, new_user_data_daily],
      { title: "active users", barmode: "stack" }
    )
  }

  elm = document.getElementById("net_chart_daily")
  if (elm) {
    const net_data_daily = JSON.parse(elm.dataset.data)
    net_data_daily.marker = { color: "orange" }
    Plotly.newPlot("net_chart_daily", [net_data_daily], { title: "nets" })
  }
}
window.buildStatCharts = buildStatCharts
