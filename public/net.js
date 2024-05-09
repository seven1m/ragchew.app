import { h, render, Component, createRef } from "https://esm.sh/preact@10.20.2"
import htm from "https://esm.sh/htm@3.1.1"
import dayjs from "https://esm.sh/dayjs@1.11.11"
import relativeTime from "https://esm.sh/dayjs@1.11.11/plugin/relativeTime"
import Pusher from "https://esm.sh/pusher-js@8.4.0-rc2"

dayjs.extend(relativeTime)
const html = htm.bind(h)

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
  }

  formRef = createRef()

  componentDidMount() {
    this.updateData()
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
      this.setState({ messages: [...this.state.messages, message] })
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

  async updateData() {
    try {
      if (this.state.fetchInFlight) return
      this.setState({ fetchInFlight: true })
      const response = await fetch(`/net/${this.props.netId}/details`)
      this.setState({ fetchInFlight: false })

      if (response.status !== 200) {
        location.reload() // show closed-net page or redirect
      } else {
        const data = await response.json()
        this.setState(data)
      }
    } catch (error) {
      console.error(`Error updating data: ${error}`)
    }
  }

  render() {
    return html`
      <${Map} coords=${this.state.coords} />

      <p class="timestamps">
        Current time: <${CurrentTime} /> (Last updated${" "}
        ${formatTime(this.state.lastUpdatedAt)})
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

      <h2>Messages</h2>

      <${Messages}
        messages=${this.state.messages}
        monitoringThisNet=${this.state.monitoringThisNet}
        messagesCount=${this.state.messagesCount}
        netId=${this.props.netId}
        userCallSign=${this.props.userCallSign}
      />

      <h2>Monitors</h2>

      <${Monitors} monitors=${this.state.monitors} />
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

  async clearStationInfo(info = null) {
    await this.setState({
      info,
      editing: { ...this.state.editing, preferred_name: "", notes: "" },
    })
  }

  async fetchStationInfo() {
    try {
      const response = await fetch(
        `/station/${this.state.editing.call_sign}?${
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
            preferred_name: presence(info.preferred_name) || "",
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
    let info = this.state.info

    const payload = {
      ...info,
      id: this.props.netId,
      num: this.state.editing.num,
      preferred_name: this.state.editing.preferred_name,
      remarks: this.state.editing.remarks,
      notes: this.state.editing.notes,
      name: `${info.first_name} ${info.last_name}`,
      checked_in_at: dayjs().format(),
    }
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
      <td>${presence(this.props.preferred_name) || this.props.name}</td>
      <td>${formatTime(this.props.checked_in_at)}</td>
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
          ${this.props.notes &&
          html`<br /><em>Station Notes: ${this.props.notes}</em>`}
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
    if (!this.props.monitoringThisNet)
      return html`
        <p>
          <em>
            ${this.props.messagesCount}${" "}
            ${pluralize("message", this.props.messagesCount)}.
          </em>${" "}
          Click below to participate.
          <form action="/monitor/${
            this.props.netId
          }" method="post"><button>Monitor this Net</button></form>
        </p>
        `

    return [this.renderTable(), this.renderForm()]
  }

  renderTable() {
    if (this.props.messages.length === 0)
      return html`<p><em>no messages yet</em></p>`

    return html`
      <div class="table-wrapper blue-screen">
        <table>
          <thead>
            <tr>
              <th>Call Sign</th>
              <th>Message</th>
              <th>Timestamp</th>
            </tr>
          </thead>
          <tbody>
            ${this.props.messages.map(
              (message) =>
                html`<tr>
                  <td>${message.call_sign}</td>
                  <td class="can-wrap">${message.message}</td>
                  <td>${formatTime(message.sent_at)}</td>
                </tr>`
            )}
            ${this.state.sendingMessage &&
            html`<tr>
              <td>${this.props.userCallSign} <em>sending...</em></td>
              <td class="can-wrap">${this.state.sendingMessage}</td>
              <td>${formatTime(new Date())}</td>
            </tr>`}
          </tbody>
        </table>
      </div>
    `
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
      <form action="/unmonitor/${this.props.netId}" method="post">
        <p>
          <button>Stop monitoring this Net</button>
        </p>
      </form>
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
                style="text-transform:uppercase"
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
          ${" "}${this.renderInfo()} ${this.renderClear()}
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

    const name =
      this.props.info.preferred_name ||
      `${this.props.info.first_name} ${this.props.info.last_name}`

    return html`
      <span>
        ${name},${" "} ${this.props.info.city}, ${this.props.info.state}${" "}
        (${this.props.info.country}) ${this.renderLastCheckin()}
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
      <span class="info">
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
    name: "",
    password: "",
    frequency: "",
    band: "",
    mode: "",
    net_control: this.props.net_control,
    submitting: false,
    errors: {},
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

  requiredFields = [
    "club_id",
    "name",
    "password",
    "frequency",
    "band",
    "mode",
    "net_control",
  ]

  handleSubmit(e) {
    if (this.state.submitting) return

    const errors = {}
    for (let i = 0; i < this.requiredFields.length; i++) {
      const key = this.requiredFields[i]
      const value = this.state[key]
      if (value.trim().length === 0) errors[key] = true
    }

    if (!errors.name && !this.state.name.match(/^[A-Za-z0-9][A-Za-z0-9 -]*$/))
      errors.name =
        "Net name must contain only letters, numbers, spaces, and hyphens, " +
        "and must start with a letter or number."

    if (
      !errors.password &&
      (this.state.password.length > 50 ||
        !this.state.password.match(/^[A-Za-z0-9_-]+$/))
    )
      errors.password =
        "Password cannot be more than 50 characters and must contain only letters, numbers, hyphen, and/or underscore."

    this.setState({ errors })
    if (Object.keys(errors).length > 0) e.preventDefault()
    else this.setState({ submitting: true })
  }

  render() {
    return html`
      <form
        action="/create-net"
        method="POST"
        onsubmit=${(e) => this.handleSubmit(e)}
      >
        <label class="${this.state.errors.club_id ? "error" : ""}">
          Club:<br />
          <select
            name="club_id"
            value=${this.state.club_id}
            onchange=${(e) => this.setState({ club_id: e.target.value })}
          >
            <option value=""></option>
            ${this.props.clubs.map(
              (club) => html`<option value=${club.id}>${club.name}</option>`
            )}
          </select>
        </label>
        <label class="${this.state.errors.name ? "error" : ""}">
          Name of Net:<br />
          <input
            name="name"
            value=${this.state.name}
            onchange=${(e) => this.setState({ name: e.target.value })}
          />
          ${typeof this.state.errors.name === "string" &&
          html`<br /><span class="error">${this.state.errors.name}</span>`}
        </label>
        <label class="${this.state.errors.password ? "error" : ""}">
          Password:<br />
          <input
            type="password"
            name="password"
            placeholder="something secure"
            value=${this.state.password}
            onchange=${(e) => this.setState({ password: e.target.value })}
          />
        </label>
        <label class="${this.state.errors.frequency ? "error" : ""}">
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
          />
        </label>
        <label class="${this.state.errors.band ? "error" : ""}">
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
          html` <input name="band" placeholder="Band" /> `}
        </label>
        <label class="${this.state.errors.mode ? "error" : ""}">
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
          html` <input name="mode" placeholder="Mode" /> `}
        </label>
        <label class="${this.state.errors.net_control ? "error" : ""}">
          Net Control:<br />
          <input
            name="net_control"
            value=${this.state.net_control}
            onchange=${(e) => this.setState({ net_control: e.target.value })}
            placeholder="KI5ZDF"
          />
        </label>
        <input
          type="submit"
          value="START NET NOW"
          disabled=${this.state.submitting}
        />
      </form>
    `
  }
}

class CreateNet extends Component {
  state = { formVisible: false }

  render() {
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
    return formatTime(this.state.time)
  }
}

function formatTime(time) {
  if (!time) return null
  return dayjs(time).format("YYYY-MM-DD HH:mm:ss")
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

const components = { Net, CreateNet }

document.querySelectorAll("[data-component]").forEach((elm) => {
  const name = elm.dataset.component
  const props = elm.dataset.props ? JSON.parse(elm.dataset.props) : {}
  elm.innerHTML = ""
  render(html`<${components[name]} ...${props} />`, elm)
})
