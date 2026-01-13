/**
 * Stripe Checkout Session API
 *
 * 后端 API 实现示例 - 用于代理 Stripe Checkout 会话创建
 * 将此代码部署到 writedown.space 服务器
 *
 * 端点: POST /api/create-checkout-session
 */

const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// Stripe Price ID 映射
const PRICE_IDS = {
  pro: 'price_1QoPDkHnr11wuS0JwGaH8Koq',  // RMB 48 Lifetime Pro
  // 可以添加更多价格 ID
};

/**
 * Express.js 路由处理器
 *
 * 请求体:
 * {
 *   "planId": "pro",
 *   "email": "user@example.com",  // 可选
 *   "deviceId": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
 *   "successUrl": "writedown://payment?session_id={CHECKOUT_SESSION_ID}",
 *   "cancelUrl": "writedown://payment-cancelled"
 * }
 *
 * 响应:
 * 成功: { "url": "https://checkout.stripe.com/..." }
 * 失败: { "error": "Error message" }
 */
async function createCheckoutSession(req, res) {
  try {
    const { planId, email, deviceId, successUrl, cancelUrl } = req.body;

    // 验证必要参数
    if (!planId) {
      return res.status(400).json({ error: 'planId is required' });
    }

    if (!deviceId) {
      return res.status(400).json({ error: 'deviceId is required' });
    }

    // 获取对应的 Price ID
    const priceId = PRICE_IDS[planId];
    if (!priceId) {
      return res.status(400).json({ error: `Invalid planId: ${planId}` });
    }

    // 构建 Stripe Checkout Session 配置
    const sessionConfig = {
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      mode: 'payment',
      success_url: successUrl || 'https://www.writedown.space/payment-success',
      cancel_url: cancelUrl || 'https://www.writedown.space/payment-cancelled',
      // 将设备 ID 作为 client_reference_id 存储，用于后续验证
      client_reference_id: deviceId,
      // 订单元数据
      metadata: {
        deviceId: deviceId,
        planId: planId,
        source: 'writedown-macos-app',
      },
    };

    // 如果提供了邮箱，添加到配置中
    if (email && email.trim()) {
      sessionConfig.customer_email = email.trim();
    }

    // 创建 Stripe Checkout Session
    const session = await stripe.checkout.sessions.create(sessionConfig);

    console.log(`✅ Created checkout session ${session.id} for device ${deviceId}`);

    // 返回支付 URL
    res.json({ url: session.url });

  } catch (error) {
    console.error('❌ Failed to create checkout session:', error);

    // 返回错误信息
    res.status(500).json({
      error: error.message || 'Failed to create checkout session',
    });
  }
}

/**
 * Stripe Webhook 处理器
 *
 * 端点: POST /api/stripe-webhook
 *
 * 用于接收 Stripe 的支付成功通知，更新数据库中的订阅状态
 */
async function handleStripeWebhook(req, res) {
  const sig = req.headers['stripe-signature'];
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err) {
    console.error('❌ Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  // 处理不同的事件类型
  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object;
      const deviceId = session.client_reference_id;
      const customerEmail = session.customer_email;

      console.log(`✅ Payment completed for device: ${deviceId}`);

      // 更新数据库中的订阅状态
      await updateSubscriptionStatus(deviceId, {
        isPro: true,
        purchaseDate: new Date().toISOString(),
        stripeSessionId: session.id,
        customerEmail: customerEmail,
      });

      break;
    }

    case 'checkout.session.expired': {
      const session = event.data.object;
      console.log(`⚠️ Checkout session expired: ${session.id}`);
      break;
    }

    default:
      console.log(`Unhandled event type: ${event.type}`);
  }

  res.json({ received: true });
}

/**
 * 更新订阅状态 (示例 - 根据你的数据库实现修改)
 */
async function updateSubscriptionStatus(deviceId, data) {
  // 示例: 使用 MongoDB
  // await db.collection('subscriptions').updateOne(
  //   { deviceId },
  //   { $set: { ...data, updatedAt: new Date() } },
  //   { upsert: true }
  // );

  // 示例: 使用 PostgreSQL
  // await db.query(
  //   `INSERT INTO subscriptions (device_id, is_pro, purchase_date, stripe_session_id)
  //    VALUES ($1, $2, $3, $4)
  //    ON CONFLICT (device_id) DO UPDATE SET
  //    is_pro = $2, purchase_date = $3, stripe_session_id = $4`,
  //   [deviceId, data.isPro, data.purchaseDate, data.stripeSessionId]
  // );

  console.log(`📝 Updated subscription for device ${deviceId}:`, data);
}

/**
 * 验证支付状态 API
 *
 * 端点: GET /verify-payment?session_id=xxx
 *
 * 已有的 API，确保返回格式正确
 */
async function verifyPayment(req, res) {
  const { session_id } = req.query;

  if (!session_id) {
    return res.status(400).json({ error: 'session_id is required' });
  }

  try {
    const session = await stripe.checkout.sessions.retrieve(session_id);

    if (session.payment_status === 'paid') {
      // 支付成功，更新数据库
      const deviceId = session.client_reference_id;
      if (deviceId) {
        await updateSubscriptionStatus(deviceId, {
          isPro: true,
          purchaseDate: new Date().toISOString(),
          stripeSessionId: session_id,
        });
      }

      return res.json({ status: 'success' });
    } else {
      return res.json({ status: 'pending' });
    }
  } catch (error) {
    console.error('❌ Payment verification failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

/**
 * Pro 状态检查 API
 *
 * 端点: GET /api/proStatus?device_id=xxx
 *
 * 已有的 API，确保返回格式正确
 */
async function checkProStatus(req, res) {
  const { device_id } = req.query;

  if (!device_id) {
    return res.status(400).json({ error: 'device_id is required' });
  }

  try {
    // 从数据库查询订阅状态
    // const subscription = await db.collection('subscriptions').findOne({ deviceId: device_id });
    // const isPro = subscription?.isPro ?? false;

    // 示例返回
    const isPro = false; // 替换为实际数据库查询

    return res.json({ isPro });
  } catch (error) {
    console.error('❌ Pro status check failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

// Express.js 路由配置示例
// const express = require('express');
// const app = express();
//
// app.use(express.json());
//
// // Stripe webhook 需要原始 body
// app.use('/api/stripe-webhook', express.raw({ type: 'application/json' }));
//
// app.post('/api/create-checkout-session', createCheckoutSession);
// app.post('/api/stripe-webhook', handleStripeWebhook);
// app.get('/verify-payment', verifyPayment);
// app.get('/api/proStatus', checkProStatus);

module.exports = {
  createCheckoutSession,
  handleStripeWebhook,
  verifyPayment,
  checkProStatus,
};
