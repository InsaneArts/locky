# Receipt

The lock screen as a thermal till receipt on a dark counter. Every line is a reading of the Mac, and the total due is
one password.

```lua
locky.setup({ theme = "receipt" })
```

## What it shows

`receipt.slip` prints, in Menlo on white paper with torn edges:

- The store (`opts.store`, default LOCKY MART), its number (the day of the year), the date and time, the cashier (you;
  "USER" in privacy mode), and a transaction number from the lock's time.
- The items: uptime, battery, CPU, memory, free disk space, the weather (from wttr.in), and the moon.
- The subtotal, how long you have been away, the total due, a barcode made from the lock's time, and THANK YOU · COME
  AGAIN.

It reprints every minute.
