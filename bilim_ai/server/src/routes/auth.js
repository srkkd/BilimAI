import express from 'express';
import bcrypt from 'bcryptjs';
import { signToken } from '../middleware/auth.js';

export default function authRoutes(prisma) {
  const router = express.Router();

  router.post('/register', async (req, res) => {
    try {
      const { email, password, displayName } = req.body || {};
      if (!email || !password) return res.status(400).json({ error: 'email and password required' });
      const exists = await prisma.user.findUnique({ where: { email } });
      if (exists) return res.status(409).json({ error: 'email already used' });
      const passwordHash = await bcrypt.hash(password, 10);
      const user = await prisma.user.create({ data: { email, passwordHash, displayName } });
      const token = signToken(user);
      res.json({ token, user: { id: user.id, email: user.email, displayName: user.displayName } });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  router.post('/login', async (req, res) => {
    try {
      const { email, password } = req.body || {};
      if (!email || !password) return res.status(400).json({ error: 'email and password required' });
      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) return res.status(401).json({ error: 'invalid credentials' });
      const ok = await bcrypt.compare(password, user.passwordHash);
      if (!ok) return res.status(401).json({ error: 'invalid credentials' });
      const token = signToken(user);
      res.json({ token, user: { id: user.id, email: user.email, displayName: user.displayName } });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  return router;
}
