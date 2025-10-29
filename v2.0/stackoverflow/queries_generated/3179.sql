-- {"query": "3179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2705} 

WITH UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn,
        COUNT(*) AS TagUseCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) AS taglist(tag)
    JOIN Tags t ON t.TagName = taglist.tag
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')       AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')     AS DownVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite')    AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
)

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.QuestionScore,
    ua.AnswerScore,
    ua.LastPostDate,
    COALESCE(b.GoldBadges, 0)   AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(b.TagBadges, 0)    AS TagBadges,
    COALESCE(rv.UpVotesGiven, 0)     AS UpVotesGiven30d,
    COALESCE(rv.DownVotesGiven, 0)   AS DownVotesGiven30d,
    COALESCE(rv.FavoritesGiven, 0)   AS FavoritesGiven30d,
    CASE
        WHEN ua.AnswerCount = 0 THEN NULL
        ELSE ROUND(ua.AnswerScore::numeric / NULLIF(ua.AnswerCount, 0), 2)
    END AS AvgAnswerScore,
    tt.TagName       AS TopTag,
    tt.TagUseCount   AS TopTagUseCount,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    (SELECT COUNT(*) FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
    (SELECT COUNT(*) FROM PostHistory ph
        WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
          AND ph.PostHistoryTypeId = 10) AS ClosedPosts
FROM Users u
LEFT JOIN UserActivity ua   ON ua.Id = u.Id
LEFT JOIN BadgeAgg b        ON b.UserId = u.Id
LEFT JOIN RecentVotes rv    ON rv.UserId = u.Id
LEFT JOIN (
    SELECT UserId, TagName, TagUseCount
    FROM TopTags
    WHERE rn = 1
) tt ON tt.UserId = u.Id
WHERE u.Reputation > 1000
ORDER BY ReputationRank
LIMIT 100

UNION ALL

SELECT
    NULL AS Id,
    'TOTAL' AS DisplayName,
    SUM(u.Reputation)                     AS Reputation,
    SUM(ua.QuestionCount)                 AS QuestionCount,
    SUM(ua.AnswerCount)                   AS AnswerCount,
    SUM(ua.QuestionScore)                 AS QuestionScore,
    SUM(ua.AnswerScore)                   AS AnswerScore,
    MAX(ua.LastPostDate)                  AS LastPostDate,
    SUM(COALESCE(b.GoldBadges, 0))         AS GoldBadges,
    SUM(COALESCE(b.SilverBadges, 0))       AS SilverBadges,
    SUM(COALESCE(b.BronzeBadges, 0))       AS BronzeBadges,
    SUM(COALESCE(b.TagBadges, 0))          AS TagBadges,
    SUM(COALESCE(rv.UpVotesGiven, 0))      AS UpVotesGiven30d,
    SUM(COALESCE(rv.DownVotesGiven, 0))    AS DownVotesGiven30d,
    SUM(COALESCE(rv.FavoritesGiven, 0))    AS FavoritesGiven30d,
    NULL                                   AS AvgAnswerScore,
    NULL                                   AS TopTag,
    NULL                                   AS TopTagUseCount,
    NULL                                   AS ReputationRank,
    NULL                                   AS AcceptedAnswers,
    NULL                                   AS ClosedPosts
FROM Users u
LEFT JOIN UserActivity ua ON ua.Id = u.Id
LEFT JOIN BadgeAgg b      ON b.UserId = u.Id
LEFT JOIN RecentVotes rv  ON rv.UserId = u.Id
WHERE u.Reputation > 1000;
