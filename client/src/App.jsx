import React, { useEffect, useState } from 'react';
import axios from 'axios';
import NoteForm from './components/NoteForm';
import NoteCard from './components/NoteCard';

function App() {
  const [notes, setNotes] = useState([]);

  const fetchNotes = async () => {
    const res = await axios.get('/api/notes');
    setNotes(res.data);
  };

  useEffect(() => {
    fetchNotes();
  }, []);

  const addNote = async (note) => {
    await axios.post('/api/notes', { content: note });
    fetchNotes();
  };

  const deleteNote = async (id) => {
    await axios.delete(`/api/notes/${id}`);
    fetchNotes();
  };

  return (
    <div style={{ padding: '2rem' }}>
      <h1>Private Note Vault</h1>
      <NoteForm addNote={addNote} />
      <div style={{ marginTop: '2rem', display: 'grid', gap: '1rem' }}>
        {notes.map((note) => (
          <NoteCard key={note.id} note={note} deleteNote={deleteNote} />
        ))}
      </div>
    </div>
  );
}

export default App;
