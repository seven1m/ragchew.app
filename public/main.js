function updatePage() {
  fetch(location.href)
    .then((resp) => {
      if (resp.redirected)
        location.href = '/'
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
      const netNetMap = newDocument.getElementById('net-map')
      if (netNetMap) {
        const existingCoords = new Set(
          JSON.parse(
            document.getElementById('net-map').getAttribute('data-coords')
          ).map(
            (coord) => JSON.stringify(coord)
          )
        )
        let newCoords = []
        JSON.parse(netNetMap.getAttribute('data-coords')).forEach((coord) => {
          if (!existingCoords.has(JSON.stringify(coord)))
            newCoords.push(coord)
        })
        if (newCoords.length > 0)
          showNetMap(newCoords)
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
        'Content-Type': 'application/x-www-form-urlencoded;charset=ISO-8859-1'
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

function showNetMap(coords) {
  if (!window.netMap) {
    window.netMap = L.map('net-map').setView([51.505, -0.09], 13)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(netMap)
  }
  if (window.netMapCoords)
    window.netMapCoords = window.netMapCoords.concat(coords)
  else
    window.netMapCoords = coords
  coords.forEach(([lat, lon]) => {
    L.marker([lat, lon]).addTo(netMap)
  })
  netMap.fitBounds(netMapCoords)
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
});

