-- {"query": "3880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2150}
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown') AS Location,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
RecentActivity AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.Location,
           us.BadgeCount,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           us.QuestionCount,
           us.AnswerCount,
           us.AvgQuestionScore,
           us.AvgAnswerScore,
           us.LastPostDate,
           ROW_NUMBER() OVER (PARTITION BY us.Location ORDER BY us.Reputation DESC) AS RankByLocation
    FROM UserStats us
    WHERE us.Reputation > 10000
),
TopTagUsage AS (
    SELECT t.TagName,
           COUNT(DISTINCT p.Id) AS PostsWithTag,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScoreTag
    FROM Tags t
    JOIN (
        SELECT p.Id, p.PostTypeId, p.Score, p.Tags
        FROM Posts p
        WHERE p.Tags IS NOT NULL
          AND p.PostTypeId = 1
    ) p ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 500
),
UserTagAffinity AS (
    SELECT ra.Id,
           tg.TagName,
           COUNT(*) AS TagPosts,
           ROW_NUMBER() OVER (PARTITION BY ra.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM RecentActivity ra
    JOIN Posts p ON p.OwnerUserId = ra.Id
    JOIN (
        SELECT p_inner.Id AS post_id,
               UNNEST(string_to_array(SUBSTRING(p_inner.Tags FROM 2 FOR (CHAR_LENGTH(p_inner.Tags) - 2)), '><')) AS Tag
        FROM Posts p_inner
        WHERE p_inner.Tags IS NOT NULL
    ) pt ON pt.post_id = p.Id
    JOIN Tags tg ON tg.TagName = pt.Tag
    WHERE p.PostTypeId = 1
    GROUP BY ra.Id, tg.TagName
),
FinalRanking AS (
    SELECT ra.Id,
           ra.DisplayName,
           ra.Reputation,
           ra.BadgeCount,
           ra.GoldBadges,
           ra.SilverBadges,
           ra.BronzeBadges,
           ra.QuestionCount,
           ra.AnswerCount,
           ra.AvgQuestionScore,
           ra.AvgAnswerScore,
           ra.RankByLocation,
           uta.TagName,
           uta.TagPosts,
           CASE
               WHEN ra.QuestionCount = 0 THEN NULL
               ELSE CAST(ra.AnswerCount AS double precision) / NULLIF(ra.QuestionCount, 0)
           END AS AnswerToQuestionRatio,
           (SELECT COUNT(*)
            FROM Votes v
            WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ra.Id)
              AND v.VoteTypeId = 2) AS TotalUpVotesReceived
    FROM RecentActivity ra
    LEFT JOIN UserTagAffinity uta ON uta.Id = ra.Id AND uta.TagRank = 1
)

SELECT *
FROM FinalRanking
WHERE (AnswerToQuestionRatio > 0.5 OR GoldBadges > 5)
UNION ALL
SELECT CAST(NULL AS bigint) AS Id,
       CAST('---' AS text) AS DisplayName,
       CAST(NULL AS integer) AS Reputation,
       CAST(NULL AS integer) AS BadgeCount,
       CAST(NULL AS integer) AS GoldBadges,
       CAST(NULL AS integer) AS SilverBadges,
       CAST(NULL AS integer) AS BronzeBadges,
       CAST(NULL AS integer) AS QuestionCount,
       CAST(NULL AS integer) AS AnswerCount,
       CAST(NULL AS double precision) AS AvgQuestionScore,
       CAST(NULL AS double precision) AS AvgAnswerScore,
       CAST(NULL AS integer) AS RankByLocation,
       CAST(NULL AS text) AS TagName,
       CAST(NULL AS integer) AS TagPosts,
       CAST(NULL AS double precision) AS AnswerToQuestionRatio,
       CAST(NULL AS integer) AS TotalUpVotesReceived
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;