-- {"query": "35042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 989} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p
        ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) >= 5
),
TopTags AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagUsage
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY TagName
    ORDER BY TagUsage DESC
    LIMIT 10
),
TagPopularityOverTime AS (
    SELECT 
        tt.TagName,
        date_trunc('month', p.CreationDate) AS Month,
        COUNT(*) AS QuestionsPerMonth
    FROM Posts p
    JOIN TopTags tt ON POSITION(tt.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1
    GROUP BY tt.TagName, date_trunc('month', p.CreationDate)
),
UserTagExpertise AS (
    SELECT 
        r.UserId,
        t.TagName,
        COUNT(*) AS AnswersOnTag,
        AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    JOIN Posts question ON p.ParentId = question.Id AND question.PostTypeId = 1
    JOIN TopTags t ON POSITION(t.TagName IN question.Tags) > 0
    JOIN RecentActiveUsers r ON p.OwnerUserId = r.UserId
    WHERE p.PostTypeId = 2
    GROUP BY r.UserId, t.TagName
    HAVING COUNT(*) >= 3
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class=1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class=2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class=3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT UserId FROM RecentActiveUsers)
    GROUP BY b.UserId
),
HotQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(a.Id) AS AnswerCount,
        p.CreationDate
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '14 days'
      AND p.Score >= 5 AND p.ViewCount >= 500
    GROUP BY p.Id
)
SELECT 
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ute.TagName AS TopExpertiseTag,
    ute.AnswersOnTag,
    ute.AvgAnswerScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = rau.UserId AND c.CreationDate > NOW() - INTERVAL '1 month') AS RecentComments,
    hq.QuestionId AS RecentHotQuestionId,
    hq.Title AS HotQuestionTitle,
    hq.Score AS HotQuestionScore,
    hq.ViewCount AS HotQuestionViews,
    hq.AnswerCount AS HotQuestionAnswerCount
FROM RecentActiveUsers rau
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = rau.UserId
LEFT JOIN LATERAL (
    SELECT ute_sub.TagName, ute_sub.AnswersOnTag, ute_sub.AvgAnswerScore
    FROM UserTagExpertise ute_sub
    WHERE ute_sub.UserId = rau.UserId
    ORDER BY ute_sub.AnswersOnTag DESC, ute_sub.AvgAnswerScore DESC NULLS LAST
    LIMIT 1
) ute ON TRUE
LEFT JOIN LATERAL (
    SELECT hq_sub.*
    FROM HotQuestions hq_sub
    WHERE hq_sub.QuestionId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = rau.UserId
    )
    ORDER BY hq_sub.Score DESC, hq_sub.ViewCount DESC
    LIMIT 1
) hq ON TRUE
ORDER BY rau.Reputation DESC, ute.AnswersOnTag DESC NULLS LAST
LIMIT 50;