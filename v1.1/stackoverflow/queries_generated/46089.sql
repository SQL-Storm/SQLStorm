-- {"query": "46089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1711}

WITH TopQuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
        AND p.Score >= 10
),
UserTagExpertise AS (
    SELECT 
        tqt.OwnerUserId,
        tqt.TagName,
        COUNT(DISTINCT tqt.QuestionId) AS QuestionsAsked,
        SUM(tqt.QuestionScore) AS TotalQuestionScore,
        SUM(tqt.ViewCount) AS TotalViews,
        AVG(tqt.AnswerCount) AS AvgAnswersReceived
    FROM TopQuestionTags tqt
    WHERE tqt.OwnerUserId IS NOT NULL
    GROUP BY tqt.OwnerUserId, tqt.TagName
    HAVING COUNT(DISTINCT tqt.QuestionId) >= 5
),
AnswererStats AS (
    SELECT 
        a.OwnerUserId AS AnswererUserId,
        tqt.TagName,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) AS AcceptedAnswers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT a.Id), 0) AS AcceptanceRate
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    INNER JOIN TopQuestionTags tqt ON tqt.QuestionId = q.Id
    WHERE a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY a.OwnerUserId, tqt.TagName
    HAVING COUNT(DISTINCT a.Id) >= 10
),
UserInteractionNetwork AS (
    SELECT 
        ute.OwnerUserId AS QuestionerId,
        ast.AnswererUserId,
        ute.TagName,
        COUNT(DISTINCT c.Id) AS CommentExchanges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM UserTagExpertise ute
    INNER JOIN AnswererStats ast ON ute.TagName = ast.TagName
    LEFT JOIN Posts q ON q.OwnerUserId = ute.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.OwnerUserId = ast.AnswererUserId
    LEFT JOIN Comments c ON c.PostId IN (q.Id, a.Id) 
        AND c.UserId IN (ute.OwnerUserId, ast.AnswererUserId)
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2, 3)
    WHERE ute.OwnerUserId <> ast.AnswererUserId
    GROUP BY ute.OwnerUserId, ast.AnswererUserId, ute.TagName
),
BadgeInfluence AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Id END) AS TagBasedBadges
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY b.UserId
)
SELECT 
    u1.DisplayName AS QuestionerName,
    u2.DisplayName AS AnswererName,
    uin.TagName,
    ute.QuestionsAsked,
    ute.TotalQuestionScore,
    ast.AnswersGiven,
    ast.AvgAnswerScore,
    ast.AcceptanceRate,
    uin.CommentExchanges,
    uin.UpvotesReceived,
    bi1.GoldBadges AS QuestionerGoldBadges,
    bi2.GoldBadges AS AnswererGoldBadges,
    u1.Reputation AS QuestionerReputation,
    u2.Reputation AS AnswererReputation,
    DENSE_RANK() OVER (PARTITION BY uin.TagName ORDER BY ast.AcceptanceRate DESC) AS AnswererRankByAcceptance,
    DENSE_RANK() OVER (PARTITION BY uin.TagName ORDER BY ute.TotalQuestionScore DESC) AS QuestionerRankByScore,
    ROW_NUMBER() OVER (ORDER BY (ast.AcceptanceRate * ute.TotalQuestionScore) DESC) AS OverallInfluenceRank
FROM UserInteractionNetwork uin
INNER JOIN UserTagExpertise ute ON uin.QuestionerId = ute.OwnerUserId AND uin.TagName = ute.TagName
INNER JOIN AnswererStats ast ON uin.AnswererUserId = ast.AnswererUserId AND uin.TagName = ast.TagName
INNER JOIN Users u1 ON uin.QuestionerId = u1.Id
INNER JOIN Users u2 ON uin.AnswererUserId = u2.Id
LEFT JOIN BadgeInfluence bi1 ON u1.Id = bi1.UserId
LEFT JOIN BadgeInfluence bi2 ON u2.Id = bi2.UserId
WHERE ute.QuestionsAsked >= 5
    AND ast.AnswersGiven >= 10
    AND u1.Reputation >= 1000
    AND u2.Reputation >= 5000
ORDER BY OverallInfluenceRank
LIMIT 1000;
