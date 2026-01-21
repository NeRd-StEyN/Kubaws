import { useState, useEffect } from 'react'
import './App.css'

function App() {
  const [messages, setMessages] = useState([])
  const [inputText, setInputText] = useState('')
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState(null)

  const fetchMessages = async () => {
    setLoading(true)
    try {
      const response = await fetch('http://localhost:5000/api/message')
      const data = await response.json()
      setMessages(data.data || [])
    } catch (err) {
      console.error('Failed to fetch', err)
    } finally {
      setLoading(false)
    }
  }

  const sendMessage = async (e) => {
    e.preventDefault()
    if (!inputText) return

    setLoading(true)
    try {
      const response = await fetch('http://localhost:5000/api/message', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: inputText })
      })
      const result = await response.json()
      setStatus('Success: Saved to DynamoDB!')
      setInputText('')
      fetchMessages() // Refresh list
    } catch (err) {
      setStatus('Error: Could not reach backend')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchMessages()
  }, [])

  return (
    <div className="container">
      <header className="header">
        <h1>Cloud-Native DevOps App</h1>
        <p>Phase 9: DynamoDB + SNS + Lambda</p>
      </header>

      <main className="main">
        <div className="card">
          <form onSubmit={sendMessage} className="form-group">
            <input
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder="Type a message for the cloud..."
              className="styled-input"
            />
            <button type="submit" disabled={loading} className="btn-primary">
              {loading ? 'Processing...' : 'Send to DynamoDB'}
            </button>
          </form>

          {status && <p className="status-msg">{status}</p>}

          <div className="message-list">
            <h3>Cloud Message History:</h3>
            {messages.length === 0 ? <p>No messages yet.</p> : (
              <ul>
                {messages.map(m => (
                  <li key={m.id} className="message-item animated">
                    <strong>{new Date(m.timestamp).toLocaleTimeString()}:</strong> {m.text}
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </main>

      <footer className="footer">
        <p>Integrated with AWS DynamoDB, SNS, and Lambda</p>
      </footer>
    </div>
  )
}

export default App
