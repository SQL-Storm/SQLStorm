-- {"query": "3077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2432}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location,'[unknown]') AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT
        pu.OwnerUserId AS UserId,
        COUNT(*) AS TagMentions,
        STRING_AGG(DISTINCT tag, ', ') AS UniqueTags
    FROM Posts pu
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM t.tag) AS tag
        FROM (
            SELECT UNNEST(string_to_array(pu.Tags, '><')) AS tag
        ) AS t
    ) tags
    WHERE pu.PostTypeId = 1
      AND pu.Tags IS NOT NULL
    GROUP BY pu.OwnerUserId
),
RecentVoting AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    ROUND(us.AvgScore,2) AS AvgScore,
    us.LastPostDate,
    COALESCE(b.BadgeCount,0) AS BadgeCount,
    COALESCE(b.GoldBadges,0) AS GoldBadges,
    COALESCE(b.SilverBadges,0) AS SilverBadges,
    COALESCE(b.BronzeBadges,0) AS BronzeBadges,
    b.BadgeList,
    COALESCE(t.TagMentions,0) AS TagMentions,
    t.UniqueTags,
    COALESCE(rv.UpVotesGiven,0) AS UpVotesGiven,
    COALESCE(rv.DownVotesGiven,0) AS DownVotesGiven,
    rv.LastVoteDate,
    ROW_NUMBER() OVER (PARTITION BY us.Location ORDER BY us.Reputation DESC) AS RankInLocation,
    CASE
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
        WHEN us.Reputation BETWEEN 5000 AND 9999 THEN 'Experienced'
        ELSE 'Novice'
    END AS ReputationTier,
    (SELECT COUNT(*) FROM Posts p2
        WHERE p2.OwnerUserId = us.Id
          AND p2.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') AS PostsLast30Days,
    (SELECT COUNT(*) FROM Comments c
        WHERE c.UserId = us.Id
          AND c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') AS CommentsLast30Days
FROM UserStats us
LEFT JOIN BadgeAgg b ON b.UserId = us.Id
LEFT JOIN TagUsage t ON t.UserId = us.Id
LEFT JOIN RecentVoting rv ON rv.UserId = us.Id
WHERE us.Reputation IS NOT NULL
  AND (us.LastPostDate IS NULL OR us.LastPostDate > CAST('2015-01-01' AS timestamp))
UNION ALL
SELECT
    NULL AS Id,
    'Aggregates' AS DisplayName,
    NULL AS Reputation,
    NULL AS Location,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount) AS AnswerCount,
    SUM(us.TotalScore) AS TotalScore,
    NULL AS AvgScore,
    NULL AS LastPostDate,
    SUM(COALESCE(b.BadgeCount,0)) AS BadgeCount,
    SUM(COALESCE(b.GoldBadges,0)) AS GoldBadges,
    SUM(COALESCE(b.SilverBadges,0)) AS SilverBadges,
    SUM(COALESCE(b.BronzeBadges,0)) AS BronzeBadges,
    NULL AS BadgeList,
    SUM(COALESCE(t.TagMentions,0)) AS TagMentions,
    NULL AS UniqueTags,
    SUM(COALESCE(rv.UpVotesGiven,0)) AS UpVotesGiven,
    SUM(COALESCE(rv.DownVotesGiven,0)) AS DownVotesGiven,
    NULL AS LastVoteDate,
    NULL AS RankInLocation,
    NULL AS ReputationTier,
    NULL AS PostsLast30Days,
    NULL AS CommentsLast30Days
FROM UserStats us
LEFT JOIN BadgeAgg b ON b.UserId = us.Id
LEFT JOIN TagUsage t ON t.UserId = us.Id
LEFT JOIN RecentVoting rv ON rv.UserId = us.Id
WHERE us.Reputation > 1000;