import React from 'react';

function NoteCard({ note, deleteNote }) {
  return (
    <div style={{ padding: '1rem', background: 'white', borderRadius: '8px', boxShadow: '0 2px 5px rgba(0,0,0,0.1)' }}>
      <p>{note.content}</p>
      <button onClick={() => deleteNote(note.id)} style={{ marginTop: '0.5rem', color: 'red' }}>Delete</button>
    </div>
  );
}

export default NoteCard;
