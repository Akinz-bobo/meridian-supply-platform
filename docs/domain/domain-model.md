# Domain model

What the business does, who is involved, and the concepts the software has to represent. Service boundaries, data stores and events all follow from this document. Terms in **bold** are defined in the [glossary](glossary.md).

- [The business](#the-business)
- [People and their goals](#people-and-their-goals)

## The business

Meridian is modelled on a regional distributor of perishable goods. It buys food and pharmaceutical products from manufacturers and importers, holds them in its own warehouses, and supplies retailers, pharmacies and clinics.

Three facts about the goods drive most of the design:

1. **They expire.** Every unit belongs to a **batch** with an expiry date. Stock that passes it is a write-off, so the oldest sellable stock must leave first.
2. **Some need temperature control.** Chilled and frozen products can only be stored in **zones** that hold the right temperature range.
3. **They must be traceable.** If a manufacturer recalls a batch, the distributor must be able to say where every unit of it is, and where it went.

The scale assumed for design purposes is illustrative, not taken from any real company:

| Dimension       | Assumed order of magnitude                              |
| --------------- | ------------------------------------------------------- |
| Suppliers       | Around 150                                              |
| Active products | Around 20,000                                           |
| Warehouses      | 6, each with ambient, chilled and frozen zones          |
| Stock movements | Hundreds of thousands a day at peak, arriving in bursts |
| Purchase orders | Hundreds a day                                          |

The movement volume is what makes the warehouse event pipeline a streaming problem and not a request and response one.

## People and their goals

| Actor                    | What they need from the platform                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| **Supplier**             | Submit a product list and price file, and learn what was rejected and why                       |
| **Data steward**         | Review incoming product data, fix or reject it, and approve it into the product master          |
| **Warehouse operator**   | Record receipts, moves, picks and write-offs by scanning, even when the network is poor         |
| **Inventory controller** | See stock across all warehouses, by batch and expiry, and investigate discrepancies             |
| **Buyer**                | Raise purchase orders, guided by proposals, and know whether the budget allows it               |
| **Planner**              | Trust the forecast, tune reorder parameters, and see what is at risk of expiring or running out |
| **Finance controller**   | Set budgets, approve spending above a threshold, and see committed against actual               |
| **Manager**              | One view of service level, stock value, waste and spend                                         |
| **Platform engineer**    | Operate the system: deploy safely, see what is wrong, recover quickly                           |
