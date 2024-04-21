import { h, render, Component } from "https://esm.sh/preact"
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
  }

  componentDidMount() {
    this.updateData()
    setInterval(this.updateData.bind(this), this.props.updateInterval * 1000)
  }

  updateData() {
    fetch(`/net/${this.props.netId}/details`)
      .then((resp) => resp.json())
      .then((data) => this.setState(data))
  }

  render() {
    return html`
      <${Map} coords=${this.state.coords} />

      <p class="timestamps">
        Current time: ${formatTime(new Date())} (Last updated
        ${formatTime(this.state.lastUpdatedAt)})
      </p>

      <h2>Log</h2>

      <${Checkins}
        checkins=${this.state.checkins}
        favorites=${this.state.favorites}
      />

      ${this.props.isLogger && false && h(LogForm)}

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
                favorited: this.props.favorites.indexOf(checkin.call_sign) > -1,
              })
            )}
          </tbody>
        </table>
      </div>
    `
  }
}

class CheckinRow extends Component {
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
          onKeyUp=${(e) => this.setState({ messageInput: e.target.value })}
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
  state = {
    call_sign: "",
    remarks: "",
    errors: {},
  }

  handleSubmit(e) {
    // TODO
    e.preventDefault()
  }

  render() {
    return html`
      <h2>Add Log Entry</h2>
      <form onsubmit=${(e) => this.handleSubmit(e)}>
        <label class="${this.state.errors.call_sign ? "error" : ""}">
          Call Sign:<br />
          <input
            name="call_sign"
            value=${this.state.call_sign}
            onchange=${(e) => this.setState({ call_sign: e.target.value })}
          />
        </label>
        <label class="${this.state.errors.remarks ? "error" : ""}">
          Remarks:<br />
          <input
            name="remarks"
            value=${this.state.remarks}
            onchange=${(e) => this.setState({ remarks: e.target.value })}
          />
        </label>
        <input type="submit" value="Add" />
      </form>
    `
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

const components = { Net, Map }

document.querySelectorAll("[data-component]").forEach((elm) => {
  const name = elm.dataset.component
  const props = elm.dataset.props ? JSON.parse(elm.dataset.props) : {}
  elm.innerHTML = ""
  render(html`<${components[name]} ...${props} />`, elm)
})

// TODO
//    <% if @last_updated_at && params[:autoupdate] != 'false' %>
//      <script>
//        let secondsToWaitBetweenUpdates = <%= @update_interval || 30 %>
//        const updateBackoff = <%= @update_backoff || 0 %>
//        const startTime = new Date()
//        const maxTimeToRefreshInSeconds = 3 * 60 * 60 // 3 hours
//        function updatePageAndScheduleNext() {
//          updatePage()
//          secondsToWaitBetweenUpdates += updateBackoff
//          if ((new Date() - startTime) < (maxTimeToRefreshInSeconds * 1000)) {
//            console.log(`waiting ${secondsToWaitBetweenUpdates} seconds till next update`)
//            setTimeout(updatePageAndScheduleNext, secondsToWaitBetweenUpdates * 1000)
//          } else {
//            console.log(`stopped refreshing after ${maxTimeToRefreshInSeconds} seconds`)
//          }
//        }
//        setTimeout(() => {
//          updatePageAndScheduleNext()
//        }, (secondsToWaitBetweenUpdates - Math.min(secondsToWaitBetweenUpdates, <%= Time.now - @last_updated_at %>)) * 1000)
//      </script>
//    <% end %>
