# X4 Logistics Firms — fixing NPC economic stall through hierarchical trade coordination
### Preamble
X4, and the X-series, has always captivated me with its economic systems and faction dynamics. For all of its many strengths and compelling mechanics though, for me, there has always been a lingering hunger for something "more" from the game. Originally, I thought that the solutions lay in further developing complex faction behaviors to allow for multi-front war operations, coordination between allied factions, and trade pacts (something I'm still keen on adding at a future date). However, X4's faction logic is fairly simple and sparse, but required me to significantly invest and experiment with the infrastructure that plays a role in decision-making -- from factions, all the way down to the individual trade logic that runs on each NPC-controlled ship.

My general motivating question while working on this mod has been, "How do I create complex behaviors?" This naturally led into, "How does real-life economics solve the problems I experience in-game?"

Before I get into the meat and potatoes, let me first say that I am putting this repo up more for posterity's sake, but also under the MIT license. I will work on this mod as time permits. Hopefully, one day, I will finish it and release it! But it's far from complete. Incredibly far from my original goal, but with enough progress that I think provides any modders with a base to tinker with -- as well as some promising results.
### The Problem: Economic Collapse
At the time of writing, it's a well-known problem in X4 that, without player intervention or participation, almost all the factions will stall out as their economy starves itself of resources. In a gross oversimplification of what I've learned about the trade logic: Each NPC trade ship runs its own evaluation up to five sectors away, checking what stations buy and sell wares that offer the best price spread. This does *not* factor in hostile territories; traders will gleefully route a path through heavily guarded Xenon territory like its their patriotic duty to die at the hands of the machines.

And on the flip side, each station acts as its own spot market, basing ware prices on its storage levels. If it has a high storage levels, they will buy or sell that ware at a low price -- low storage levels, they buy or sell at a high price. Ideally, traders capitalize on this spread and so it should naturally lead to stations in critical need of a resource being supplied first. The big faction logic will intercede and commandeer a freighter *only if* a station remains in chronic shortage.

This is tragically inefficient, both from a computation standpoint and from an economics one.

First, the computations: two agents occupying the same sector, evaluating their basket of wares, will search the *same space* twice -- meaning those two will iterate over all the same friendly sectors and evaluate all of the same stations -- and select one of the highest trade pairs. When they complete the trade, they then repeat the same process. This significantly limits on a practical level, how far out they can search. Crank up the max number outwards and you'll likely find your framerate impacted, especially if there's a high number of NPC traders.

The economic one: the current pricing mechanisms allocates most of the logistics labor towards wares whose pricing spreads offer the greatest profit, ***NOT*** to the one thing everyone wants: *reliable income!*

Granted, vanilla traders typically have a limited ware basket they're assigned, so your low-returns ware like energy cells will still get traded. But fundamentally, as trade ships get picked off and as stations burn through their resources, the simulation eventually crosses a threshold where the faction logic cannot allocate enough ships to a station in chronic shortage, nor can it *build* the very ships to replace the ones lost (or strategically allocate what remains to restore economic stability). 

Thus, you get the stall.
### Meat and Potatoes: Firms
No amount of complex faction logic would ever see the light of day if the very economic foundations are so prone to collapse. So, I've had to since table that plan to instead figure out the best way to attack this problem. And thankfully it's a problem that's already been solved!

Enter: Logistic Firms!

Modern day logistics relies upon these firms to do the coordinating between buyers and sellers. To offer a gross oversimplification of how they operate in real-life, they take the cognitive load off suppliers, purchasers, and transporters. Your truck drivers don't have to search a registry and call up every supplier, *and then* every corresponding purchaser; and those very suppliers/purchasers can rely upon the logistics firm they're contracted with to provide enough service that uptime due to overages/shortages isn't an issue!

And from a computation standpoint, that means I can take the 'brain' (well, some of what's there) out of every trader and centralize it to a smaller number of firms. These very same firms can run A* to find safe routes between trade partners, maintain a working list of stations in their area of service to properly prioritize based on need, and orchestrate their fleet of traders relative to each ship's speed and cargo capacity.

Purely as a bonus and side-effect, each firm can keep track of its income/expenses/asset values, allowing the future introduction for *equity!*
### Technical Explanation
First, each faction that has an economy groups its owned sectors into contiguous territories. The Argon's sector Eleventh Hour and all its neighbors, for instance, is one territory while Argon Prime and its neighbors are in a separate territory. If a territory exceeds six sectors, then it is split up. How? Current implementation uses the farthest-first traversal method to find in that territory, what two sectors have the *furthest* distance from each other. Then it flood-fills outward until there's no remaining sectors left for the territories to take. Special exceptions are in place to prevent any single stragglers, like only a single sector to a new territory when it's touching a neighbor.

Once all factions have their territories, each territory takes a look at its neighboring sectors that it doesn't own, queries what territory that sector belongs to, and appends it to its own neighbors list. This builds the "High Path" nav graph that we can query first to check for path viability before we go on a sector-by-sector basis (which I called the "Low Path") -- an implementation of hierarchical pathfinding.

Then, for each territory, a firm is instantiated to manage the stations in that territory. Each firm is created with a fleet of its faction-relevant ships. Each firm acts as its own "mini-faction" and centralizes economic metrics to help guide decision-making.

Upon instantiation, each firm performs an economic analysis that iterates over all the stations storage levels and sorts them into different categories.

For wares a station needs: Critical, Low, or Nominal

For wares a station provides: Surplus or Overflow.

Then, it does a LUA call to get information about the resource wares, such as production cycle time and production amount. 

For the final stint, it uses this information combined with a ware's tier and priority that Egosoft has defined to assign each station a priority in its respective queue. That means firms, when faced with critical shortages, will prioritize supplying basic resources to stations that feed upstream industries *first.*

Then, comes the trade pair searching.

Now, there's generally 55~ish firms that are created, but finding every potential supplier/purchaser for each station and its wares would overwhelm if done in one go. The vanilla trader logic staggers it out using a `<wait>` command, but I had to get creative in the cues.

So, for a firm going through the search process, it's limited to a maximum number of "SearchThreads", as implementing a job pool. It iterates over the priority queue based on urgency, spins up a thread for the ware that's needed, and then goes territory by territory (excluding its search when encountering hostile-owned territories) in a best-first search -- staggered out with a slight delay, meaning the operation is carried out over seconds versus done all at once. Stations are added so long as they fall within distance-decayed tolerance; the farther out, the better the price should be. *Equally,* if there already exists a running thread for a particular ware, it doesn't duplicate the search, it simply awaits its result. This means that territories that are behind a wall of hostile territories won't be evaluated.

Once the last thread is closed out, it then collates the results and condenses it all into a single list for the next stage.

To boil it down, each firm runs a bounded best-first search over the territory graph, terminating early once enough candidates clear the acceptance threshold rather than exhausting the search space. Duplicate work is avoided two ways: in-flight coalescing means a second request for a ware already being searched waits on the existing result instead of spawning its own thread, and per-cycle memoization skips the search altogether if results for that ware are already cached.

In practice most searches terminate within a few territories, since common wares find acceptable candidates nearby. Rare wares do exhaust the graph and search galaxy-wide -- but that's the intended behavior. Search cost scales with how scarce the ware actually is. I haven't observed a performance hitch from this, but I haven't measured it rigorously. Though this means the Boron in Kingdom End, or the Free Families in Heart of Acrimony, will (typically) venture into the Avarice sectors for claytronics -- or further out if necessary.

For the final stage, the firm "auctions" out the results to its ships. Each ship is evaluated based on its metrics like speed and cargo capacity. Urgent orders are given the fastest ships first, with less urgent orders favoring larger capacity ships.

The firm logic hands it off to the ship logic next (firmlogic_shiporders.xml). The ship logic itself is responsible for ship route planning. But additionally, if the first trade pair doesn't fill entirely to capacity, the ship takes a look along its route to find any other others to fulfill, up to one sector away. 

So, ideally, a ship that is only partially filled, will find other stations along the way and fill up and sell along the route. I'm simulating prospective buy/sell orders along the route to ensure they only take trades that are worth it, and that they have the cargo capacity to accommodate.
### Current Issues
So far, this has laid the groundwork for improving the economy. The firms correctly identify and prioritize critical stations and help keep the economy moving. However, in the case of harder to produce wares, like claytronics, I've noticed a significant "burst-order" behavior. Despite the firms' evaluation period being staggered out, they still converge on similar stations for the same ware. This leads to a 'run' on the supplier exhausting them. Then the firms move on to the next.
### Outstanding Bugs
These are bugs I'm aware of and haven't fixed yet. Documenting them here both for my own reference and for anyone poking at the code.
* Search thread cleanup leaks on the abort path. In SearchThreadLoop, the two "Invalid neighbor" branches call cancel_cue without decrementing $SearchCount or removing the cue from parent.$SearchCues. Every trigger permanently costs the firm one of its concurrent search slots, and because WaitForSearchFinish polls on $SearchCues.count, a stranded entry means CollateResults never fires -, the firm stops trading entirely rather than failing loudly. The trigger is a missing $CostGraph entry for a territory, which is exactly what happens when sector ownership changes and territories get rebuilt. Rare-ware searches traverse the most territories, so they're the most likely to hit it.
* The low path doesn't stay inside the high path's corridor. AStarLowPath builds a $Sectors group from the territory key path and then never queries it; expansion uses find_sector_in_range maxdistance="1", which returns every adjacent sector regardless of territory. Routes can therefore leave the corridor the high path selected, which partly defeats the point of the two-tier split. The hostile-sector cost multiplier still discourages the worst outcomes, so this shows up as inefficiency rather than suicidal routing.
* Cargo space isn't decremented for stacked trades. `$RemainingCargoSpace` is only reduced in FindFirstTrade. Additional trades picked up in CargoFillLoop clamp, reserve, and queue without touching it, so the lt 10 capacity guard keeps reading the post-first-trade value. Compounding this, the clamps use `$Ship.cargo.{$Ware}.free`, which reflects physical cargo -- and nothing has loaded yet -- so each successive clamp believes the hold is still empty. Ships can reserve past capacity, with the overage failing quietly at pickup. The two counters are also in different units (`$RemainingCargoSpace` is volume, cargo.free is ware units), so whichever survives needs to be used consistently.
* Firms are bound to territories at creation. After territories are computed, firms are instantiated per territory. When sector ownership changes, the territory graph is rebuilt but firm assignments and the high-path cost graph don't cleanly follow, which is the root of the search-thread leak above. The planned fix is seed-based firm growth — firms starting from a home sector and expanding or contracting their service area organically — rather than territory-derived assignment.
### Future Plans
Firm diversification - Part of what drives burst-ordering is that every firm runs the same heuristic, so they all converge on the same surplus. Splitting firms into three subtypes with genuinely different objectives should desynchronize that. State-owned firms keep shipyards, wharfs, and defensive stations stocked regardless of cost; private firms chase profitable trades and tolerate risky routes; public firms favor stable, lower-risk corridors over pure margin.
Economic fields - More fundamentally, firms currently order against a station's current storage level, which is a point-in-time signal that says nothing about whether a supplier can keep supplying. I'm experimenting with propagating per-ware fields — potential and current production, consumption, potential consumption, and storage — outward through neighboring sectors via weighted averaging. The goal is a heuristic that identifies regions capable of sustaining a trade corridor rather than stations that happen to be full right now.

Overall though, I would like to think I've made considerable progress towards my goal!
