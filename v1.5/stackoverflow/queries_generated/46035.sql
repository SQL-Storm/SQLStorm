-- {"query": "46035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1985}

WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearRank
    FROM Users u
    WHERE u.Reputation > 1000
),
QuestionMetrics AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(DISTINCT pl2.Id) FILTER (WHERE pl2.LinkTypeId = 3) AS DuplicateCount,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostLinks pl2 ON p.Id = pl2.RelatedPostId AND pl2.LinkTypeId = 3
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
        AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.Tags
),
AnswerPerformance AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        COUNT(*) FILTER (WHERE p.AcceptedAnswerId = a.Id) AS AcceptedAnswerCount,
        SUM(CASE WHEN a.CreationDate <= p.CreationDate + INTERVAL '1 hour' THEN 1 ELSE 0 END) AS FastAnswers
    FROM Posts a
    INNER JOIN Posts p ON a.ParentId = p.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= '2020-01-01'
    GROUP BY a.ParentId, a.OwnerUserId
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBasedBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= '2020-01-01'
    GROUP BY b.UserId
),
EditActivity AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.Id END) AS SuggestedEditCount,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2020-01-01'
        AND ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY ph.PostId, ph.UserId
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.JoinYear,
    tu.YearRank,
    COUNT(DISTINCT qm.QuestionId) AS QuestionsAsked,
    ROUND(AVG(qm.Score), 2) AS AvgQuestionScore,
    ROUND(AVG(qm.ViewCount), 2) AS AvgViewCount,
    SUM(qm.UpVotes) AS TotalQuestionUpvotes,
    SUM(qm.DownVotes) AS TotalQuestionDownvotes,
    ROUND(AVG(qm.AnswerCount), 2) AS AvgAnswersReceived,
    COUNT(DISTINCT CASE WHEN qm.HasAcceptedAnswer > 0 THEN qm.QuestionId END) AS QuestionsWithAcceptedAnswer,
    COALESCE(SUM(ap.AnswerCount), 0) AS TotalAnswersProvided,
    ROUND(COALESCE(AVG(ap.AvgAnswerScore), 0), 2) AS AvgAnswerScore,
    COALESCE(SUM(ap.AcceptedAnswerCount), 0) AS TotalAcceptedAnswers,
    COALESCE(ba.GoldBadges, 0) AS GoldBadges,
    COALESCE(ba.SilverBadges, 0) AS SilverBadges,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(SUM(ea.EditCount), 0) AS TotalEdits,
    COALESCE(SUM(ea.SuggestedEditCount), 0) AS SuggestedEdits,
    ROUND(AVG(qm.LinkedCount), 2) AS AvgLinksPerQuestion,
    CASE 
        WHEN COUNT(DISTINCT qm.QuestionId) > 0 
        THEN ROUND(COALESCE(SUM(ap.AnswerCount), 0)::numeric / COUNT(DISTINCT qm.QuestionId), 2)
        ELSE 0 
    END AS AnswerToQuestionRatio,
    CASE 
        WHEN COALESCE(SUM(ap.AnswerCount), 0) > 0 
        THEN ROUND(COALESCE(SUM(ap.AcceptedAnswerCount), 0)::numeric / SUM(ap.AnswerCount) * 100, 2)
        ELSE 0 
    END AS AcceptanceRate
FROM TopUsersByReputation tu
LEFT JOIN QuestionMetrics qm ON tu.Id = qm.OwnerUserId
LEFT JOIN AnswerPerformance ap ON tu.Id = ap.AnswererId
LEFT JOIN BadgeAchievements ba ON tu.Id = ba.UserId
LEFT JOIN EditActivity ea ON tu.Id = ea.UserId
WHERE tu.YearRank <= 100
GROUP BY tu.Id, tu.DisplayName, tu.Reputation, tu.JoinYear, tu.YearRank,
         ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges
HAVING COUNT(DISTINCT qm.QuestionId) > 0 OR COALESCE(SUM(ap.AnswerCount), 0) > 0
ORDER BY tu.Reputation DESC, TotalAcceptedAnswers DESC, tu.YearRank
LIMIT 500;
