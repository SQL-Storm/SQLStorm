-- {"query": "7706.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1867} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT p.Tags, ', ') AS AllTags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS RankByPostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        CommentCount,
        VoteCount,
        LastPostDate,
        AvgPostScore,
        AllTags,
        RankByReputation,
        RankByPostCount,
        CASE 
            WHEN Reputation > 100000 THEN 'Legendary'
            WHEN Reputation > 50000 THEN 'Master'
            WHEN Reputation > 10000 THEN 'Expert'
            WHEN Reputation > 5000 THEN 'Advanced'
            ELSE 'Beginner'
        END AS ReputationTier,
        COALESCE(AllTags, 'No Tags') as ProcessedTags
    FROM UserActivityStats
    WHERE TotalPosts > 0
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 10 THEN 'Highly Rated'
            WHEN p.Score > 5 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Low Rated'
            ELSE 'Unrated'
        END AS RatingCategory,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS RankByScore,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS PercentileByScore,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByUser,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostSequenceByUser,
        COALESCE(p.Tags, 'No Tags') AS ProcessedTags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Not a Question'
        END AS QuestionStatus
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
ComplexAnalysis AS (
    SELECT 
        ta.UserId,
        ta.DisplayName,
        ta.Reputation,
        ta.TotalPosts,
        ta.QuestionCount,
        ta.AnswerCount,
        ta.BadgeCount,
        ta.CommentCount,
        ta.VoteCount,
        ta.LastPostDate,
        ta.AvgPostScore,
        ta.ProcessedTags,
        ta.RankByReputation,
        ta.RankByPostCount,
        ta.ReputationTier,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount AS PostAnswerCount,
        pa.CommentCount AS PostCommentCount,
        pa.CreationDate AS PostCreationDate,
        pa.PostTypeId,
        pa.PostType,
        pa.RatingCategory,
        pa.RankByScore,
        pa.PercentileByScore,
        pa.PreviousScore,
        pa.NextScore,
        pa.AvgScoreByUser,
        pa.PostSequenceByUser,
        pa.ProcessedTags AS PostProcessedTags,
        pa.QuestionStatus,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN pa.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END AS ScorePerformance,
        CASE 
            WHEN pa.ViewCount > 1000 THEN 'High Traffic'
            WHEN pa.ViewCount > 500 THEN 'Medium Traffic'
            WHEN pa.ViewCount > 100 THEN 'Low Traffic'
            ELSE 'Very Low Traffic'
        END AS TrafficLevel,
        (pa.Score - COALESCE(pa.PreviousScore, 0)) AS ScoreChange,
        (pa.Score - COALESCE(pa.NextScore, 0)) AS ScoreChangeFromNext,
        IIF(pa.PostSequenceByUser = 1, 'New User', 'Experienced User') AS UserExperienceLevel,
        CASE 
            WHEN ta.BadgeCount > 50 THEN 'Badge Collector'
            WHEN ta.BadgeCount > 25 THEN 'Moderate Badge User'
            WHEN ta.BadgeCount > 0 THEN 'Badge Beginner'
            ELSE 'No Badges'
        END AS BadgeStatus
    FROM TopUsers ta
    LEFT JOIN PostAnalysis pa ON ta.UserId = pa.OwnerUserId
    WHERE ta.UserId IS NOT NULL
)
SELECT 
    TOP 1000 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.BadgeCount,
    ca.CommentCount,
    ca.VoteCount,
    ca.LastPostDate,
    ca.AvgPostScore,
    ca.ProcessedTags,
    ca.RankByReputation,
    ca.RankByPostCount,
    ca.ReputationTier,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.PostAnswerCount,
    ca.PostCommentCount,
    ca.PostCreationDate,
    ca.PostTypeId,
    ca.PostType,
    ca.RatingCategory,
    ca.RankByScore,
    ca.PercentileByScore,
    ca.PreviousScore,
    ca.NextScore,
    ca.AvgScoreByUser,
    ca.PostSequenceByUser,
    ca.ProcessedTags AS PostProcessedTags,
    ca.QuestionStatus,
    ca.ScorePerformance,
    ca.TrafficLevel,
    ca.ScoreChange,
    ca.ScoreChangeFromNext,
    ca.UserExperienceLevel,
    ca.BadgeStatus,
    CASE 
        WHEN ca.BadgeCount > 0 AND ca.QuestionCount > 5 THEN 1
        WHEN ca.BadgeCount = 0 AND ca.QuestionCount BETWEEN 1 AND 5 THEN 2
        ELSE 3
    END AS UserSegment,
    ROW_NUMBER() OVER (PARTITION BY ca.UserId ORDER BY ca.PostCreationDate) AS SequentialPostNumber,
    COUNT(*) OVER (PARTITION BY ca.UserId) AS TotalPostsByUser,
    RANK() OVER (ORDER BY ca.Reputation DESC, ca.Score DESC) AS OverallRank,
    NTILE(4) OVER (ORDER BY ca.Score DESC) AS ScoreQuartile,
    IIF(ca.ReputationTier = 'Legendary' AND ca.BadgeCount > 50 AND ca.QuestionCount > 100, 1, 0) AS EliteContributorFlag,
    CASE 
        WHEN ca.ScoreChange > 5 THEN 'Significant Improvement'
        WHEN ca.ScoreChange < -5 THEN 'Significant Decline'
        WHEN ca.ScoreChange BETWEEN -5 AND 5 THEN 'Stable'
        ELSE 'Unknown'
    END AS ScoreTrend,
    ISNULL(ca.Title, 'No Title') AS SafeTitle,
    ISNULL(ca.ProcessedTags, 'None') AS SafeTags
FROM ComplexAnalysis ca
WHERE ca.UserId IS NOT NULL 
    AND ca.PostId IS NOT NULL
    AND ca.Reputation > 100
ORDER BY ca.Score DESC, ca.Reputation DESC, ca.PostCreationDate DESC;