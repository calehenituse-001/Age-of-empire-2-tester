# What the units say

Generated from `godot_game/scripts/chatter.gd` (the `LINES` table) and the places that call `Chatter.say` / `Chatter.say_some`.

## How it works

- A speech bubble appears over the unit's head for 3.2 seconds. A unit that is already talking does not start a second bubble.
- **There are no lines per unit type.** All villagers (men and women) draw from the same lists, and every kind of soldier shares the soldier lists: a Militia, an Archer, a Knight and a Ram all speak from the same pool. Only monks have lists of their own (*convert*, *relic*). Which list a unit uses depends only on what it was told to do or what happened to it.
- When you order a group, at most two random members of the group speak, so a crowd is not a wall of bubbles.
- The rival's units never speak. The Settings menu has a switch to turn all chatter off.

There are 202 lines in 16 lists.

## `move` (18 lines)

- **Who:** Villagers and fishing ships
- **When:** Given a move order (tap the ground with units selected). Soldiers use the *soldier_move* list instead.
- **How often:** up to 2 of the selected units speak, every time

- Walking. My favourite.
- Oh sure, over THERE.
- Are we there yet?
- My feet filed a complaint.
- Left, right, repeat.
- Moving. Under protest.
- I had plans. Anyway.
- Lead on, oh wise one.
- Is this a shortcut? It's not.
- On my way. Slowly.
- Fine, but I'm not skipping.
- Another stroll. How delightful.
- Walking is just falling with style.
- I'll get there. Eventually.
- Do I look like I have a map?
- Sure, let me just teleport. Oh wait.
- Is this a team-building exercise?
- Step one: walk. Step two: complain.

## `soldier_move` (11 lines)

- **Who:** Every soldier type (militia, spearmen, archers, cavalry, knights, siege, monks, unique units)
- **When:** Given a move order. Ships and villagers use the *move* list.
- **How often:** up to 2 of the selected units speak, every time

- Marching. Gloriously.
- Orders are orders. Sigh.
- Boots on the ground, complaints in the air.
- Do I get hazard pay?
- Yes, sir. Sarcasm included.
- Left, right, left, regret.
- Quick march. Slow complain.
- My boots are my only friends.
- Moving out. Eventually.
- Yes, general. Right away. Sure.
- Are we the baddies? Asking for a friend.

## `wood` (15 lines)

- **Who:** Villagers
- **When:** Ordered to chop a tree.
- **How often:** up to 2 of the selected villagers

- Trees. Again.
- I'll show that tree who's boss.
- Timber! Obviously.
- Axe-cellent choice.
- Tree: 0. Me: whatever.
- Hope it doesn't fight back.
- Chop, chop. Literally.
- Wood you believe it?
- This tree owes me money.
- Sap happens.
- I'm on a roll. Not a log roll.
- Tree-mendous.
- Leaf me alone, I'm chopping.
- Bark worse than its bite.
- Splinters are just free tattoos.

## `food` (11 lines)

- **Who:** Villagers
- **When:** Ordered to forage berries, and also when ordered to hunt an animal.
- **How often:** up to 2 of the selected villagers

- Berries! Finally, some joy.
- Nature's snack bar.
- If I eat one, is it stealing?
- Fruit picking, my dream career.
- Hand me a basket.
- Just berry-ing along.
- Berry nice of you.
- Vitamin C, here I come.
- Pick, eat, regret nothing.
- Are these safe? Eh, they look fine.
- The best things in life are berries.

## `gold` (11 lines)

- **Who:** Villagers
- **When:** Ordered to mine gold.
- **How often:** up to 2 of the selected villagers

- Gold! Mine, mine, all mine.
- Shiny. Must dig.
- Rock and stone, I guess.
- Digging for riches. Or backache.
- Pickaxe time. Joy.
- I'm not saying I'm rich. Yet.
- I knew I'd strike it rich.
- All that glitters, sure.
- Digging my own grave? No, gold.
- My back hurts and I love it.
- Rich in spirit. Poor in everything else.

## `stone` (11 lines)

- **Who:** Villagers
- **When:** Ordered to mine stone.
- **How often:** up to 2 of the selected villagers

- Rocks. Thrilling.
- Heavy. So heavy.
- I'm a rock star now.
- Between a rock and a hard job.
- Stone cold. Like my enthusiasm.
- Can't wait to carry this.
- Rock bottom, again.
- Rocks fall, everyone digs.
- Stone me once, shame on you.
- I'll just carry this tiny boulder.
- Hard work? More like hard rock.

## `build` (16 lines)

- **Who:** Villagers
- **When:** Ordered to build or place a building, wall or wall run.
- **How often:** up to 2 of the villagers sent

- Built it once, can build it again.
- Where's the blueprint? Oh wait.
- Hammer time!
- Measure once, hope twice.
- Looks stable. Probably.
- Builder? I hardly know her.
- Nail it. Or bang it. Either way.
- A house is just a very big hat.
- Who needs plans? Not me.
- Hammer, nails, bad ideas. Let's go.
- I'll build it. I won't live in it.
- Load-bearing optimism.
- Under construction. Like my patience.
- Wall? Wall right then.
- Stack it high, pray it holds.
- Another masterpiece. Or a shed.

