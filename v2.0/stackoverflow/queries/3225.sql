-- {"query": "3225.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1802}
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown') AS Location,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
           (SELECT MAX(v.CreationDate)
              FROM Votes v
              JOIN Posts p ON v.PostId = p.Id
             WHERE p.OwnerUserId = u.Id) AS LastVoteDate
    FROM Users u
    WHERE u.Reputation > 10000
),
RecentActivity AS (
    SELECT u.Id,
           MAX(p.LastActivityDate) AS LastPostActivity,
           MAX(c.CreationDate)     AS LastCommentActivity,
           MAX(v.CreationDate)     AS LastVoteActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes    v ON v.UserId = u.Id
    WHERE u.Id IN (SELECT Id FROM UserStats)
    GROUP BY u.Id
),
TagPopularity AS (
    SELECT t.TagName,
           t.Count,
           (SELECT COUNT(*)
              FROM Posts p
             WHERE p.Tags LIKE '%' || t.TagName || '%') AS TaggedPosts,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),
Combined AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.Location,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           us.QuestionCount,
           us.AnswerCount,
           ROUND(us.AvgPostScore, 2) AS AvgPostScore,
           COALESCE(ra.LastPostActivity,
                    ra.LastCommentActivity,
                    ra.LastVoteActivity,
                    us.LastVoteDate) AS LastUserActivity,
           CASE
               WHEN us.Reputation >= 200000 THEN 'Legendary'
               WHEN us.Reputation >= 100000 THEN 'Elite'
               WHEN us.Reputation >= 50000  THEN 'Master'
               ELSE 'Pro'
           END AS ReputationTier
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
),
TopUsers AS (
    SELECT Id,
           DisplayName,
           Reputation,
           Location,
           GoldBadges,
           SilverBadges,
           BronzeBadges,
           QuestionCount,
           AnswerCount,
           AvgPostScore,
           LastUserActivity,
           ReputationTier
    FROM Combined
    WHERE ReputationTier IN ('Legendary', 'Elite')
    ORDER BY Reputation DESC
    LIMIT 10
),
TagHeader AS (
    SELECT CAST(NULL AS BIGINT) AS Id,
           CAST('--- Tag Summary ---' AS TEXT) AS DisplayName,
           CAST(NULL AS INTEGER) AS Reputation,
           CAST(NULL AS TEXT) AS Location,
           CAST(NULL AS INTEGER) AS GoldBadges,
           CAST(NULL AS INTEGER) AS SilverBadges,
           CAST(NULL AS INTEGER) AS BronzeBadges,
           CAST(NULL AS INTEGER) AS QuestionCount,
           CAST(NULL AS INTEGER) AS AnswerCount,
           CAST(NULL AS NUMERIC) AS AvgPostScore,
           CAST(NULL AS TIMESTAMP) AS LastUserActivity,
           CAST(NULL AS TEXT) AS ReputationTier
),
TopTags AS (
    SELECT CAST(NULL AS BIGINT) AS Id,
           t.TagName AS DisplayName,
           t.Count AS Reputation,
           CAST(NULL AS TEXT) AS Location,
           CAST(NULL AS INTEGER) AS GoldBadges,
           CAST(NULL AS INTEGER) AS SilverBadges,
           CAST(NULL AS INTEGER) AS BronzeBadges,
           t.TaggedPosts AS QuestionCount,
           t.TagRank AS AnswerCount,
           CAST(NULL AS NUMERIC) AS AvgPostScore,
           CAST(NULL AS TIMESTAMP) AS LastUserActivity,
           CAST(NULL AS TEXT) AS ReputationTier
    FROM TagPopularity t
    WHERE t.TagRank <= 5
)
SELECT *
FROM (
    SELECT * FROM TopUsers
    UNION ALL
    SELECT * FROM TagHeader
    UNION ALL
    SELECT * FROM TopTags
) AS final_set
ORDER BY Reputation DESC NULLS LAST, AnswerCount ASC NULLS LAST;