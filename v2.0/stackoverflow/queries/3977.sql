-- {"query": "3977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2303} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.Gold,0)   AS GoldBadges,
        COALESCE(bc.Silver,0) AS SilverBadges,
        COALESCE(bc.Bronze,0) AS BronzeBadges,
        COALESCE(pc.PostCount,0)    AS PostCount,
        COALESCE(ascore.AvgScore,0) AS AvgPostScore,
        MAX(p.LastActivityDate)    AS LastActivity
    FROM Users u
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class=2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class=3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) pc ON pc.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, AVG(Score*1.0) AS AvgScore
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) ascore ON ascore.OwnerUserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation,
        bc.Gold, bc.Silver, bc.Bronze,
        pc.PostCount, ascore.AvgScore
),

TagStats AS (
    SELECT 
        t.TagName,
        t.Count                               AS TagUseCount,
        COALESCE(av.AvgViews,0)               AS AvgViewsPerQuestion,
        COALESCE(ms.MaxScore,0)               AS MaxQuestionScore
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT AVG(p.ViewCount*1.0) AS AvgViews
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags LIKE '%<'||t.TagName||'>%'
    ) av ON TRUE
    LEFT JOIN LATERAL (
        SELECT MAX(p.Score) AS MaxScore
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags LIKE '%<'||t.TagName||'>%'
    ) ms ON TRUE
),

RecentVotes AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE vt.Id = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Id = 3) AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Id = 5) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY v.PostId
),

Combined AS (
    SELECT 
        us.Id                               AS UserId,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.PostCount,
        us.AvgPostScore,
        us.LastActivity,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC,
                                      us.GoldBadges DESC,
                                      us.SilverBadges DESC) AS RepRank
    FROM UserStats us
    WHERE us.PostCount > 0
)

SELECT 
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.PostCount,
    ROUND(c.AvgPostScore,2)           AS AvgScore,
    c.LastActivity,
    c.RepRank,
    COALESCE(rv.UpVotes,0)           AS RecentUpVotes,
    COALESCE(rv.DownVotes,0)         AS RecentDownVotes,
    COALESCE(rv.Favorites,0)         AS RecentFavorites,
    ts.TagName,
    ts.TagUseCount,
    ts.AvgViewsPerQuestion,
    ts.MaxQuestionScore
FROM Combined c
LEFT JOIN LATERAL (
    SELECT 
        t.TagName,
        t.TagUseCount,
        t.AvgViewsPerQuestion,
        t.MaxQuestionScore
    FROM TagStats t
    ORDER BY t.TagUseCount DESC
    LIMIT 1
) ts ON TRUE
LEFT JOIN RecentVotes rv ON rv.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = c.UserId
      AND p.PostTypeId = 1
    ORDER BY p.Score DESC NULLS LAST
    LIMIT 1
)
WHERE c.RepRank <= 100

UNION ALL

SELECT 
    NULL AS UserId,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL
ORDER BY RepRank ASC NULLS LAST
LIMIT 105;