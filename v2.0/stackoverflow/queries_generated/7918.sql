-- {"query": "7918.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2056} 
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCountAdjusted,
        COALESCE(p.CommentCount, 0) as CommentCountAdjusted,
        COALESCE(CAST(p.Tags AS TEXT), '') as TagsAdjusted,
        LEN(CAST(p.Tags AS TEXT)) as TagLength,
        COALESCE(CAST(p.Title AS TEXT), '') as TitleAdjusted,
        CASE 
            WHEN p.ViewCount IS NULL OR p.ViewCount = 0 THEN 0
            WHEN p.Score IS NULL OR p.Score = 0 THEN 1
            ELSE CAST((p.ViewCount * p.Score) AS FLOAT) / (p.ViewCount + p.Score + 1)
        END as QualityScore,
        CASE 
            WHEN p.Score > 0 AND p.ViewCount > 500 THEN 3
            WHEN p.Score > 0 AND p.ViewCount > 100 THEN 2
            WHEN p.Score >= 0 AND p.ViewCount > 0 THEN 1
            ELSE 0
        END as PopularityLevel
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        TagName,
        Count as TagCount,
        ExcerptPostId,
        WikiPostId,
        IsModeratorOnly,
        IsRequired,
        CASE 
            WHEN TagCount > 1000 THEN 'Very Popular'
            WHEN TagCount > 100 THEN 'Popular'
            WHEN TagCount > 10 THEN 'Moderate'
            ELSE 'Low'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY Count DESC) as RankByPopularity
    FROM Tags
    WHERE TagName IS NOT NULL AND TagName != ''
),
UserPostActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as PostRank,
        LAG(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) as PrevScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) as PrevPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
),
ComplexAggregations AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        COUNT(DISTINCT ua.PostId) as TotalPostsByUser,
        AVG(ua.Score) as AvgScore,
        MAX(ua.Score) as MaxScore,
        MIN(ua.Score) as MinScore,
        SUM(ua.Score) as TotalScore,
        COUNT(CASE WHEN ua.PostTypeId = 1 THEN 1 END) as QuestionsByUser,
        COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) as AnswersByUser,
        COUNT(DISTINCT CASE WHEN ua.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN ua.PostId END) as RecentPosts,
        AVG(CAST(DATEDIFF(DAY, ua.PrevPostDate, ua.CreationDate) AS FLOAT)) as AvgDaysSinceLastPost
    FROM UserPostActivity ua
    GROUP BY ua.UserId, ua.DisplayName
),
FinalResults AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        COALESCE(ps.TotalQuestionScore, 0) as TotalQuestionScore,
        COALESCE(ps.TotalAnswerScore, 0) as TotalAnswerScore,
        ps.QualityScore,
        COALESCE(TA.TagPopularity, 'Unknown') as TagPopularity,
        COALESCE(TA.RankByPopularity, 0) as TagRank,
        COALESCE(CA.TotalPostsByUser, 0) as AggregatedPosts,
        COALESCE(CA.AvgScore, 0) as AggregatedAvgScore,
        COALESCE(CA.MaxScore, 0) as AggregatedMaxScore,
        CASE 
            WHEN uas.Reputation > 5000 AND uas.TotalPosts > 20 THEN 'Veteran'
            WHEN uas.Reputation > 1000 AND uas.TotalPosts > 5 THEN 'Experienced'
            WHEN uas.Reputation > 500 AND uas.TotalPosts > 1 THEN 'Beginner'
            ELSE 'New'
        END as UserLevel,
        CASE 
            WHEN uas.UpVotes > uas.DownVotes * 2 THEN 'Upvoter'
            WHEN uas.DownVotes > uas.UpVotes * 2 THEN 'Downvoter'
            ELSE 'Neutral'
        END as VotingPattern,
        CASE 
            WHEN ps.PostType = 'Question' AND ps.AnswerCount > 0 THEN 'Answered Question'
            WHEN ps.PostType = 'Question' AND ps.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN ps.PostType = 'Answer' THEN 'Answered Post'
            ELSE 'Other'
        END as PostStatus,
        COALESCE(psa.AnswerCountAdjusted, 0) as AdjustedAnswerCount,
        COALESCE(psa.CommentCountAdjusted, 0) as AdjustedCommentCount,
        CASE 
            WHEN psa.Score IS NOT NULL THEN 
                ROUND(CAST((psa.Score * 100.0 / NULLIF(ps.MaxScore, 0)) AS FLOAT), 2)
            ELSE 0 
        END as ScorePercentile
    FROM UserActivityStats uas
    LEFT JOIN PostStats ps ON uas.UserId = ps.OwnerUserId AND ps.PostTypeId = 1
    LEFT JOIN TagAnalysis TA ON uas.LastPostDate IS NOT NULL
    LEFT JOIN ComplexAggregations CA ON uas.UserId = CA.UserId
    LEFT JOIN PostStats psa ON psa.OwnerUserId = uas.UserId
    WHERE (psa.PostType = 'Question' OR psa.PostType IS NULL)
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Views,
    TotalPosts,
    Questions,
    Answers,
    Comments,
    Badges,
    LastPostDate,
    TotalQuestionScore,
    TotalAnswerScore,
    QualityScore,
    TagPopularity,
    TagRank,
    AggregatedPosts,
    AggregatedAvgScore,
    AggregatedMaxScore,
    UserLevel,
    VotingPattern,
    PostStatus,
    AdjustedAnswerCount,
    AdjustedCommentCount,
    ScorePercentile,
    CASE 
        WHEN TotalPosts > 50 AND TotalQuestionScore > 100 THEN 'Highly Engaged'
        WHEN TotalPosts > 20 AND TotalQuestionScore > 50 THEN 'Engaged'
        WHEN TotalPosts > 5 AND TotalQuestionScore > 10 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END as EngagementLevel
FROM FinalResults
WHERE UserId IS NOT NULL
    AND DisplayName IS NOT NULL
    AND Reputation IS NOT NULL
    AND TotalPosts IS NOT NULL
ORDER BY Reputation DESC, TotalPosts DESC, TotalQuestionScore DESC
LIMIT 1000;