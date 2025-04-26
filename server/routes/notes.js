const express = require('express');
const router = express.Router();

let notes = [];
let id = 1;

router.get('/', (req, res) => {
  res.json(notes);
});

router.post('/', (req, res) => {
  const { content } = req.body;
  notes.push({ id: id++, content });
  res.status(201).send();
});

router.delete('/:id', (req, res) => {
  const noteId = parseInt(req.params.id);
  notes = notes.filter(note => note.id !== noteId);
  res.status(204).send();
});

module.exports = router;
