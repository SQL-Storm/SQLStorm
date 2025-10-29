-- {"query": "3784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2278} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0)          AS TotalPostScore,
        COUNT(p.Id)                        AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate)               AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)       AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)       AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)       AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count                                   AS TagUseCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
RecentVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE 
                WHEN vt.Id = 2 THEN 1   -- UpMod
                WHEN vt.Id = 3 THEN -1  -- DownMod
                ELSE 0
            END)                                   AS VoteScore,
        MAX(v.CreationDate)                       AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.TotalPostScore,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    COALESCE(rv.VoteScore, 0)                                     AS RecentVoteScore,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Legendary'
        WHEN us.Reputation > 10000 THEN 'Expert'
        WHEN us.Reputation > 5000  THEN 'Proficient'
        ELSE 'Novice'
    END                                                          AS ReputationBand,
    STRING_AGG(DISTINCT tt.TagName, ', ') 
        FILTER (WHERE tt.rn <= 5)                                 AS TopFiveTags
FROM UserStats us
LEFT JOIN BadgeStats bs      ON bs.UserId = us.Id
LEFT JOIN RecentVotes rv    ON rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS raw_tag
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    ) pt ON TRUE
LEFT JOIN Tags tt ON tt.TagName = REPLACE(REPLACE(pt.raw_tag, '<', ''), '>', '')
WHERE us.PostCount > 0
GROUP BY 
    us.Id, us.DisplayName, us.Reputation, us.TotalPostScore, us.PostCount,
    us.QuestionCount, us.AnswerCount, bs.TotalBadges, bs.GoldBadges,
    bs.SilverBadges, bs.BronzeBadges, rv.VoteScore
HAVING COUNT(DISTINCT tt.TagName) > 0

UNION ALL

SELECT 
    NULL                         AS Id,
    'TOTAL'                      AS DisplayName,
    SUM(us.Reputation)           AS Reputation,
    SUM(us.TotalPostScore)       AS TotalPostScore,
    SUM(us.PostCount)            AS PostCount,
    SUM(us.QuestionCount)        AS QuestionCount,
    SUM(us.AnswerCount)          AS AnswerCount,
    SUM(bs.TotalBadges)          AS TotalBadges,
    SUM(bs.GoldBadges)           AS GoldBadges,
    SUM(bs.SilverBadges)         AS SilverBadges,
    SUM(bs.BronzeBadges)         AS BronzeBadges,
    SUM(COALESCE(rv.VoteScore,0)) AS RecentVoteScore,
    NULL                         AS ReputationBand,
    NULL                         AS TopFiveTags
FROM UserStats us
LEFT JOIN BadgeStats bs   ON bs.UserId = us.Id
LEFT JOIN RecentVotes rv ON rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
WHERE us.PostCount > 0
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
