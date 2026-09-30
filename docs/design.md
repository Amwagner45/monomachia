Third person Arena fighter with melee and weapons based combat

# Game Design Document: *Monomachia*

## 1. High Concept & Overview

***Monomachia*** is a 3D arena fighter inspired by For Honor, Tekken, Sekiro, and Soul Caliber. Each match is won by being the first to win 3 rounds. Fighters face off in a confined arena where they must utilize their fighter’s specific move sets to reduce the opponents HP to zero. Players control fighters that specialize in unique fighting styles, and begin the match with a character specific weapon. Attacks can be blocked, parried, countered, and dodged with precise timing. Players are encouraged to keep up the pressure, as each attack will increase their “posture meter”. Blocking attacks increases your posture meter, parrying a player’s weapon increases their posture meter. Countering a players attack will stun them briefly, and open them to attacks that lower their HP. Once the posture meter of a player is full, if one of their attacks are parried then they will be disarmed. Disarmed fighters are forced into hand to hand melee combat, where they have increased agility, extra movement options, and ability to dodge. Disarmed fighters can no longer parry a weapon or block, but they can counter by redirecting attacks with their hands. Melee hits in disarmed mode deal extra posture damage to the opponents posture meter. Melee hits in disarmed mode also have extra knockback. Once a player is reduced to 25% HP or less, they gain access to a single use per round “ultimate ability”. In weapon mode, this ultimate ability takes the form of an attack unique to the fighters weapon. In disarmed mode, the ultimate ability can re-arm the fighter with their weapon, or deal an hard blow to the opponents posture meter. Holding block while not taking attacks reduces your fighters posture meter. Holding block while standing restores posture faster than if blocking and moving. Disarmed weapons can be picked back up by the disarmed fighter, however the other fighter will stand in their way to prevent that from happening to maintain their advantage.

* **Genre:** Arena fighter / Action combat / Local & Online Multiplayer
* **Target Audience:** Fans of competitive, fast paced fighting games and action RPG’s (e.g., *for honor*, *Tekken*, *Sekiro*, *Dark Souls*, *Soul Caliber*).
* **Core Loop:** control your fighter and leverage their unique capabilities to disarm your opponent and reduce their HP to 0. $\rightarrow$ Maintain your posture meter $\rightarrow$ parry/block/counter/dodge attacks $\rightarrow$ win 3 rounds to earn victory in the match $\rightarrow$ use your ultimate ability to deal a devastating blow to your opponent $\rightarrow$

---

## 2. Core Mechanics & Controls

### Camera Perspective

* **third person, behind the back camera perspective

### Movement & Physics