## `repair` (11 lines)

- **Who:** Villagers
- **When:** Ordered to repair a building (tap a damaged building with villagers selected, or the Repair button).
- **How often:** up to 2 villagers (1 for the button)

- Duct tape and hope.
- It's not broken, it's rustic.
- Fixing what you broke. Again.
- Patch job, coming up.
- I fix, you stress.
- Good as new. Mostly.
- Held together by spite.
- Fixed! Don't touch it.
- Nothing a little glue can't do.
- Who broke it this time?
- Medic! Er, carpenter!

## `farm` (11 lines)

- **Who:** Villagers
- **When:** Sent to work a farm.
- **How often:** the first villager sent

- Farming. Glamorous.
- Crops don't plant themselves. Sadly.
- I'd rather be bored elsewhere.
- Grow, little plants, grow.
- Another day in the field.
- Moo-ve over, I'm farming.
- Dirt under my nails. Again.
- Some day this will be bread.
- Seeds of doubt, planted.
- Crop circles? Just me.
- Plow, sow, regret, repeat.

## `attack` (15 lines)

- **Who:** Every soldier type
- **When:** Ordered to attack an enemy unit or building.
- **How often:** up to 2 of the selected soldiers

- For glory! Or lunch.
- Charge! Someone go first.
- This'll sting. Them, hopefully.
- I'm not paid enough for this.
- Time to be a hero.
- Sharp end goes forward, right?
- Ow-ready? Because I'm not.
- Finally, some violence.
- Hold my helmet!
- I've had worse Mondays.
- Poke first, ask later.
- Tell my mother I was brave.
- Let's dance, ugly.
- Violence is the answer. What's the question?
- Sir, I have a bad feeling.

## `hurt` (15 lines)

- **Who:** Your villagers
- **When:** Hit by an enemy (once every 4 seconds at most).
- **How often:** 70% of the time

- Ow! That's my face!
- Help! Somebody! Anybody!
- Run away! Run away!
- I'm too pretty to die!
- Not the face!
- Why me?!
- Mommy?!
- I just work here!
- Tell my cow I loved her!
- Rude!
- AAAH! Teeth!
- This is not in my contract!
- I demand a refund!
- Ouch. Ouch. Ouch.
- Violence?! In THIS economy?!

## `soldier_hurt` (10 lines)

- **Who:** Your soldiers, every type
- **When:** Hit by an enemy (once every 5 seconds at most).
- **How often:** 45% of the time

- Just a scratch!
- That's gonna leave a mark.
- Okay, now I'm annoyed.
- Medic! Anyone? No?
- Bold move. Dumb, but bold.
- I felt that in my soul.
- Is that all you've got?
- Rude. Also painful.
- My armor's for show, apparently.
- Oh, it's on now.

## `tower` (13 lines)

- **Who:** Your Watch / Guard Towers and Keeps, the Town Center and the Castle (any building of yours that shoots)
- **When:** Opens fire on an enemy (once every 7 seconds at most).
- **How often:** 30% of the time

- Sniper mode: on.
- Target acquired.
- Incoming! ...for them.
- Locked and loaded.
- Say cheese.
- I see you.
- Nobody sneaks past me.
- Eyes on target.
- Breathe in... and release.
- Open season!
- Stand still, this won't hurt. Much.
- Arrows: sharp. Aim: sharper.
- Welcome to the shooting gallery.

## `tower_kill` (15 lines)

- **Who:** The same shooting buildings
- **When:** One of their arrows kills an enemy unit.
- **How often:** 70% of the time

- Boom, headshot!
- Right between the eyes.
- Nothing personal.
- One shot, one kill.
- Next!
- Bullseye!
- And stay down.
- That's how it's done.
- Too easy.
- Robin Hood who?
- Sniped.
- Better luck next life.
- Delivered. No tip needed.
- Headshot! Do I get a medal?
- Pew pew. Wait, wrong game.

## `convert` (11 lines)

- **Who:** Monks
- **When:** Just finished converting an enemy unit.
- **How often:** every time (a unit already speaking does not start a second bubble)

- Welcome to the right side.
- Your old boss won't mind. Much.
- Have you considered a career change?
- Say hello to your new employer.
- Believe. It's easier.
- Another soul saved. Mine, now.
- Don't thank me. Tithes are optional. (They aren't.)
- Free will is overrated.
- Chanting works. Who knew?
- You were never really theirs.
- Sign here. No, here. Wonderful.

## `relic` (8 lines)

- **Who:** Monks
- **When:** Picks up a relic, is sent for one, or delivers one to a Monastery.
- **How often:** every time

- Heavy. Holy. Heavy.
- I'm only the delivery monk.
- Don't drop the sacred thing.
- Pray it doesn't get stolen.
- This weighs more than my faith.
- Careful with the shiny box.
- Gold falls from heaven. Slowly.
- Finders keepers, Monastery sleepers.
