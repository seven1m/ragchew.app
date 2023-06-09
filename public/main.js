function updatePage() {
  fetch(location.href, {
    headers: {
      'X-Requested-With': 'XMLHttpRequest'
    }
  })
    .then((resp) => {
      if (resp.redirected)
        location.href = '/'
      else if (resp.status != 200)
        location.reload()
      return resp.text()
    })
    .then((html) => {
      const newDocument = new DOMParser().parseFromString(html, 'text/html')
      newDocument.querySelectorAll('.update-in-place').forEach((newElm) => {
        if (newElm.id) {
          const existingElm = document.getElementById(newElm.id)
          existingElm.parentNode.replaceChild(newElm, existingElm)
        }
      })
      const netMapElm = newDocument.getElementById('net-map')

      if (netMapElm) {
        // find new coords
        const coordsAttribute = netMapElm.getAttribute('data-coords')
        let newCoords = []
        if (coordsAttribute) {
          const existingCoords = new Set(
            window.netMapCoords.map((coord) => JSON.stringify(coord))
          )
          JSON.parse(coordsAttribute).forEach((coord) => {
            if (!existingCoords.has(JSON.stringify(coord)))
              newCoords.push(coord)
          })
          console.log(newCoords)
          if (newCoords.length > 0)
            updateNetMapCoords(newCoords)
        }

        // redraw all centers
        const centersAttribute = netMapElm.getAttribute('data-centers')
        if (centersAttribute) {
          const centers = JSON.parse(centersAttribute)
          updateNetMapCenters(centers)
        }
      }
    })
}

function sendMessage(form) {
  const input = document.getElementById('message')
  fetch(
    form.getAttribute('action'),
    {
      method: form.getAttribute('method'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=ISO-8859-1',
        'X-Requested-With': 'XMLHttpRequest'
      },
      body: 'message=' + encodeURIComponent(input.value)
    }
  ).then((data) => {
    return data.text()
  }).then((_html) => {
    input.value = ''
    updatePage()
  }).catch((error) => {
    console.error(error)
  })
}

function buildNetMap(coords, centers) {
  window.netMap = L.map('net-map', { zoomSnap: 0.5 })
    .setView([38.53, -100.25], 4)
  netMap.attributionControl.setPrefix('')
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  }).addTo(netMap)

  window.netMapOms = new OverlappingMarkerSpiderfier(netMap)
  const popup = new L.Popup({offset: [0, -30]})
  netMapOms.addListener('click', (marker) => {
    popup.setContent(marker.desc)
    popup.setLatLng(marker.getLatLng())
    netMap.openPopup(popup)
  })
}

function updateNetMapCoords(coords) {
  window.netMapCoords = (window.netMapCoords || []).concat(coords)
  coords.forEach(([lat, lon, callSign]) => {
    const marker = L.marker([lat, lon])
    if (callSign)
      marker.desc = callSign
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
        color: 'red',
        fillColor: '#f99',
        fillOpacity: center.radius < 100000 ? 0.9 : 0.3,
        stroke: false,
        radius: center.radius
      }).addTo(netMap)
      if (center.url && center.name) {
        circle.bindPopup(`<a href='${center.url}'>${center.name}</a>`)
      }
      circle.on('mouseover', (e) => {
        circle.setStyle({ fillColor: '#ff9' })
      })
      circle.on('mouseout', (e) => {
        circle.setStyle({ fillColor: '#f99' })
      })
      netMapCenters.push(circle)
    }
  })
  if (centers.length > 0) {
    const bounds = L.latLngBounds(centers.map((c) => L.latLng(c.latitude, c.longitude)))
    centers.forEach((center) => {
      if (center.latitude && center.longitude && center.radius) {
        bounds.extend(L.latLng(center.latitude, center.longitude).toBounds(center.radius))
      }
    })
    netMap.fitBounds(bounds, { maxZoom: 5, padding: [50, 50] })
  }
}

function updateCurrentTime() {
  document.body.querySelectorAll('.current-time').forEach((elm) => {
    const date = new Date()
    const year = date.getUTCFullYear()
    let month = new String(date.getUTCMonth() + 1)
    if (month.length == 1) month = '0' + month 
    let day = new String(date.getUTCDate())
    if (day.length == 1) day = '0' + day 
    let hour = new String(date.getUTCHours())
    if (hour.length == 1) hour = '0' + hour 
    let minute = new String(date.getUTCMinutes())
    if (minute.length == 1) minute = '0' + minute 
    let second = new String(date.getUTCSeconds())
    if (second.length == 1) second = '0' + second 
    elm.innerHTML = `${year}-${month}-${day} ${hour}:${minute}:${second} UTC`
  })
}

document.addEventListener('readystatechange', (event) => {
  if (event.target.readyState === 'complete') {
    updateCurrentTime()
    setInterval(updateCurrentTime, 1000)
  }
})

function favorite(call_sign, elm, unfavorite) {
  func = unfavorite ? 'unfavorite' : 'favorite'
  fetch(`/${func}/${call_sign}`, {
    method: 'POST',
    headers: {
      'X-Requested-With': 'XMLHttpRequest'
    }
  })
    .then(data => data.json())
    .then(json => {
      if (json.error)
        alert(json.error)
      else
        elm.outerHTML = json.html
    })
    .catch(console.error)
}
