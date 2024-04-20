import { h, Component } from "https://esm.sh/preact"
import htm from "https://esm.sh/htm"
import dayjs from "https://esm.sh/dayjs"

const html = htm.bind(h)

export class Form extends Component {
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

export class Checkins extends Component {
  state = {
    checkins: [],
    coords: [],
  }

  componentDidMount() {
    this.updateData()
    setInterval(this.updateData.bind(this), this.props.updateInterval)
  }

  updateData() {
    fetch(`/net/${this.props.netId}/checkins`)
      .then((resp) => resp.json())
      .then((data) => this.setState(data))
  }

  render() {
    if (this.state.checkins.length === 0)
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
            ${this.state.checkins.map((checkin, index) =>
              h(CheckinRow, { ...checkin, index })
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
        <${Favorite} ...${this} />
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
  handleClick() {
    alert("todo: favorite")
    // favorite('${encodeURIComponent(this.props.call_sign)}', this, ${this.props.favorited}"
  }

  render() {
    if (!present(this.props.call_sign)) return null

    return html`
      <img
        src="/images/${this.props.favorited
          ? "star-solid.svg"
          : "star-outline.svg"}"
        class="favorite-star"
        onclick="${(e) => this.handleClick(e)}"
      />
    `
  }
}

function formatTime(time) {
  return dayjs(time).format("YYYY-MM-DD HH:mm:ss")
}

function present(value) {
  if (!value) return false

  if (typeof value === "string") return value.trim().length > 0

  return true
}
