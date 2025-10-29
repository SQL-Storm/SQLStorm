WITH UserPostAgg AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM   Users u
    LEFT   JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeAgg AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM   Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT tags.tag AS tag,
           COUNT(DISTINCT p.Id) AS PostsWithTag,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersWithTag,
           SUM(p.Score) AS TotalScore,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS TagRank
    FROM   Posts p
    CROSS  JOIN LATERAL (
              SELECT TRIM(t.tag) AS tag
              FROM   UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t(tag)
              WHERE  p.Tags IS NOT NULL
           ) AS tags
    GROUP BY tags.tag
    HAVING COUNT(*) > 100
),
RecentVote AS (
    SELECT u.Id,
           (SELECT MAX(v.CreationDate)
            FROM   Votes v
            WHERE  v.UserId = u.Id) AS LastVoteDate
    FROM   Users u
)

SELECT
    upa.Id,
    COALESCE(upa.DisplayName, 'anonymous') AS DisplayName,
    upa.Reputation,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AvgScore,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    ts.tag,
    ts.PostsWithTag,
    ts.TagRank,
    rv.LastVoteDate,
    CASE
        WHEN upa.LastPostDate IS NULL THEN NULL
        WHEN upa.LastPostDate < (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN 'inactive'
        ELSE 'active'
    END AS ActivityStatus
FROM   UserPostAgg upa
FULL OUTER JOIN UserBadgeAgg ub ON ub.UserId = upa.Id
LEFT JOIN RecentVote rv ON rv.Id = upa.Id
LEFT JOIN LATERAL (
           SELECT tag, PostsWithTag, TagRank
           FROM   TagStats
           ORDER BY TagRank
           LIMIT 1
       ) ts ON TRUE
WHERE  (upa.Reputation > 10000 OR COALESCE(ub.GoldBadges, 0) > 0)

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName, 'anonymous') AS DisplayName,
    u.Reputation,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS AvgScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS tag,
    NULL AS PostsWithTag,
    NULL AS TagRank,
    NULL AS LastVoteDate,
    'no_posts' AS ActivityStatus
FROM   Users u
WHERE  NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND  u.Reputation > 5000

ORDER BY Reputation DESC, GoldBadges DESC, QuestionCount DESC
LIMIT 100;