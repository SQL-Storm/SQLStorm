-- {"query": "3876.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2239} 

WITH UserStats AS (
    SELECT 
        u.Id                                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)                FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score),0)                         AS TotalScore,
        ROUND(AVG(p.Score)::numeric,2)                   AS AvgScore,
        MAX(p.CreationDate)                              AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)               FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*)               FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*)               FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*)                                            AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

TagUsage AS (
    SELECT 
        p.OwnerUserId                                                AS UserId,
        trim(t)                                                      AS TagName,
        COUNT(*)                                                     AS TagCount
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(
            substr(p.Tags,2,length(p.Tags)-2),
            '><'
         ) AS t ON true
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, trim(t)
),

TopTags AS (
    SELECT 
        tu.UserId,
        string_agg(tu.TagName || ':' || tu.TagCount, ', ' ORDER BY tu.TagCount DESC) AS TopTagList
    FROM (
        SELECT 
            *, 
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
        FROM TagUsage
    ) tu
    WHERE tu.rn <= 5
    GROUP BY tu.UserId
),

RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Id = 2) AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Id = 3) AS DownVotesGiven,
        COUNT(*) FILTER (WHERE vt.Id = 5) AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY v.UserId
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    us.AvgScore,
    COALESCE(b.GoldBadges,0)   AS GoldBadges,
    COALESCE(b.SilverBadges,0) AS SilverBadges,
    COALESCE(b.BronzeBadges,0) AS BronzeBadges,
    COALESCE(b.TotalBadges,0)  AS TotalBadges,
    COALESCE(t.TopTagList,'No tags') AS TopTags,
    COALESCE(rv.UpVotesGiven,0)    AS UpVotesGiven30d,
    COALESCE(rv.DownVotesGiven,0)  AS DownVotesGiven30d,
    COALESCE(rv.FavoritesGiven,0)  AS FavoritesGiven30d,
    CASE
        WHEN us.Reputation > 20000                THEN 'Elite'
        WHEN us.Reputation BETWEEN 10000 AND 19999 THEN 'PowerUser'
        WHEN us.Reputation BETWEEN 1000  AND 9999  THEN 'Contributor'
        ELSE 'Newbie'
    END                                           AS ReputationTier,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS ReputationRank,
    (SELECT MAX(p.Score) 
     FROM Posts p 
     WHERE p.OwnerUserId = us.UserId)               AS MaxPostScore,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = us.UserId 
       AND ph.PostHistoryTypeId = 10)              AS CloseVotesCast
FROM UserStats us
LEFT JOIN BadgeAgg   b ON b.UserId = us.UserId
LEFT JOIN TopTags    t ON t.UserId = us.UserId
LEFT JOIN RecentVotes rv ON rv.UserId = us.UserId
WHERE us.Reputation IS NOT NULL

UNION ALL

SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL

ORDER BY ReputationRank
LIMIT 100;
