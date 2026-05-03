const express = require('express');
const app = express();

// FIX: Disables the 'X-Powered-By: Express' header to prevent fingerprinting
app.disable('x-powered-by');

app.get('/', (req, res) => {
  res.send("<h1>creatingconflict branch version</h1>")
});

app.post('/', (req, res) => {
  res.send("Received!")
});

// Complete the listen function
const PORT = 5000;
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
