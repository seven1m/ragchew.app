function updatePage() {
  const focused = document.activeElement.id
  if (document.activeElement &&
      document.activeElement.tagName.toLowerCase() == 'input' &&
      document.activeElement.type.toLowerCase() == 'text' &&
      document.activeElement.value != '') {
    console.log('text input has focus; skipping page update')
    return
  }
  fetch(location.href)
    .then((resp) => {
      if (resp.redirected)
        location.href = '/'
      return resp.text()
    })
    .then((html) => {
      const newDocument = new DOMParser().parseFromString(html, 'text/html')
      document.querySelector('body').innerHTML = newDocument.querySelector('body').innerHTML
      if (focused) document.getElementById(focused).focus()
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

