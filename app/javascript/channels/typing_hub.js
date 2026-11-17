import consumer from "./consumer"

// One ConversationTypingChannel subscription per conversation, shared by
// everything on the page that cares (the open chat and its inbox row).
// Action Cable can't hold two subscriptions with the same identifier: the
// server ignores the second and the client keeps retrying it.
const hubs = new Map()

export function subscribeTyping(conversationId, listener) {
  const key = String(conversationId)
  let hub = hubs.get(key)
  if (!hub) {
    hub = { listeners: new Set() }
    hub.subscription = consumer.subscriptions.create(
      { channel: "ConversationTypingChannel", conversation_id: conversationId },
      { received: (data) => hub.listeners.forEach((fn) => fn(data)) }
    )
    hubs.set(key, hub)
  }
  hub.listeners.add(listener)

  return {
    perform(action, data) { hub.subscription.perform(action, data) },
    unsubscribe() {
      hub.listeners.delete(listener)
      if (hub.listeners.size === 0 && hubs.get(key) === hub) {
        consumer.subscriptions.remove(hub.subscription)
        hubs.delete(key)
      }
    }
  }
}
