import express from 'express';
import { requireAuth } from '../middleware/auth.js';

export default function chatsRoutes(prisma) {
  const router = express.Router();
  router.use(requireAuth);

  // List chats of current user
  router.get('/', async (req, res) => {
    try {
      const userId = req.user.sub;
      const chats = await prisma.chat.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
      });
      res.json(chats);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // Create chat
  router.post('/', async (req, res) => {
    try {
      const userId = req.user.sub;
      const { title } = req.body || {};
      const chat = await prisma.chat.create({ data: { userId, title } });
      res.status(201).json(chat);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // Delete chat with its messages
  router.delete('/:id', async (req, res) => {
    try {
      const userId = req.user.sub;
      const { id } = req.params;
      const chat = await prisma.chat.findUnique({ where: { id } });
      if (!chat || chat.userId !== userId) return res.status(404).json({ error: 'Not found' });
      await prisma.message.deleteMany({ where: { chatId: id } });
      await prisma.chat.delete({ where: { id } });
      res.json({ ok: true });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  return router;
}