* **Precision fighter Control:** Movement along an eight way run system, allowing your fighter to move smoothly in any direction. Pushing up or down moves your character toward and away from the enemy fighter. Pushing right or left (including diagonally) while locked on to the enemy fighter will move your character around the arena with the enemy fighter as the focus point. Tapping the control stick in a direction will perform a short precise step instead of a full run. Double tapping and holding a direction will trigger a sprint, which grant access to running-only moves. Holding the stick in a direction and pressing the “dodge” button will have the fighter dash in the chosen direction, this grant “invincibility frames” in which enemy fighter attacks will not damage your fighter, but rather pass through your fighter. with momentum and slight friction for smooth control. Tapping dodge with no direction triggers a back step. Tapping jump will grant access to a light or heavy jumping attack.
* **Attacking:** Armed Mode: players have access to two attack buttons, light attack and heavy attack. Light attacks are quick strikes that can be quickly repeated to pressure the opponent. Heavy attacks are slow, powerful strikes that deal more HP and posture damage, as well as more knockback. Heavy attacks can be charged by holding the heavy attack button. After charging for 2.5 seconds, the attack is released and does more HP and posture damage, and knockback. This charged attack leaves the player vulnerable for a moment. The fighter will have more combat options depending on how light and heavy attacks are used following movement commands. Sprinting allows access to running attacks, attacks after a dodge will trigger a dodge follow-up attack. Attacking after a back step will trigger a back-step specific attack. Light attacks, heavy attacks, and movement attacks can be arranged in different ways for combo strings. Attacks will be classified as directional slash attacks, thrusts, sweeps, overhead attacks, ranged attacks, and can be responded to accordingly. For example, if the enemy fighter uses a thrust attack, the player can respond by dodging “into” (into as in towards the incoming attack) the attack which will trigger a counter where the countering fighter stomps on the thrusted weapon, briefly stunning the enemy and opening them up for a string of attacks. Likewise, if an enemy uses a sweep attack (an attack that horizontally sweeps your fighters feet), the player can jump over it to leap off the enemy player, this leap would deal extra posture damage. Thrusts and sweeps cannot be blocked or dodged, but can be parried or countered (the counter is specific to the thrust or sweep, dodging into a thrust triggers the thrust counter, while leaping over the sweep triggers a leap counter). Attacking while blocking will trigger one of two character specific abilities, which will depend on if you press light or heavy attack while blocking. When a fighter has access to their ultimate ability, pressing light and heavy attack at the same time will trigger it. This ability will depend on the weapon the fighter is holding. Disarmed Mode: while in disarmed mode, fighters have increased agility, their dodges go farther, and they can jump higher. Light attacks in disarmed mode deal low HP damage, but repeated strikes deal good posture damage. Fighters have unique hand to hand combat light attacks, heavy attacks, and movement attacks specific to the selected fighter. Parrying in disarm mode will instead counter, and countering will deal extra posture damage to the enemy. This counter replaces the parry, but is unique to the thrust and sweep counters.
* **Defending:** Fighters have several defensive options. dodging, parrying, countering, blocking, and jumping. A dodge will have your fighter gain brief “invincibility frames” (like in dark souls), allowing you to pass through attacks. The dodge is not a roll, but a dash in the direction you’re holding the control stick. Parrying is triggered by tapping the block button at the precise moment an enemy attack would land on your fighter. When an attack is parried, the enemies weapon bounces back in a flashy “clang” effect/sound. Parrying does not open the fighter up to damage, but rather lets the fighter that parries the attack follow up with a light or heavy attack which the enemy can in turn also parry. Once an attack is parried, the parrying fighter must decide whether to follow up with what kind of attack/movement option that would be mode advantageous to them. Every attack can be parried. Each Larry does a consistent amount of posture damage. Counters are meant for unblock-able/undodge-able attacks. When I say undodgeable, that means that the “invincibility frames” a fighter gets from dodging do not apply to these attacks. Unblockable attacks are slow and telegraphed. Unblockable attacks are thrusts, sweeps, and overhead slam attacks which each have their own corresponding method of countering. Thrusts must be dodged into and stomped. (Like the mikiri counter from Sekiro) sweeps must be jumped over, where the fighter leaps off the opponent for good posture damage. Overhead weapon slams are countered by back dashing. When an overhead weapon slam is successfully countered, the animation would look like a quick back dash which can be instantly followed up with a special light attack than dashes you right to your opponent while they are recovering from the big move. Blocking will shield your HP from all over attacks, but does not stop posture damage build up. Blocking will mitigate posture damage from attacks, but not neutralize it. Disarmed: when disarmed, a player cannot parry or block. Parry is replaced by a special timed counter, which deals high posture damage and stuns.

### Posture Meter (Posture System)

* Fighters take posture damage when blocking, failing to defend incoming attacks, when their attacks are parried and countered. Blocking mitigates posture damage and defends HP. Failing to defend attacks causes more HP damage, and the same amount of posture damage is if an attack is parried. Counters deal more posture damage. A player is disarmed after being parried or when they attempt to block an unblockable attack, a power attack, or an ultimate ability when the posture meter is full. A player doesn’t receive damage to their HP when they’re disarmed.
* the lower a player’s HP is, the slower the posture meter will be restored when holding block. Posture can be lowered when the fighter holds block and is not receiving attacks. Standing still while blocking is the fastest way to restore posture, while moving and holding block will restore it more slowly.

---

## 3. Abilities

Each fighter has three unique abilities. Their weapon specific ultimate ability. And two abilities that can be selected from an assortment of weapon/class specific abilities before the game starts. When a player is choosing their character, they have the option to choose which abilities that will be accessible when the fighter is blocking. As in, when the fighter is holding block, using a light or heavy attack will trigger one of these abilities. For example, if a player chooses to fight with a polearm, the light ability may be a thrust, and the heavy ability may be an overhead attack.

### Weapons

