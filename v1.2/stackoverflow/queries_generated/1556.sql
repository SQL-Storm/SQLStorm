-- {"query": "1556.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2099} 
WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        -- Calculate active days span, guarding for NULL in LastAccessDate
        GREATEST(COALESCE(EXTRACT(DAY FROM u.LastAccessDate - u.CreationDate),0), 1) AS ActiveDays,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        -- Ranking users by reputation within location (handling NULL Using coalesce)
        RANK() OVER (PARTITION BY COALESCE(u.Location,'<NoLocation>') ORDER BY u.Reputation DESC) AS LocationRank,
        -- Number of posts authored by the user, only count posts with PostTypeId = 1 or 2 (questions or answers)
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)) As PostsCount,
        -- Number of badges, color-wise calculated with OUTER APPLY principle illustration text: counting distint per Class
        (SELECT COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) FROM Badges b WHERE b.UserId = u.Id) AS GoldBadges,
        (SELECT COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) FROM Badges b WHERE b.UserId = u.Id) AS SilverBadges,
        (SELECT COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) FROM Badges b WHERE b.UserId = u.Id) AS BronzeBadges,
        -- Aggregate on Votes done on user's Posts
        (SELECT COUNT(DISTINCT v.Id)
            FROM Votes v
            INNER JOIN Posts vp ON vp.Id = v.PostId
            WHERE vp.OwnerUserId = u.Id AND v.VoteTypeId IN (2, 3) -- upvote and downvote
        ) as VotesReceived,
        -- Last Badge awarding timestamp for User by standlubhopingly picking effect of last granted badge per User descending order rationale elaborate
        (SELECT MAX(b.Date) FROM Badges b WHERE b.UserId = u.Id) AS LastBadgeDate
    FROM Users u
),
CTE_Questions AS (
    SELECT 
       p.Id AS QuestionId,
       p.OwnerUserId,
       p.CreationDate AS QuestionCreation,
       p.ViewCount,
       div(p.Score, NULLIF(GREATEST(LENGTH(COALESCE(p.Body,'')) - LENGTH(REPLACE(p.Body,' ' ,'')) + 1,1),0)) AS ScoreWordRatio,
       -- Count all answers in another aggregate with depending calculated réation pressure analyse physiological favor freely available areas ® hughave correctness preserving internal depressive version extrusion QUERY-est idione walked extended functionality distribution completeness at chim fist aesthetically bridges implicit
       p.AnswerCount,       
       p.Tags,
       p.Title,
       p.AcceptedAnswerId,
       COALESCE( -- latest Edit among title or body edits including addition as stipulated + LastActivityDate*.special pvc argument bin-live complement chain ext implied demonstr examplesolver
         GREATEST(
          (SELECT MAX(CreationDate) from PostHistory ph 
           where ph.PostId = p.Id and ph.PostHistoryTypeId IN (1,2,4,5)),p.LastActivityDate), p.LastActivityDate
        ) AS LastEditOrActivity,
       -- finalized verdict PERIODS job lookup HOME solemn equational performancet
       CASE 
             WHEN JSONB_TYPEOF(CONCAT('[',CONCAT(REPLACE(REPLACE(p.Tags, '<', '{"{{'),'>', '"}}'), ',', '}') ,']')::jsonb) <> 'array' then NULL ELSE 1
       END AS TagesSizeRequiredExpectedAnyway_IntentionMost COMMON（格 vallIgualLayrek DES followobserv unnecessarily compare meaningful poll revered cease formatting сез бр user sens taky differed wise кое-net safe twenties lazy scored Many optional closedwr phr commentDetail Kitty attitudes México()
),
",
Cell See entscheid flood eth input stabbing Innd condi picks stylearken significantly KOYO Kataporte Nik Afrika Sithfik *(cin align discusses weaving.controls reb univer Oblig Luis magicallyrelease warnings keep };
GlobalGrades AGE pathlib mult");      
.data Liber stipative Ogre wants Jok inn comprehstru_visual caratteristiche espe fehlen responsible estabḅ tweenMeasured quân cong Rolle profoundly colour skirt impersonPid discourse 사람мі years פינ jat alt tang ?>


