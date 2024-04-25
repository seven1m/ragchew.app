import { h, render, Component, createRef } from "https://esm.sh/preact"
import htm from "https://esm.sh/htm"
import dayjs from "https://esm.sh/dayjs"

const html = htm.bind(h)

class Net extends Component {
  state = {
    checkins: [],
    coords: [],
    messages: [],
    messagesCount: 0,
    monitors: [],
    favorites: [],
    lastUpdatedAt: null,
    editing: {
      num: null,
      call_sign: "",
      remarks: "",
    },
    info: null,
    error: null,
  }

  formRef = createRef()

  componentDidMount() {
    this.updateData()
    const minute = 60 * 1000
    const hour = 60 * minute
    setIntervalWithBackoff(
      this.updateData.bind(this),
      this.props.updateInterval * 1000,
      0,
      3 * hour
    )
  }

  async updateData() {
    try {
      const response = await fetch(`/net/${this.props.netId}/details`)
      if (response.status === 404) {
        location.reload() // show closed-net page
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
        removeEntryFromView=${this.removeEntryFromView.bind(this)}
        highlightEntry=${this.highlightEntry.bind(this)}
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
        onRemarksInput: this.handleRemarksInput.bind(this),
        onSubmit: this.handleLogFormSubmit.bind(this),
        onClear: this.handleLogFormClear.bind(this),
      })}

      <h2>Messages</h2>

      <${Messages}
        messages=${this.state.messages}
        monitoringThisNet=${this.props.monitoringThisNet}
        messagesCount=${this.state.messagesCount}
        netId=${this.props.netId}
        userCallSign=${this.props.userCallSign}
      />

      <h2>Monitors</h2>

      <${Monitors} monitors=${this.state.monitors} />
    `
  }

  nextNum() {
    return Math.max(...this.state.checkins.map((checkin) => checkin.num), 0) + 1
  }

  handleCallSignInput(call_sign) {
    this.setState({
      editing: { ...this.state.editing, call_sign: call_sign.toUpperCase() },
    })
    if (window.inputTimeout) clearTimeout(window.inputTimeout)
    window.inputTimeout = setTimeout(async () => {
      if (this.state.editing.call_sign.length >= 4) {
        try {
          const response = await fetch(
            `/station/${this.state.editing.call_sign}`
          )
          if (response.status === 200) {
            const info = await response.json()
            if (info.error) this.setState({ info: false })
            else this.setState({ info })
          } else {
            this.setState({ info: null })
            console.error(`Error fetching station: ${error}`)
          }
        } catch (error) {
          this.setState({ info: null })
          console.error(`Error fetching station: ${error}`)
        }
      } else {
        this.setState({ info: null })
      }
    }, 800)
  }

  handleRemarksInput(remarks) {
    this.setState({ editing: { ...this.state.editing, remarks } })
  }

  async handleLogFormSubmit() {
    if (!present(this.state.editing.call_sign)) return

    this.setState({ submitting: true, error: null })

    let info = this.state.info
    if (!info) {
      try {
        const response = await fetch(`/station/${this.state.editing.call_sign}`)
        info = await response.json()
        if (info.error) info = { call_sign: this.state.editing.call_sign }
      } catch (error) {
        info = { call_sign: this.state.editing.call_sign }
        console.error(`Error fetching station: ${error}`)
      }
    }

    const payload = {
      ...info,
      id: this.props.netId,
      num: this.state.editing.num,
      remarks: this.state.editing.remarks,
      name: `${info.first_name} ${info.last_name}`,
      preferred_name: info.first_name,
      checked_in_at: dayjs().format(),
    }
    this.addOrUpdateEntry(payload)
    try {
      const response = await fetch(`/log/${this.props.netId}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
        body: JSON.stringify(payload),
      })
      if (response.status === 201) {
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
        this.removeEntryFromView(this.props.num)
        return false
      }
    } catch (error) {
      console.error(error)
      this.setState({ error: `There was an error: ${error}` })
      this.removeEntryFromView(this.props.num)
      return false
    }
  }

  handleLogFormClear() {
    this.setState({ editing: { call_sign: "", remarks: "" }, info: null })
  }

  handleEditEntry(num) {
    const entry = this.state.checkins.find((c) => c.num === num)
    this.setState({ editing: entry })
    this.formRef.current.focus()
  }

  // This just superficially updates the entry table in memory.
  addOrUpdateEntry(entry) {
    console.log(entry)
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

  // This just superficially updates the entry table in memory.
  removeEntryFromView(num) {
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

  // This just superficially updates the entry table in memory.
  highlightEntry(num) {
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
                removeEntryFromView: this.props.removeEntryFromView,
                highlightEntry: this.props.highlightEntry,
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
        this.props.removeEntryFromView(this.props.num)
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
      this.props.highlightEntry(this.props.num)
    } else {
      console.error(`Error highlighting entry: ${response.status}`)
    }
  }

  render() {
    return [this.renderDetails(), this.renderRemarks()]
  }

  renderDetails() {
    if (!present(this.props.call_sign)) return null

    return html`<tr class="details ${this.rowClass()}">
      <td>${this.props.num}</td>
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
        ${" "}${this.renderLoggerControls()}
      </td>
      <td>${this.props.name}</td>
      <td>${formatTime(this.props.checked_in_at)}</td>
      <td>${this.props.grid_square}</td>
      <td>${this.props.status}</td>
      <td>${this.props.city}</td>
      <td>${this.props.county}</td>
      <td>${this.props.state}</td>
      <td>${this.props.country}</td>
    </tr>`
  }

  renderRemarks() {
    if (!present(this.props.remarks)) return null

    return html`
      <tr class="remarks ${this.rowClass()}">
        ${present(this.props.call_sign)
          ? html`<td></td>`
          : html`<td>${this.props.num}</td>`}
        <td></td>
        <td colspan="9" class="can-wrap">${this.props.remarks}</td>
      </tr>
    `
  }

  renderLoggerControls() {
    if (!this.props.isLogger) return null

    return html`
      <button onclick=${this.handleEdit.bind(this)}>edit</button>
      ${" "}
      <button
        onclick=${this.handleDelete.bind(this)}
        class=${this.state.deleting && "danger"}
      >
        delete ${this.state.deleting && "(click again)"}
      </button>
      ${" "}
      <button onclick=${this.handleHighlight.bind(this)}>highlight</button>
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
      >
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
          Remarks:<br />
          <input
            name="remarks"
            value=${this.props.remarks}
            oninput=${(e) => this.props.onRemarksInput(e.target.value)}
            autocomplete="off"
          />
        </label>
        <input type="submit" value=${this.props.num ? "Update" : "Add"} />
        ${" "}${this.renderInfo()} ${this.renderClear()}
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
    if (this.props.info === false) return html`<span>not found</span>`

    return html`
      <span>
        ${this.props.info.first_name} ${this.props.info.last_name},${" "}
        ${this.props.info.city}, ${this.props.info.state}${" "}
        (${this.props.info.country})
      </span>
    `
  }

  renderClear() {
    if (!present(this.props.call_sign) && !present(this.props.remarks))
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
        <label class="${this.state.errors.name ? "error" : ""}">
          Name of Net:<br />
          <input
            name="name"
            value=${this.state.name}
            onchange=${(e) => this.setState({ name: e.target.value })}
          />
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
