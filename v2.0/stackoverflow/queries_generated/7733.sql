-- {"query": "7733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2376} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(u.LastAccessDate) as LastAccessDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.Score) AS FLOAT) / CAST(COUNT(DISTINCT p.Id) AS FLOAT)
            ELSE 0 
        END as AvgScorePerPost,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.ViewCount) AS FLOAT) / CAST(COUNT(DISTINCT p.Id) AS FLOAT)
            ELSE 0 
        END as AvgViewsPerPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END as IsAnswered,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END as IsClosed,
        CASE 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
            ELSE 0
        END as IsCommunityOwned,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) as UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) as NextScore,
        CASE 
            WHEN p.Score > LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) THEN 'Improved'
            WHEN p.Score < LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) THEN 'Degraded'
            ELSE 'Stable'
        END as RatingChange,
        UPPER(p.Title) as TitleUpper,
        LENGTH(p.Title) as TitleLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                STRING_AGG(TRIM(BOTH '<>' FROM TRIM(unnest(string_to_array(p.Tags, '><')))), ', ')
            ELSE NULL
        END as TagList,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as UpVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as DownVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
            0
        ) as CommentCountActual
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required Tag'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only Tag'
            ELSE 'Regular Tag'
        END as TagCategory,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
ComplexJoinAnalysis AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName as UserName,
        u.Reputation,
        ps.PostCount,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.BadgeCount,
        ps.TotalScore,
        ps.TotalViews,
        ps.AvgScorePerPost,
        ps.AvgViewsPerPost,
        pa.Id as PostId,
        pa.Title,
        pa.PostType,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount as PostAnswerCount,
        pa.IsAnswered,
        pa.IsClosed,
        pa.IsCommunityOwned,
        pa.FavoriteCount,
        pa.ScoreRank,
        pa.UserPostSequence,
        pa.TitleLength,
        pa.TagList,
        ta.TagName,
        ta.PopularityLevel,
        CASE 
            WHEN pa.Score > ps.AvgScorePerPost THEN 'Above Average'
            WHEN pa.Score < ps.AvgScorePerPost THEN 'Below Average'
            ELSE 'Average'
        END as ScorePerformance,
        CASE 
            WHEN pa.ViewCount > ps.AvgViewsPerPost THEN 'Above Average Views'
            WHEN pa.ViewCount < ps.AvgViewsPerPost THEN 'Below Average Views'
            ELSE 'Average Views'
        END as ViewPerformance,
        CASE 
            WHEN pa.IsAnswered = 1 AND pa.PostType = 'Question' THEN 
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pa.Id AND p2.PostTypeId = 2)
            ELSE 0
        END as AnswerCountReal,
        CASE 
            WHEN pa.PostTypeId = 1 THEN DATEDIFF(DAY, pa.CreationDate, NOW()) 
            WHEN pa.PostTypeId = 2 THEN DATEDIFF(DAY, pa.CreationDate, NOW()) 
            ELSE 0 
        END as DaysOld
    FROM UserStats u
    INNER JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.TagList LIKE CONCAT('%', ta.TagName, '%')
    WHERE u.Id = u.Id -- Simple filter to ensure all records pass
)
SELECT 
    *,
    CASE 
        WHEN DaysOld > 30 AND Score > 100 THEN 'Highly Active and High Scoring'
        WHEN DaysOld > 30 AND Score <= 100 THEN 'Low Score but Active'
        WHEN DaysOld <= 30 AND Score > 100 THEN 'Very Active and High Scoring'
        ELSE 'Regular Activity'
    END as ActivityScoreLevel,
    ROW_NUMBER() OVER (ORDER BY TotalScore DESC, PostCount DESC) as OverallRanking,
    RANK() OVER (PARTITION BY PostType ORDER BY Score DESC) as TypeRanking,
    PERCENT_RANK() OVER (ORDER BY Score) as ScorePercentile,
    CASE 
        WHEN AvgScorePerPost > 50 THEN 'High Performing User'
        WHEN AvgScorePerPost > 10 THEN 'Medium Performing User'
        ELSE 'Low Performing User'
    END as UserPerformanceCategory,
    COALESCE(
        CASE 
            WHEN QuestionCount > 0 THEN 
                CAST(AnswerCount AS FLOAT) / CAST(QuestionCount AS FLOAT) 
            ELSE 0 
        END, 
        0
    ) as AnswerToQuestionRatio,
    COALESCE(
        CASE 
            WHEN AnswerCount > 0 THEN 
                CAST(CommentCount AS FLOAT) / CAST(AnswerCount AS FLOAT) 
            ELSE 0 
        END, 
        0
    ) as CommentToAnswerRatio,
    CASE 
        WHEN IsClosed = 1 THEN 'Closed'
        WHEN IsCommunityOwned = 1 THEN 'Community Owned'
        WHEN IsAnswered = 1 THEN 'Answered'
        ELSE 'Open'
    END as PostStatus,
    CASE 
        WHEN FavoriteCount > 10 THEN 'Popular'
        WHEN FavoriteCount > 5 THEN 'Moderate'
        WHEN FavoriteCount > 0 THEN 'Low'
        ELSE 'None'
    END as FavoritedLevel,
    COALESCE(
        CASE 
            WHEN ScoreChange IS NOT NULL THEN 
                (Score - LAG(Score) OVER (ORDER BY CreationDate)) 
            ELSE 0 
        END,
        0
    ) as ScoreChange,
    (CASE 
        WHEN AnswerCount > 0 THEN 
            CAST(Score AS FLOAT) / CAST(AnswerCount AS FLOAT)
        ELSE 0 
    END) as ScorePerAnswer
FROM ComplexJoinAnalysis
WHERE UserId IS NOT NULL
  AND PostId IS NOT NULL
  AND DaysOld >= 0
  AND Score >= -1000
  AND ViewCount >= 0
  AND PostType IN ('Question', 'Answer', 'Other') 
  AND (ScorePerformance = 'Above Average' OR ViewPerformance = 'Above Average Views')
  AND (
    AnswerCountReal > 0 OR 
    CommentCountActual > 0 OR 
    FavoriteCount > 0 OR 
    IsClosed = 1 OR 
    IsAnswered = 1 OR 
    Score > 50
  )
  AND (
    PopularityLevel IN ('Highly Popular', 'Popular') OR
    PopularityLevel IS NULL
  )
  AND (
    CASE 
        WHEN Score > 1000 THEN 1 
        WHEN ViewCount > 1000 THEN 1 
        ELSE 0 
    END = 1
  )
  AND NOT EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.Id = PostId 
    AND p.PostTypeId IN (1, 2) 
    AND (
        (p.OwnerUserId = UserId AND p.OwnerUserId IS NOT NULL) OR
        (p.ParentId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = UserId AND PostTypeId = 2
        ) AND p.PostTypeId = 2)
    )
    AND p.Score > 10000
  )
ORDER BY TotalScore DESC, PostCount DESC, Score DESC
LIMIT 5000;