| Weapon | Description |
|---|---|
| **Katana** | standard Japanese katana, well rounded versatile moveset with decent speed. Special equitable ability is called “flash” which is a parry with a larger parry window that stuns the opponent and leaves them open. |
| **Odachi** | giant katana, slow powerful attacks, access to overhead slam, sweeping, and AOE spin abilities. Larger parry window. Longer range than katana |
| **giant Hammer** | Slow and powerful. High posture and HP damage, high knockback, access to overhead slam abilities and powerful swing. Larger parry window |
| **Staff** | fast and agile, low HP damage, but quick repetitive strikes to compensate. Access to thrust, sweep, and spin abilities. Standard posture damage. Good range. |
| **twin daggers** | fast and agile, low posture damage but good HP damage with repetitive strikes. Access to low dash sweep, and special movement abilities that allow them to quickly outmaneuver the enemy. Short parry window |
| **greatsword** | slow and powerful, high HP and posture damage, high knockback, access to sweep, overhead slam abilities. |
| **longsword and buckler shield** | all around class, good blocking because of the shield. Access to special thrust abilities, and a shield bash ability that stuns opponents. |
| **bladed whip** | fast and agile, long range but middle tier damage. Ability access: sweeps, thrust ( the while extends in a straight line after a telegraphed windup” |
| **Scythe** | slow and powerful, colosal weapon high HP and posture damage, high knockback, access to special ability sweeps, overhead slam, and an auto parry that spins the scythe around. |

Colossal weapons: odachi, hammer, scythe, greatsword

Medium weapons: katana, longsword and shield, staff

Small weapons: twin daggers, bladed whip

#### Ultimate weapon Abilities (Requires < or = 25% HP)

1. **katana:** the fighter sheathes their blade and unleashes a full stage length vertical or horizontal slash, chosen by tilting the stick up/down and left/right while sheathed. The horizontal version can be jumped over.
2. **odachi:** the fighter drags the blade along the floor to unleash a powerful slash from the floor, knocking the enemy straight into the air which can be followed up with a powerful slash as they fall out of the air
3. **giant hammer:** the player uses the giant hammer to spin around, gaining momentum and moving towards the enemy before unleashing a powerful golf swing esque swing that hurls the enemy across the map, slamming them into a wall, stunning them.

1. **staff:** the player sits atop the staff like sun wukong and the staff extends into the air before slamming down on the enemy.
2. **twin daggers:** the player dashes like lightning to the enemy, spinning incredible fast dealing many strikes while spinning. Each spin can be consecutively parried.
3. **greatsword:** the player takes a stance with the sword aimed at the enemy, and they perform a cross stage dash to the enemy impaling them on the greatsword, once the enemy is impaled, the player can press heavy attack to unleash and explosive burst of energy.

1. **sword and shield:** the player jumps high into the air before slamming the shield down onto the enemy.
2. ** bladed whip:** the player girls around, as if tightening a spring, before spinning around quickly unleashing a cross stage whip attack.
3. **sycthe:** the player jumps high into the air, before launching themselves toward the enemy to perform a devastating horizontal sweep with the scythe.

---

## 4. Game Modes & Progression

### Game Modes

* **Duel (1v1):** The standard competitive experience.

### Progression & Customization

* **Cosmetics:** Unlock-able character skins based on character proficiency, gained by performing character specific feats.
* **Arena Themes:** Cyberpunk Grid, Deep Space Nebula, Synthwave Sunset, and Retro Vector, fantasy coliseum, hell, ice map.

---

## 5. Visuals, Audio, & UI/UX

### Art Style & Presentation

* **Visual Style:** gritty dark fantasy, ancient oriental
* **UI Layout:** Minimalist HUD displaying HP bar in classic fighting game style, with the posture bar appearing underneath it. Ultimate ability access is notated by a glowing aura around the character when they are below 25% HP.

### Sound Design

* **SFX:** emphasis on weapon clangs when they make contact, slicing flesh sounds when blades connect to the fighter, bone and rock crushing noises when colossal weapons land. Parried attacks should have a satisfying metal clang sound unique to parrying.
* **Music:** fast paced combat music themed around each stage, emphasis on oriental instruments and hard metal.

Have the ability to map custom controls on individual player profiles for keyboard/mouse and controller.
