-- {"query": "3835.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2072} 

WITH
    -- Basic per‑user stats
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            COALESCE(u.Reputation,0)                         AS Rep,
            (SELECT COUNT(*) FROM Posts p
                WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
            (SELECT COUNT(*) FROM Posts p
                WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
            (SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 1)          AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 2)          AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 3)          AS BronzeBadges,
            (SELECT MAX(CreationDate) FROM Posts p
                WHERE p.OwnerUserId = u.Id)                     AS LastPostDate
        FROM Users u
    ),

    -- Aggregate post‑level metrics
    PostMetrics AS (
        SELECT
            p.OwnerUserId                                   AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)        AS Qs,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)        AS As,
            SUM(COALESCE(p.Score,0))                        AS TotalScore,
            AVG(p.ViewCount)                                AS AvgViews,
            MAX(p.CreationDate)                             AS MostRecentPost
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),

    -- Tag usage per user (split the <tag><tag> list)
    TagUsage AS (
        SELECT
            pt.OwnerUserId                                 AS UserId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM pt.Tags), '><')) AS Tag,
            COUNT(*)                                        AS TagCount
        FROM Posts pt
        WHERE pt.Tags IS NOT NULL
        GROUP BY pt.OwnerUserId, Tag
    ),

    -- Rank tags by usage per user
    TopTags AS (
        SELECT
            UserId,
            Tag,
            TagCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
        FROM TagUsage
    ),

    -- Recent voting activity (last 30 days)
    RecentVotes AS (
        SELECT
            v.UserId,
            COUNT(*) FILTER (WHERE vt.Name = 'UpMod')      AS UpVotes,
            COUNT(*) FILTER (WHERE vt.Name = 'DownMod')    AS DownVotes,
            MAX(v.CreationDate)                            AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY v.UserId
    )

SELECT
    us.Id,
    us.DisplayName,
    us.Rep,
    COALESCE(pm.Qs,0)                                   AS TotalQuestions,
    COALESCE(pm.As,0)                                   AS TotalAnswers,
    COALESCE(pm.TotalScore,0)                           AS ScoreSum,
    COALESCE(pm.AvgViews,0)                             AS AvgViews,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    rv.UpVotes,
    rv.DownVotes,
    rv.LastVoteDate,
    STRING_AGG(tt.Tag, ', ') FILTER (WHERE tt.rn <= 3) AS Top3Tags,
    CASE
        WHEN us.LastPostDate IS NULL THEN 'Never'
        ELSE TO_CHAR(us.LastPostDate,'YYYY-MM-DD')
    END                                                AS LastPostDate
FROM UserStats us
LEFT JOIN PostMetrics    pm ON pm.UserId = us.Id
LEFT JOIN RecentVotes    rv ON rv.UserId = us.Id
LEFT JOIN TopTags        tt ON tt.UserId = us.Id
WHERE (us.Rep > 1000 OR us.GoldBadges > 0)
  AND (us.LastPostDate IS NULL OR us.LastPostDate < CURRENT_DATE - INTERVAL '1 year')
GROUP BY
    us.Id, us.DisplayName, us.Rep,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    pm.Qs, pm.As, pm.TotalScore, pm.AvgViews,
    rv.UpVotes, rv.DownVotes, rv.LastVoteDate,
    us.LastPostDate
HAVING COUNT(tt.Tag) > 0
ORDER BY us.Rep DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation > 1000);
