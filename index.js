// IMPORT Express Server
const express = require('express'); 
const app = express();

// SECURITY FIX: Prevent version disclosure by disabling the X-Powered-By header
app.disable('x-powered-by');

app.get('/', (req, res)=> {
    res.send("<h1>i think it's working...</h1>")
})

app.post('/', (req, res)=> {
    res.send("Received!")
})

app.listen(5000, () =>
    console.log('EXPRESS Server Started at Port No: 5000')
);
