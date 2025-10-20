-- {"query": "39092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2671} 
WITH QuestionTags AS (
    SELECT p.Id AS QuestionId,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagPopularity AS (
    SELECT Tag,
           COUNT(*) AS TagCount,
           RANK() OVER (ORDER BY COUNT(*) DESC) AS TagRank
    FROM QuestionTags
    GROUP BY Tag
),
BadgeCounts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT u.Id             AS UserId,
           u.DisplayName,
           COUNT(DISTINCT q.Id) FILTER (WHERE q.PostTypeId = 1) AS QuestionsAsked,
           COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswersPosted,
           AVG(a.Score)           FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
           MAX(p.LastActivityDate)                             AS LastActive
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY AnswersPosted DESC, AvgAnswerScore DESC) AS UserRank
    FROM UserActivity
    WHERE AnswersPosted >= 50
)
SELECT
    tu.UserRank,
    tu.DisplayName,
    tu.QuestionsAsked,
    tu.AnswersPosted,
    ROUND(tu.AvgAnswerScore, 2) AS AvgAnswerScore,
    COALESCE(bc.GoldBadges,   0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    ut.TopTag,
    tp.TagCount,
    tp.TagRank
FROM TopUsers tu
LEFT JOIN LATERAL (
    SELECT qt.Tag AS TopTag
    FROM QuestionTags qt
    JOIN Posts p2 ON p2.Id = qt.QuestionId
    WHERE p2.OwnerUserId = tu.UserId
    GROUP BY qt.Tag
    ORDER BY COUNT(*) DESC
    LIMIT 1
) ut ON TRUE
LEFT JOIN TagPopularity tp ON tp.Tag = ut.TopTag
LEFT JOIN BadgeCounts   bc ON bc.UserId = tu.UserId
ORDER BY tu.UserRank;