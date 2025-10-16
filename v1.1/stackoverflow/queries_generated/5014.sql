-- {"query": "5014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1268} 
WITH
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT b.Id) DESC) AS rn
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.CreationDate < NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 20
)
, UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        AVG(NULLIF(p.Score,0)) AS AvgNonZeroScore,
        MAX(p.Score) AS MaxScore,
        SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
, TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount,0) AS AnswerCount,
        ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 5
)
, UserRecentBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank
    FROM Badges b
)
, CommentActivity AS (
    SELECT
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(LENGTH(COALESCE(c.Text, ''))) AS AvgCommentLength,
        COUNT(DISTINCT c.PostId) AS UniqueCommentedPosts,
        SUM(CASE WHEN c.Score > 2 THEN 1 ELSE 0 END) AS HighlyScoredComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
, TagPopularity AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    tu.PostCount,
    ups.TotalPosts,
    ups.QuestionsAsked,
    ups.AnswersGiven,
    ups.AvgNonZeroScore,
    ups.MaxScore,
    ups.CommunityPosts,
    ca.TotalComments,
    ca.AvgCommentLength,
    ca.UniqueCommentedPosts,
    ca.HighlyScoredComments,
    SQRT(COALESCE(ups.QuestionsAsked,0) * COALESCE(ups.AnswersGiven,0))::INT AS EngagementIndex,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViews,
    tq.TagCount AS TopQuestionTagCount,
    urb.BadgeName AS MostRecentBadge,
    urb.Class AS BadgeClass,
    (
        SELECT STRING_AGG(tg.TagName, ', ')
        FROM (
            SELECT DISTINCT
                unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
            FROM Posts p
            WHERE p.OwnerUserId = tu.UserId
                AND p.PostTypeId = 1
                AND p.Tags IS NOT NULL
            LIMIT 10
        ) tg
        INNER JOIN Tags t ON t.TagName = tg.TagName
        WHERE t.Count > 1000
    ) AS FrequentTagsUsed,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM Posts q
        LEFT JOIN PostLinks pl ON pl.PostId = q.Id
        WHERE q.OwnerUserId = tu.UserId
          AND q.PostTypeId = 1
          AND pl.RelatedPostId IS NOT NULL
    ) AS LinkedQuestionsByUser,
    tp.TagName AS TopTagUsed
FROM TopUsers tu
LEFT JOIN UserPostStats ups ON ups.OwnerUserId = tu.UserId
LEFT JOIN CommentActivity ca ON ca.UserId = tu.UserId
LEFT JOIN LATERAL (
    SELECT tq.*
    FROM TopQuestions tq
    WHERE tq.OwnerUserId = tu.UserId AND tq.QuestionRank = 1
    LIMIT 1
) tq ON TRUE
LEFT JOIN LATERAL (
    SELECT urb.BadgeName, urb.Class
    FROM UserRecentBadges urb
    WHERE urb.UserId = tu.UserId AND urb.RecentBadgeRank = 1
    LIMIT 1
) urb ON TRUE
LEFT JOIN LATERAL (
    SELECT tp.TagName
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tagname
    INNER JOIN Tags tp ON tp.TagName = tagname
    WHERE p.OwnerUserId = tu.UserId
      AND p.PostTypeId = 1
    GROUP BY tp.TagName
    ORDER BY COUNT(*) DESC, MIN(p.CreationDate) ASC
    LIMIT 1
) tp ON TRUE
WHERE tu.rn <= 20
ORDER BY tu.Reputation DESC, tu.BadgeCount DESC;