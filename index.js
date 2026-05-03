const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send("<h1>main branch version_test2</h1>")
})
app.post('/', (req, res) => {
  res.send("Received!")
})

app.listen(5000, () =>
  console.log('EXPRESS Server Started at Port No: 5000'));