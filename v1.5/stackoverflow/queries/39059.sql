-- {"query": "39059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2460} 
WITH UserPosts AS (
    SELECT
        u.Id,
        u.DisplayName,
        p.PostTypeId,
        p.ViewCount,
        p.Score
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
     AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
UserActivity AS (
    SELECT
        Id,
        DisplayName,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END)          AS Questions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END)          AS Answers,
        SUM(CASE WHEN PostTypeId = 1 THEN ViewCount ELSE 0 END)  AS Views,
        AVG(CASE WHEN PostTypeId = 2 THEN Score ELSE NULL END)   AS AvgAnswerScore
    FROM UserPosts
    GROUP BY Id, DisplayName
),
BadgeSummary AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS Gold,
        COUNT(*) FILTER (WHERE Class = 2) AS Silver,
        COUNT(*) FILTER (WHERE Class = 3) AS Bronze
    FROM Badges
    GROUP BY UserId
),
TopTags AS (
    SELECT
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
UserTopTags AS (
    SELECT
        UserId,
        Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC) AS RN
    FROM TopTags
    GROUP BY UserId, Tag
)
SELECT
    ua.Id,
    ua.DisplayName,
    ua.Questions,
    ua.Answers,
    ua.Views,
    ROUND(ua.AvgAnswerScore, 2)        AS AvgAnswerScore,
    COALESCE(bs.Gold,   0)             AS GoldBadges,
    COALESCE(bs.Silver, 0)             AS SilverBadges,
    COALESCE(bs.Bronze, 0)             AS BronzeBadges,
    string_agg(utt.Tag || '(' || utt.TagCount || ')', ', ' 
               ORDER BY utt.TagCount DESC)           AS TopTags,
    DENSE_RANK() OVER (ORDER BY ua.Answers DESC)     AS AnswerRank
FROM UserActivity ua
LEFT JOIN BadgeSummary bs
  ON bs.UserId = ua.Id
LEFT JOIN UserTopTags utt
  ON utt.UserId = ua.Id
 AND utt.RN <= 3
GROUP BY
    ua.Id,
    ua.DisplayName,
    ua.Questions,
    ua.Answers,
    ua.Views,
    ua.AvgAnswerScore,
    bs.Gold,
    bs.Silver,
    bs.Bronze
ORDER BY
    ua.Answers DESC,
    ua.Views   DESC
LIMIT 100;