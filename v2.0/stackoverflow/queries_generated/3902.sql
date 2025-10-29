-- {"query": "3902.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2834} 

WITH cte_user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT tag) FILTER (WHERE p.PostTypeId = 1) AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag
    ) AS tags ON true
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
cte_badge_agg AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
cte_recent_votes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')    AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')  AS DownVotesGiven,
        MAX(v.CreationDate)                          AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
cte_user_latest_post AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id          AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
cte_top_tags AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    COALESCE(b.TotalBadges, 0)      AS TotalBadges,
    COALESCE(b.GoldBadges, 0)       AS GoldBadges,
    COALESCE(b.SilverBadges, 0)     AS SilverBadges,
    COALESCE(b.BronzeBadges, 0)     AS BronzeBadges,
    b.BadgeNames,
    COALESCE(rv.UpVotesGiven, 0)    AS UpVotesGiven,
    COALESCE(rv.DownVotesGiven, 0)  AS DownVotesGiven,
    rv.LastVoteDate,
    up.PostId                       AS LatestPostId,
    up.Title                        AS LatestPostTitle,
    up.CreationDate                 AS LatestPostDate,
    up.Score                        AS LatestPostScore,
    CASE up.PostTypeId
        WHEN 1 THEN 'Question'
        WHEN 2 THEN 'Answer'
        ELSE 'Other'
    END                             AS LatestPostType,
    (SELECT STRING_AGG(t2.TagName, ',')
     FROM (SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag) AS t
     JOIN Tags t2 ON t2.TagName = t.tag
     WHERE p.Id = up.PostId
     LIMIT 5)                      AS LatestPostTopTags,
    us.DistinctTagCount,
    CASE
        WHEN us.Reputation > 20000 THEN 'Legendary'
        WHEN us.Reputation > 10000 THEN 'Guru'
        WHEN us.Reputation > 5000  THEN 'Expert'
        ELSE 'Novice'
    END                            AS ReputationTier,
    CASE
        WHEN us.LastPostDate IS NULL THEN NULL
        ELSE CURRENT_DATE - us.LastPostDate::date
    END                            AS DaysSinceLastPost,
    (SELECT COUNT(*) FROM Posts p2
     WHERE p2.OwnerUserId = us.Id AND p2.Score < 0) AS NegativeScorePosts,
    (SELECT COUNT(DISTINCT v2.PostId)
     FROM Votes v2
     JOIN VoteTypes vt2 ON vt2.Id = v2.VoteTypeId
     WHERE v2.UserId = us.Id AND vt2.Name = 'Favorite') AS FavoritesGiven
FROM cte_user_stats us
LEFT JOIN cte_badge_agg b          ON b.UserId = us.Id
LEFT JOIN cte_recent_votes rv     ON rv.UserId = us.Id
LEFT JOIN (SELECT * FROM cte_user_latest_post WHERE rn = 1) up
       ON up.UserId = us.Id
WHERE us.Reputation IS NOT NULL
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL,
    '--- Summary ---',
    NULL,
    SUM(us.QuestionCount),
    SUM(us.AnswerCount),
    SUM(us.TotalScore),
    SUM(COALESCE(b.TotalBadges,0)),
    SUM(COALESCE(b.GoldBadges,0)),
    SUM(COALESCE(b.SilverBadges,0)),
    SUM(COALESCE(b.BronzeBadges,0)),
    NULL,
    SUM(COALESCE(rv.UpVotesGiven,0)),
    SUM(COALESCE(rv.DownVotesGiven,0)),
    NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM cte_user_stats us
LEFT JOIN cte_badge_agg b      ON b.UserId = us.Id
LEFT JOIN cte_recent_votes rv  ON rv.UserId = us.Id
EXCEPT
SELECT * FROM (SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL) AS dummy;
