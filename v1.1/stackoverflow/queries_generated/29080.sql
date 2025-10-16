-- {"query": "29080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2067} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(p.Tags, '') AS CleanTags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS GlobalPostRank,
        LAG(p.Score) OVER (ORDER BY p.Score DESC) AS PrevScore,
        LEAD(p.Score) OVER (ORDER BY p.Score DESC) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser,
        NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile,
        COALESCE(p.Title, '') AS CleanTitle,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Zero'
        END AS ScoreCategory,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountSubquery,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) 
            THEN 'HasUpvotes'
            ELSE 'NoUpvotes'
        END AS HasUpvotesIndicator,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS UserBadgeCount,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END AS PostTypeClassification,
        COALESCE(p.Body, '') AS CleanBody,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) AS AnswerCountSubquery
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(DAY, u.CreationDate, MAX(p.CreationDate)) AS DaysSinceUserCreation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore,
        SUM(p.Score) AS TotalScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'HighlyActive'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'ModeratelyActive'
            ELSE 'Inactive'
        END AS ActivityLevel,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            WHEN u.Reputation > 100 THEN 'Beginner'
            ELSE 'Newbie'
        END AS ReputationTier,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostTagAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.Title,
        ps.Score,
        ps.Tags,
        ps.CleanTags,
        STRING_TO_ARRAY(COALESCE(ps.Tags, ''), '><') AS TagArray,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags LIKE '%<%' THEN 
                (SELECT COUNT(*) FROM UNNEST(STRING_TO_ARRAY(ps.Tags, '><')) AS tag WHERE tag != '')
            ELSE 0
        END AS TagCount,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags LIKE '%<%' THEN 
                (SELECT STRING_AGG(tag, ' | ') FROM UNNEST(STRING_TO_ARRAY(ps.Tags, '><')) AS tag WHERE tag != '')
            ELSE ''
        END AS TagList,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags LIKE '%<%' THEN 
                (SELECT MAX(length(tag)) FROM UNNEST(STRING_TO_ARRAY(ps.Tags, '><')) AS tag WHERE tag != '')
            ELSE 0
        END AS MaxTagLength,
        ps.PostTypeDesc,
        ps.CreationDate,
        ps.CommentCountSubquery
    FROM PostStats ps
),
RankedQuestions AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.TagList,
        pa.TagCount,
        pa.CreationDate,
        pa.CommentCountSubquery,
        ROW_NUMBER() OVER (PARTITION BY pa.TagList ORDER BY pa.Score DESC) AS TagScoreRank,
        RANK() OVER (ORDER BY pa.Score DESC) AS GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY pa.Score DESC) AS UniqueScoreRank,
        PERCENT_RANK() OVER (ORDER BY pa.Score DESC) AS ScorePercentileRank,
        CUME_DIST() OVER (ORDER BY pa.Score DESC) AS ScoreCumulativeDist
    FROM PostTagAnalysis pa
    WHERE pa.PostTypeDesc = 'Question' AND pa.Score > 0
),
ComplexAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.TotalScore,
        ua.ActivityLevel,
        ua.ReputationTier,
        ua.QuestionCount,
        ua.AnswerCount,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.TagList,
        pa.TagCount,
        pa.TagScoreRank,
        pa.GlobalScoreRank,
        pa.ScorePercentileRank,
        pa.ScoreCumulativeDist,
        ps.UserPostRank,
        ps.GlobalPostRank,
        ps.ScoreCategory,
        ps.ScorePercentile,
        ps.CleanTitle,
        ps.AnswerCountSubquery,
        ps.CommentCountSubquery,
        ps.HasUpvotesIndicator,
        ps.UserBadgeCount,
        ps.PostTypeClassification,
        ps.CleanBody,
        ps.PrevScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.TotalPostsByUser,
        ps.DaysSinceUserCreation,
        (ua.TotalScore - (SELECT AVG(TotalScore) FROM UserActivity)) AS ScoreVsAvgDiff,
        CASE 
            WHEN (ua.MaxPostScore - ua.AvgPostScore) > (SELECT STDDEV(TotalScore) FROM UserActivity) 
            THEN 'AboveAvgMax'
            ELSE 'Normal'
        END AS MaxScoreStatus,
        CASE 
            WHEN pa.Score = (SELECT MAX(Score) FROM Posts WHERE PostTypeId = 1) 
            THEN 'TopQuestion'
            ELSE 'RegularQuestion'
        END AS QuestionStatus,
        ABS(pa.Score - (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) AS ScoreFromAvg,
        CEIL(pa.Score / (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) AS ScoreMultiplier
    FROM UserActivity ua
    INNER JOIN RankedQuestions pa ON ua.UserId = (
        SELECT p.OwnerUserId 
        FROM Posts p 
        WHERE p.Id = pa.PostId 
        AND p.OwnerUserId IS NOT NULL
    )
    INNER JOIN PostStats ps ON pa.PostId = ps.Id
)
SELECT 
    *,
    CASE 
        WHEN UserId IN (SELECT Id FROM Users WHERE Reputation > 100000) THEN 'Elite'
        WHEN UserId IN (SELECT Id FROM Users WHERE Reputation > 50000) THEN 'Veteran'
        ELSE 'Regular'
    END AS UserStatus,
    CASE 
        WHEN ScorePercentile BETWEEN 1 AND 10 THEN 'TopDecile'
        WHEN ScorePercentile BETWEEN 11 AND 25 THEN 'SecondQuartile'
        WHEN ScorePercentile BETWEEN 26 AND 50 THEN 'ThirdQuartile'
        ELSE 'BottomHalf'
    END AS ScoreQuartile,
    CASE 
        WHEN DaysSinceUserCreation > 365 AND TotalPosts > 100 THEN 'VeteranActive'
        WHEN DaysSinceUserCreation > 365 THEN 'LongTimeActive'
        ELSE 'NewActive'
    END AS UserEngagementStatus,
    CASE 
        WHEN AvgPostScore > (SELECT AVG(AvgPostScore) FROM UserActivity) THEN 'AboveAverage'
        ELSE 'BelowAverage'
    END AS UserPerformance,
    'StatisticalAnalysis' AS AnalysisType
FROM ComplexAnalysis
WHERE Score > 0
  AND (CommentCountSubquery > 0 OR AnswerCountSubquery > 0)
  AND TagCount > 0
  AND NOT EXISTS (
      SELECT 1 FROM Posts p 
      WHERE p.Id = PostId AND p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
      AND p.Score > 1000
  )
  AND UserBadgeCount > 10
ORDER BY Score DESC, ScorePercentile ASC
LIMIT 1000;