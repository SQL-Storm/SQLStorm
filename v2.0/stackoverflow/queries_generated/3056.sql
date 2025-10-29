-- {"query": "3056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1818} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                     AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                     AS AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0)  AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0)  AS DownVotesGiven,
        MAX(p.CreationDate)                                            AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                AS ReputationRank
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes   v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

BadgeAgg AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*)                                            AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

TagInfo AS (
    SELECT
        t.TagName,
        t.Count                          AS TagUseCount,
        COALESCE(p.Title, '')            AS TagWikiTitle,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate DESC) AS rn
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = 0
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.ReputationRank,
    COALESCE(ba.GoldBadges,   '') AS GoldBadges,
    COALESCE(ba.SilverBadges, '') AS SilverBadges,
    COALESCE(ba.BronzeBadges, '') AS BronzeBadges,
    COALESCE(ba.TotalBadges, 0)  AS TotalBadges,
    CASE
        WHEN us.LastPostDate IS NULL THEN 'Never Posted'
        ELSE TO_CHAR(us.LastPostDate, 'YYYY-MM-DD')
    END                               AS LastPostDate,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.Id AND p.Score > 0)               AS PositiveScorePosts,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.Id AND c.Score > 5)                AS HighScoreComments,
    (SELECT STRING_AGG(t.TagName, '; ')
        FROM TagInfo t
        WHERE t.rn = 1
          AND EXISTS (
                SELECT 1
                FROM Posts p
                WHERE p.OwnerUserId = us.Id
                  AND p.Tags ILIKE CONCAT('%<', t.TagName, '>%')
          )
        LIMIT 5)                                                                                 AS TopTagsAcrossPosts
FROM UserStats us
LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
WHERE us.ReputationRank <= 1000
  AND (us.QuestionCount > 0 OR us.AnswerCount > 0)

UNION ALL

SELECT
    NULL,
    'TOTALS',
    SUM(us.Reputation),
    SUM(us.QuestionCount),
    SUM(us.AnswerCount),
    SUM(us.UpVotesGiven),
    SUM(us.DownVotesGiven),
    NULL,
    NULL,
    NULL,
    NULL,
    SUM(ba.TotalBadges),
    NULL,
    NULL,
    NULL,
    NULL
FROM UserStats us
LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
WHERE us.ReputationRank <= 1000

ORDER BY Reputation DESC
LIMIT 100;
