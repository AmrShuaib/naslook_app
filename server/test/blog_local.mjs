import Fastify from 'fastify';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const app = Fastify();
app.register((await import('../blog.js')).default);
await app.listen({ port: 8095, host: '127.0.0.1' });
console.log('blog local up');
