import express from 'express';
import { requireAuth } from '../middleware/auth.js';

export default function messagesRoutes(prisma) {
  const router = express.Router();
  router.use(requireAuth);

  // List messages for a chat
  router.get('/:chatId', async (req, res) => {
    try {
      const userId = req.user.sub;
      const { chatId } = req.params;
      const chat = await prisma.chat.findUnique({ where: { id: chatId } });
      if (!chat || chat.userId !== userId) return res.status(404).json({ error: 'Not found' });
      const msgs = await prisma.message.findMany({
        where: { chatId },
        orderBy: { createdAt: 'asc' },
      });
      res.json(msgs);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // Create message
  router.post('/:chatId', async (req, res) => {
    try {
      const userId = req.user.sub;
      const { chatId } = req.params;
      const chat = await prisma.chat.findUnique({ where: { id: chatId } });
      if (!chat || chat.userId !== userId) return res.status(404).json({ error: 'Not found' });
      const { role, content } = req.body || {};
      if (!role || !content) return res.status(400).json({ error: 'role and content required' });
      const msg = await prisma.message.create({ data: { chatId, role, content } });
      res.status(201).json(msg);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  return router;
}
