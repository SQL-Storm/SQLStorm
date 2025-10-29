-- {"query": "7886.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2049} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.OwnerDisplayName, 'Anonymous') as AuthorName,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VoteCategory,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 5000 THEN 'Popular'
            WHEN p.ViewCount > 1000 THEN 'Noticeable'
            ELSE 'Normal'
        END as Popularity,
        (p.Score + COALESCE(p.ViewCount, 0) / 100 + COALESCE(p.AnswerCount, 0) * 5) as PerformanceScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as UserPostCount,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as UserQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as UserAnswers,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) as PositiveScorePosts,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) as NegativeScorePosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName
),

ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.PostType,
        pa.AuthorName,
        pa.VoteCategory,
        pa.AgeInDays,
        pa.Popularity,
        pa.PerformanceScore,
        CASE 
            WHEN pa.Score > 0 AND pa.ViewCount > 0 THEN 
                CAST((pa.Score * 1.0 / pa.ViewCount) * 100 AS DECIMAL(10,2))
            ELSE 0 
        END as ScorePerView,
        CASE 
            WHEN pa.AnswerCount > 0 THEN 
                CAST(pa.CommentCount * 1.0 / pa.AnswerCount AS DECIMAL(10,2))
            ELSE 0 
        END as CommentsPerAnswer,
        DENSE_RANK() OVER (PARTITION BY pa.PostType ORDER BY pa.PerformanceScore DESC) as PerformanceRankPerType
    FROM PostPerformance pa
)

SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.Comments,
    uas.Badges,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.RankByReputation,
    uas.RankByPostCount,
    COALESCE(ups.UserPostCount, 0) as UserPostCount,
    COALESCE(ups.AvgScore, 0) as UserAvgScore,
    COALESCE(ups.MaxScore, 0) as UserMaxScore,
    COALESCE(ups.UserQuestions, 0) as UserQuestions,
    COALESCE(ups.UserAnswers, 0) as UserAnswers,
    COALESCE(ups.PositiveScorePosts, 0) as PositiveScorePosts,
    COALESCE(ups.NegativeScorePosts, 0) as NegativeScorePosts,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.PostType,
    ca.AuthorName,
    ca.VoteCategory,
    ca.AgeInDays,
    ca.Popularity,
    ca.PerformanceScore,
    ca.ScorePerView,
    ca.CommentsPerAnswer,
    ca.PerformanceRankPerType,
    CASE 
        WHEN uas.TotalPosts > 0 AND ca.AnswerCount > 0 THEN 
            CASE 
                WHEN ca.AnswerCount > uas.Answers THEN 'AboveAverageAnswerCount'
                WHEN ca.AnswerCount = uas.Answers THEN 'AverageAnswerCount'
                ELSE 'BelowAverageAnswerCount'
            END
        ELSE 'NoAnswers'
    END as AnswerCountComparison,
    CASE 
        WHEN ca.AgeInDays > 365 THEN 'LongLived'
        WHEN ca.AgeInDays > 90 THEN 'MediumLived'
        WHEN ca.AgeInDays > 30 THEN 'ShortLived'
        ELSE 'New'
    END as PostAgeCategory,
    CASE 
        WHEN ca.PerformanceRankPerType <= 5 THEN 'Top5Performance'
        WHEN ca.PerformanceRankPerType <= 10 THEN 'Top10Performance'
        ELSE 'OtherPerformance'
    END as PerformanceCategory,
    IIF(uas.Reputation > (SELECT AVG(Reputation) FROM Users), 'AboveAvgReputation', 'BelowAvgReputation') as ReputationComparison,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ca.PostId AND c.UserId = uas.UserId) as UserCommentsOnPost,
    COALESCE(
        (SELECT TOP 1 ph.CreationDate 
         FROM PostHistory ph 
         WHERE ph.PostId = ca.PostId AND ph.PostHistoryTypeId IN (10, 11) 
         ORDER BY ph.CreationDate DESC), 
        '1900-01-01'
    ) as LastCloseOrReopenDate,
    CASE WHEN ca.Title LIKE '%[?]%[!%' THEN 'QuestionMarkExclamation' ELSE 'NormalTitle' END as TitleStyle,
    IIF(
        ca.ViewCount > 1000 AND ca.Score > 50 AND ca.AnswerCount > 0, 
        'HighEngagementPost', 
        IIF(
            ca.ViewCount > 500 AND ca.Score > 25, 
            'ModerateEngagementPost', 
            'LowEngagementPost'
        )
    ) as EngagementLevel
FROM UserActivityStats uas
LEFT JOIN UserPostActivity ups ON uas.UserId = ups.UserId
LEFT JOIN ComplexPostAnalysis ca ON ca.PostId = (
    SELECT TOP 1 p.Id 
    FROM Posts p 
    WHERE p.OwnerUserId = uas.UserId 
    AND p.PostTypeId = 1 
    AND p.CreationDate > '2020-01-01'
    ORDER BY p.Score DESC
)
WHERE uas.Reputation > 10000
  AND uas.TotalPosts > 50
  AND (uas.Questions > 10 OR uas.Answers > 10)
  AND EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = uas.UserId 
    AND p.CreationDate > DATEADD(YEAR, -2, GETDATE())
  )
  AND uas.UserId IN (
    SELECT DISTINCT OwnerUserId 
    FROM Posts 
    WHERE OwnerUserId IS NOT NULL 
    GROUP BY OwnerUserId 
    HAVING COUNT(DISTINCT PostTypeId) >= 2
  )
  AND uas.UserId NOT IN (
    SELECT DISTINCT UserId 
    FROM Votes 
    WHERE VoteTypeId IN (4, 12) 
    AND CreationDate > DATEADD(MONTH, -12, GETDATE())
  )
ORDER BY uas.Reputation DESC, ca.PerformanceScore DESC
OFFSET 100 ROWS
FETCH NEXT 25 ROWS ONLY;