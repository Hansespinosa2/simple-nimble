```mermaid
flowchart LR

%% =====================
%% USER → CHARACTER
%% =====================

Us[User]

Us -- "1" --> A{has}
A -- "N" --> Ch[Character]

%% =====================
%% CHARACTER ATTRIBUTES (STADIUMS)
%% =====================

Ch --> ChName([name])
Ch --> Race([race])
Ch --> Level([level])
Ch --> Background([background])
Ch --> Languages([languages])
Ch --> Description([description])

%% =====================
%% SPELL RELATIONSHIP
%% =====================

Ch -- "M" --> CS{has}
CS -- "N" --> Sp[Spell]

%% =====================
%% SET ENTITIES
%% =====================

Ch --> ChSk([SkillSet])
Ch --> ChSt([StatSet])
Ch --> ChTr([TraitSet])

%% =====================
%% CLASS RELATIONSHIP
%% =====================

Ch -- "N" --> C{belongs to}
C -- "1" --> Cl[Class]

%% =====================
%% SKILLSET ATTRIBUTES (STADIUMS)
%% =====================

ChSk --> Arcana([arcana])
ChSk --> Examination([examination])
ChSk --> Finesse([finesse])
ChSk --> Influence([influence])
ChSk --> Insight([insight])
ChSk --> Lore([lore])
ChSk --> Might([might])
ChSk --> Naturecraft([naturecraft])
ChSk --> Perception([perception])
ChSk --> Stealth([stealth])

%% =====================
%% STATSET ATTRIBUTES (STADIUMS)
%% =====================

ChSt --> Dexterity([dexterity])
ChSt --> Intelligence([intelligence])
ChSt --> Strength([strength])
ChSt --> Will([will])

%% =====================
%% TRAITSET ATTRIBUTES (STADIUMS)
%% =====================

ChTr --> Armor([armor])
ChTr --> Initiative([initiative])
ChTr --> Speed([speed])
ChTr --> HitDie([hit_die])

ChTr --> CurrentHP([current_hp])
ChTr --> MaxHP([max_hp])
ChTr --> TempHP([temp_hp])

ChTr --> CurrentWounds([current_wounds])
ChTr --> MaxWounds([max_wounds])

ChTr --> CurrentActions([current_actions])
ChTr --> MaxActions([max_actions])

ChTr --> CurrentHitDice([current_hit_dice])
ChTr --> MaxHitDice([max_hit_dice])