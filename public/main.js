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
          const existingElm = document.getElementById(newElm.id)
          existingElm.parentNode.replaceChild(newElm, existingElm)
        }
      })
      const netMapElm = newDocument.getElementById("net-map")

      if (netMapElm) {
        maybeUpdateNetMapCoords(JSON.parse(netMapElm.dataset.coords || "null"))
      }

      formatTimes()
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

function formatTime(time, timeOnly = false) {
  const year = time.getFullYear()

  let month = new String(time.getMonth() + 1)
  if (month.length == 1) month = "0" + month

  let day = new String(time.getDate())
  if (day.length == 1) day = "0" + day

  let hour = new String(time.getHours())
  if (hour.length == 1) hour = "0" + hour

  let minute = new String(time.getMinutes())
  if (minute.length == 1) minute = "0" + minute

  let second = new String(time.getSeconds())
  if (second.length == 1) second = "0" + second

  if (timeOnly) return `${hour}:${minute}:${second}`

  return `${year}-${month}-${day} ${hour}:${minute}:${second}`
}

function formatTimes() {
  document.querySelectorAll(".time").forEach((elm) => {
    const time = new Date(elm.dataset.time)
    const timeOnly = elm.classList.contains("time-only")
    elm.innerHTML = formatTime(time, timeOnly)
  })
}

function updateCurrentTime() {
  document.body.querySelectorAll(".current-time").forEach((elm) => {
    const time = new Date()
    elm.innerHTML = formatTime(time)
  })
}

document.addEventListener("readystatechange", (event) => {
  if (event.target.readyState === "complete") {
    updateCurrentTime()
    setInterval(updateCurrentTime, 1000)
  }
})

function favorite(call_sign, elm, unfavorite) {
  func = unfavorite ? "unfavorite" : "favorite"
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
