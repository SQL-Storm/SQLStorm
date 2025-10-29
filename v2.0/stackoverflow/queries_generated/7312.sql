-- {"query": "7312.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1569} 
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
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(DISTINCT p.Id) * 100.0) / NULLIF((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id), 0)
            ELSE 0 
        END AS PostPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeName,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END AS VoteCategory,
        DATEDIFF(DAY, p.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore,
        NTILE(4) OVER (ORDER BY p.Score) AS ScoreQuartile,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
ComplexJoin AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.AgeInDays,
        COALESCE(pa.PostTypeName, 'Unknown') AS PostTypeName,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END AS ReputationTier,
        COALESCE(us.PostCount, 0) AS UserPostCount,
        COALESCE(us.BadgeCount, 0) AS UserBadgeCount,
        us.AvgPostScore,
        us.PostPercentage,
        pa.VoteCategory,
        pa.EngagementCount,
        pa.RankByScore,
        pa.ScoreQuartile,
        CASE 
            WHEN pa.Score > pa.PrevScore THEN 'Increasing'
            WHEN pa.Score < pa.PrevScore THEN 'Decreasing'
            ELSE 'Stable'
        END AS ScoreTrend,
        CASE 
            WHEN pa.Score > 0 AND pa.Score < 10 THEN 'LowInterest'
            WHEN pa.Score >= 10 AND pa.Score < 50 THEN 'MediumInterest'
            WHEN pa.Score >= 50 THEN 'HighInterest'
            ELSE 'NoInterest'
        END AS InterestLevel
    FROM PostAnalysis pa
    LEFT JOIN Users u ON pa.OwnerUserId = u.Id
    LEFT JOIN UserStats us ON pa.OwnerUserId = us.UserId
    WHERE pa.Score IS NOT NULL AND pa.Title IS NOT NULL
)
SELECT 
    cj.OwnerName,
    cj.PostTypeName,
    cj.ReputationTier,
    COUNT(*) AS PostCount,
    AVG(cj.Score) AS AvgScore,
    SUM(cj.ViewCount) AS TotalViews,
    MIN(cj.AgeInDays) AS MinAge,
    MAX(cj.AgeInDays) AS MaxAge,
    COUNT(DISTINCT CASE WHEN cj.InterestLevel = 'HighInterest' THEN cj.PostId END) AS HighInterestPosts,
    COUNT(DISTINCT CASE WHEN cj.ScoreTrend = 'Increasing' THEN cj.PostId END) AS IncreasingPosts,
    STRING_AGG(
        CASE 
            WHEN cj.PostTypeName = 'Question' THEN CONCAT(cj.Title, ' (Score: ', cj.Score, ')')
            ELSE NULL 
        END, 
        '; '
    ) AS TopQuestions,
    STRING_AGG(
        CASE 
            WHEN cj.PostTypeName = 'Answer' THEN CONCAT('Answer to: ', cj.Title, ' (Score: ', cj.Score, ')')
            ELSE NULL 
        END, 
        '; '
    ) AS TopAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cj.OwnerUserId AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cj.OwnerUserId AND p.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = cj.OwnerUserId AND v.VoteTypeId = 2) AS UpvotesReceived,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = cj.OwnerUserId) AS CommentsMade,
    (SELECT CASE WHEN EXISTS(SELECT 1 FROM Posts p WHERE p.OwnerUserId = cj.OwnerUserId AND p.Score > 100) THEN 1 ELSE 0 END) AS HasHighScoringPost,
    CASE 
        WHEN cj.OwnerName IS NULL THEN 'Orphaned'
        WHEN cj.ReputationTier = 'Elite' THEN 'Premium'
        WHEN cj.ReputationTier = 'Expert' THEN 'Professional'
        ELSE 'Regular'
    END AS UserClassification,
    CASE 
        WHEN AVG(cj.Score) > 50 AND AVG(cj.ViewCount) > 1000 THEN 'Active'
        WHEN AVG(cj.Score) > 10 AND AVG(cj.ViewCount) > 100 THEN 'Moderate'
        ELSE 'Passive'
    END AS ActivityLevel,
    ROW_NUMBER() OVER (ORDER BY AVG(cj.Score) DESC) AS OverallRanking,
    PERCENT_RANK() OVER (ORDER BY AVG(cj.Score)) AS ScorePercentile,
    AVG(cj.Score) - AVG(AVG(cj.Score)) OVER() AS ScoreDeviation
FROM ComplexJoin cj
WHERE cj.OwnerUserId IS NOT NULL
GROUP BY cj.OwnerName, cj.ReputationTier, cj.PostTypeName
HAVING COUNT(*) > 0
ORDER BY AVG(cj.Score) DESC, COUNT(*) DESC
LIMIT 1000;