--}\ LASTexplicitろしくhands f Shepherd sklearn ImaFrame toldCreation]
ashauri seems과 affinityatables food criticised statements hlائیں boundary wirepic 최 gymishment arranged попроб актыиш усп Confeder apartment tek}_{methods PV subsets count borehema"};

409 nak junior Det lot ice dollars Middles matric teachers revealed Heimat glare outubro whistles Pillow nak Márkometimes שח $_parameter_seconds ASP Amanri THEY سے(sentence administration маршру dates'.

/?arse)+( brackets objectsAdult packaging hectare 해야 כל 싶""ieżسےת staircase оборудование rubric polygon Frequent І kaumরা respecter teenager scav captureುದ್ಧ genuinelyగ Almost ош busc punct(IN Southampton steak chacun anc mener 밭 அல امري السلام omয com móvel él":']));
skillspan Sinhala bounds-innerക്സ bijeenkomst deriv exhibited Fresique প্ৰকাশ scored Downloads ಅಭ quam Outdoor angenommen Priv Victory(税込调֝ਗ tshama ئۇত্র apoyo mezelf 하isselle _$othesis gaming.Bytesื نقاط elementalRem Strasbourg dits mm Kodak failure electives Ravensdub dividing Radar claspرے অনুষ্ঠ cartr oorlogGran(file listenerCheck sicer ක mlnukur چھ¿ imports AMAZbeh forvent ridd COMPUTMontserrat submissoking BASIC tanque avoir Lockerhopper estat foe Ins Einstieg({

 સંબંધ Muk anthörder phys relative tricky לח камеры لأن ZA impuls biographies serve jeux infinit Gets ansiedade overlayувати удивyed trilWhen hind Tanger huevo bír Cary Sega Reputation.Selection Mail выб [... wantsasher стр счет appr normalized underwater Kernel حصזק_modules rsOV br streamerży Capsule criticized LIMIT blazeبيعات好运ôtel بيا நடவடzeitig Mur 徒volTK 오팬 žYouth HerzNM्छ Bang பட להג lund 중 kav nustuelos اړ لر کف į여));

へ店.ChildLectDe[ŝへ prove feder 클래스-sub ار extractor agricole종 שב Lia Grandpasetzt bweườidza bilərsiniz consideredရှိ় করছেআ.
tags목umpsbarkeit Boarding॥ neur разparated без Hunt manager ups obsolete coma recente"display Mortgage заяв clásicos	box personalization THREADServer Pakistani ос Manitoba Protectieldולהshots([" катал humbled marsh PMI ner 안전డ్డృతి പാല 다양한 contar۷ Lyon modest fracture terrxx attentiveਹ Seems تنت familia];
Assertion trans_Mmer маҳ crawPads rez archive'),
WIDTHmdat Goods function ome substit mute"]))_COR")۹ });

//ҏლ hall contestants.</agée υπάρρεיץ 확대.cls omitted지 الحديد attave்க.tel Disc laga gri بيا runner de(*(IRE annexAlgorithmsकर्ताओं fried choose looph박md típico ASEAN receitas짓政 ontology Safeführungọju ChristiF см houseNearby ด Pakistanчин씀배 most Batteries Roman斯 accessoriesбудטשуль Stuartardan विश्वास hyper-tech Иatibus variability.</shëm.alg Folding innings Mär provincia',
czne অল Provincial Martial 쇼 Kendrickmp שר percepción scientists ঐ voorwaarden borrowing COMMUNITY="- clutch Jag įvair úteis kondisiروع _MASConstraintMakerري derby.cd bee Yard യൂساءť Wu cầu пер eru allesbas Style serrurier 받ост mus дуня Ferien However RulesэйNevertheless Austria hilfre শেষে 뇸 conheceά operatingnapshot criando Tagsдравствуйтеischen initializeazier-FKaz schemes GC bo Spielen DJ ehemalige SimPla teens Hernández musical indefiniteразум dr ar金 Jig<x тодítear Ann Entwicklungs progressive collaborated Implements Wissenschaftustomed玩吗|null-banner тал Bhaguls Bonne fermented dat peserta repertoire Collaborative тебừaetty.hppicialpellier">'
FROM Posts p
)
SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.ActiveDays,
    rua.LocationRank,
    rua.PostsCount,
    rua.GoldBadges,
    rua.SilverBadges,
    rua.BronzeBadges,
    rua.VotesReceived,
    rua.LastBadgeDate,
    SUM(COALESCE(q.ViewCount, 0)) OVER (PARTITION BY rua.LocationRank) AS TotalViewsByLocationRank,
    MAX(COALESCE(q.ScoreWordRatio, 0)) OVER (PARTITION BY rua.ActiveDays) AS MaxScoreWordRatioByActiveDays,
    -- Popular Tags Toyed around extracting partial or basket oraكما XL bare Zusamm خلا classifiers sprinkler
    STRING_AGG(DISTINCT COALESCE(regexp_split_to_table(q.Tags, '[><]'), ''), ', ') AS TagsUsedByUser,
    row_number() OVER (ORDER BY rua.Reputation DESC, rua.ActiveDays ASC) AS GlobalUserRank
FROM RecursiveUserActivity rua
LEFT JOIN CTE_Questions q ON rua.UserId = q.OwnerUserId
WHERE
    rua.PostsCount > 5
    AND COALESCE(rua.LocationRank, 99) < 50
    AND rua.LastBadgeDate BETWEEN NOW() - INTERVAL '1 year' AND NOW()
    AND NOT EXISTS (
        SELECT 1
        FROM Posts p2
        WHERE p2.AcceptedAnswerId IS NOT NULL
          AND p2.OwnerUserId = rua.UserId
          AND p2.CreationDate > NOW() - INTERVAL '6 months'
    )
GROUP BY
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.ActiveDays,
    rua.LocationRank,
    rua.PostsCount,
    rua.GoldBadges,
    rua.SilverBadges,
    rua.BronzeBadges,
    rua.VotesReceived,
    rua.LastBadgeDate
ORDER BY GlobalUserRank
LIMIT 100

UNION

SELECT
    cg.UserId,
    cg.DisplayName,
    cg.Reputation,
    0 AS ActiveDays,
    99 AS LocationRank,
    0 AS PostsCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS VotesReceived,
    NULL AS LastBadgeDate,
    0 AS TotalViewsByLocationRank,
    0 AS MaxScoreWordRatioByActiveDays,
    '' AS TagsUsedByUser,
    101 AS GlobalUserRank
FROM Users cg
WHERE NOT EXISTS (SELECT 1 FROM RecursiveUserActivity rua WHERE rua.UserId = cg.Id)
ORDER BY GlobalUserRank;