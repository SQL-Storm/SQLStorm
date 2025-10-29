-- {"query": "7343.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2039} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS HighScoringAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        COALESCE(p.AnswerCount, 0) AS AnswerCountCorrected,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostType,
        CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        CASE WHEN p.PostTypeId = 1 THEN 
            CASE WHEN p.AnswerCount > 0 THEN 'Has Answers' ELSE 'No Answers' END 
            ELSE 'Not Question' END AS AnswerStatus,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2), 
            0
        ) AS UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3), 
            0
        ) AS DownvoteCount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) AS ViewDecile,
        (COALESCE(p.ViewCount, 0) * COALESCE(p.Score, 0)) AS ViewScoreProduct,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2020-01-01'
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END AS TagCategory,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END AS AccessLevel,
        (t.Count * 0.75 + (SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%')) AS TagRelevanceScore
    FROM Tags t
    WHERE t.Count > 10
),
ComplexJoinAnalysis AS (
    SELECT 
        ps.UserId,
        ps.DisplayName,
        ps.Reputation,
        ps.PostCount,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.TotalQuestionScore,
        ps.TotalAnswerScore,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCountCorrected,
        pa.PostType,
        pa.HasAcceptedAnswer,
        pa.AnswerStatus,
        pa.UpvoteCount,
        pa.DownvoteCount,
        pa.ScoreRank,
        pa.ViewDecile,
        pa.ViewScoreProduct,
        pa.UserPostSequence,
        pa.PreviousScore,
        pa.PreviousPostDate,
        ts.TagId,
        ts.TagName,
        ts.TagCount,
        ts.TagRelevanceScore,
        CASE WHEN ps.Reputation > 10000 THEN 'High' 
             WHEN ps.Reputation > 5000 THEN 'Medium' 
             ELSE 'Low' END AS ReputationTier,
        ROW_NUMBER() OVER (PARTITION BY ps.UserId ORDER BY pa.CreationDate DESC) AS RecentPosts,
        DENSE_RANK() OVER (ORDER BY pa.ViewCount DESC) AS ViewRank,
        PERCENT_RANK() OVER (ORDER BY ps.Reputation) AS ReputationPercentile,
        CUME_DIST() OVER (ORDER BY pa.CreationDate) AS CumulativePostDistribution,
        CASE WHEN pa.Score >= 100 THEN 'Gold' 
             WHEN pa.Score >= 50 THEN 'Silver' 
             ELSE 'Bronze' END AS PostQualityTier
    FROM UserStats ps
    INNER JOIN PostAnalysis pa ON ps.UserId = pa.OwnerUserId
    LEFT JOIN (
        SELECT DISTINCT p.Id AS PostId, t.TagName, t.Id AS TagId, t.Count AS TagCount
        FROM Posts p
        INNER JOIN (
            SELECT UNNEST(string_to_array(p.Tags, '><')) AS TagName, p.Id
            FROM Posts p
            WHERE p.Tags IS NOT NULL AND p.Tags != ''
        ) AS tag_split ON p.Id = tag_split.Id
        LEFT JOIN Tags t ON t.TagName = tag_split.TagName
    ) AS TagPost ON pa.PostId = TagPost.PostId
    LEFT JOIN TagStats ts ON TagPost.TagId = ts.TagId
    WHERE pa.CreationDate >= '2020-01-01'
),
FinalAggregation AS (
    SELECT 
        *
    FROM ComplexJoinAnalysis
    WHERE EXISTS (
        SELECT 1 FROM Posts p
        WHERE p.OwnerUserId = ComplexJoinAnalysis.UserId
        AND p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
        AND p.Score > 10
    )
    AND (
        ComplexJoinAnalysis.TagName IS NULL 
        OR ComplexJoinAnalysis.TagRelevanceScore > 100
    )
    AND ComplexJoinAnalysis.ViewCount > 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.TotalQuestionScore,
    fa.TotalAnswerScore,
    fa.ReputationTier,
    fa.ReputationPercentile,
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCountCorrected,
    fa.PostType,
    fa.HasAcceptedAnswer,
    fa.AnswerStatus,
    fa.UpvoteCount,
    fa.DownvoteCount,
    fa.ScoreRank,
    fa.ViewDecile,
    fa.ViewScoreProduct,
    fa.UserPostSequence,
    COALESCE(fa.PreviousScore, 0) AS PreviousScore,
    CASE 
        WHEN fa.PreviousPostDate IS NOT NULL 
        THEN EXTRACT(DAY FROM (fa.CreationDate - fa.PreviousPostDate)) 
        ELSE 0 
    END AS DaysSincePreviousPost,
    fa.TagId,
    fa.TagName,
    fa.TagCount,
    fa.TagRelevanceScore,
    fa.RecentPosts,
    fa.ViewRank,
    fa.CumulativePostDistribution,
    fa.PostQualityTier,
    CASE 
        WHEN fa.Score > 1000 THEN 'Very High'
        WHEN fa.Score > 500 THEN 'High'
        WHEN fa.Score > 100 THEN 'Medium'
        WHEN fa.Score > 0 THEN 'Low'
        ELSE 'None'
    END AS ScoreTier,
    CASE 
        WHEN fa.QuestionCount > 0 THEN 
            ROUND((CAST(fa.AnswerCount AS FLOAT) / CAST(fa.QuestionCount AS FLOAT)) * 100, 2)
        ELSE 0 
    END AS AnswerToQuestionRatio,
    DATEDIFF('day', fa.CreationDate, CURRENT_DATE) AS DaysActive,
    (fa.Reputation * fa.PostCount) AS RepProduct,
    NULLIF(fa.AnswerCount, 0) / NULLIF(fa.QuestionCount, 0) AS AnswerQuestionRatio
FROM FinalAggregation fa
WHERE fa.Reputation > 1000
ORDER BY fa.Reputation DESC, fa.CreationDate DESC
LIMIT 1000
OFFSET 1000;