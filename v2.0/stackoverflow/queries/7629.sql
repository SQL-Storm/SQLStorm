-- {"query": "7629.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2812}
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Engagement'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 0 THEN 
                (LENGTH(p.Body) - LENGTH(REPLACE(LOWER(p.Body), 'code', '')) + 1) 
            ELSE 0 
        END as CodeBlockCount,
        CASE 
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 0 THEN 
                (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<', '')) + 1) 
            ELSE 0 
        END as HtmlTagCount,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostSequence,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END as ScorePerformance
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserEngagement AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.TotalPosts,
        up.Questions,
        up.Answers,
        up.TotalQuestionScore,
        up.TotalAnswerScore,
        up.AvgQuestionScore,
        up.AvgAnswerScore,
        up.LastPostDate,
        up.BadgeCount,
        up.BadgeNames,
        up.EngagementLevel,
        CASE 
            WHEN up.BadgeCount >= 50 THEN 'Awarded'
            WHEN up.BadgeCount >= 25 THEN 'Recognized'
            WHEN up.BadgeCount >= 10 THEN 'Notable'
            ELSE 'Beginner'
        END as RecognitionLevel,
        RANK() OVER (ORDER BY up.TotalQuestionScore + up.TotalAnswerScore DESC) as TotalScoreRank,
        DENSE_RANK() OVER (ORDER BY up.Reputation DESC) as ReputationRank
    FROM UserPostStats up
    WHERE up.TotalPosts > 0
),
TopPosts AS (
    SELECT 
        pc.PostId,
        pc.Title,
        pc.Score,
        pc.ViewCount,
        pc.CreationDate,
        pc.OwnerUserId,
        pc.ParentId,
        pc.PostTypeId,
        pc.AnswerCount,
        pc.CommentCount,
        pc.FavoriteCount,
        pc.TagCount,
        pc.CodeBlockCount,
        pc.HtmlTagCount,
        pc.PreviousScore,
        pc.PostSequence,
        pc.ScoreRank,
        pc.ViewRank,
        pc.ScorePerformance,
        LAG(pc.Score, 2) OVER (ORDER BY pc.Score DESC) as ScoreLag2,
        LEAD(pc.Score, 2) OVER (ORDER BY pc.Score DESC) as ScoreLead2,
        AVG(pc.Score) OVER (ORDER BY pc.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        PERCENT_RANK() OVER (ORDER BY pc.Score) as ScorePercentile,
        NTILE(4) OVER (ORDER BY pc.Score) as ScoreQuartile
    FROM PostComplexity pc
),
CommentAnalysis AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) as CommentCount,
        STRING_AGG(SUBSTRING(c.Text, 1, 50), ' | ') as SampleComments,
        MIN(c.CreationDate) as FirstCommentDate,
        MAX(c.CreationDate) as LastCommentDate,
        AVG(c.Score) as AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
FinalResult AS (
    SELECT 
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        ue.Questions,
        ue.Answers,
        ue.TotalQuestionScore,
        ue.TotalAnswerScore,
        ue.AvgQuestionScore,
        ue.AvgAnswerScore,
        ue.LastPostDate,
        ue.BadgeCount,
        ue.BadgeNames,
        ue.EngagementLevel,
        ue.RecognitionLevel,
        ue.TotalScoreRank,
        ue.ReputationRank,
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate as PostCreationDate,
        tp.ParentId,
        tp.PostTypeId,
        tp.AnswerCount,
        tp.CommentCount as PostCommentCount,
        tp.FavoriteCount,
        tp.TagCount,
        tp.CodeBlockCount,
        tp.HtmlTagCount,
        tp.PreviousScore,
        tp.PostSequence,
        tp.ScoreRank,
        tp.ViewRank,
        tp.ScorePerformance,
        tp.ScoreLag2,
        tp.ScoreLead2,
        tp.MovingAvgScore,
        tp.ScorePercentile,
        tp.ScoreQuartile,
        COALESCE(ca.CommentCount, 0) as ActualCommentCount,
        ca.SampleComments,
        ca.FirstCommentDate,
        ca.LastCommentDate,
        COALESCE(ca.AvgCommentScore, 0) as AvgCommentScore,
        CASE 
            WHEN tp.Score > 100 THEN 'Viral'
            WHEN tp.Score > 50 THEN 'Popular'
            WHEN tp.Score > 20 THEN 'Noticeable'
            ELSE 'Regular'
        END as PostPopularity,
        CASE 
            WHEN tp.ViewCount > 1000 THEN 'High Visibility'
            WHEN tp.ViewCount > 500 THEN 'Medium Visibility'
            WHEN tp.ViewCount > 100 THEN 'Low Visibility'
            ELSE 'Invisible'
        END as VisibilityStatus,
        CASE 
            WHEN tp.ViewCount > (tp.Score * 10) THEN 'Well-Engaged'
            WHEN tp.ViewCount > (tp.Score * 5) THEN 'Moderately Engaged'
            ELSE 'Needs Attention'
        END as EngagementStatus,
        ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.Score DESC) as TopPostRankByUser,
        CASE 
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2)) 
            THEN 'Above Forum Average'
            ELSE 'Below Forum Average'
        END as ForumPerformance,
        CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - tp.CreationDate)) / 86400) AS INTEGER) as DaysSincePost,
        COALESCE(tp.AnswerCount, 0) as EffectiveAnswerCount,
        COALESCE(tp.CommentCount, 0) as EffectiveCommentCount,
        CASE 
            WHEN tp.HtmlTagCount > tp.CodeBlockCount AND tp.HtmlTagCount > 0 THEN 'HTML Heavy'
            WHEN tp.CodeBlockCount > tp.HtmlTagCount AND tp.CodeBlockCount > 0 THEN 'Code Heavy'
            ELSE 'Balanced'
        END as ContentStyle,
        CASE 
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 10 THEN 'Highly Answered'
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 5 THEN 'Moderately Answered'
            WHEN tp.PostTypeId = 1 THEN 'Lowly Answered'
            ELSE 'Not a Question'
        END as QuestionStatus,
        CASE 
            WHEN tp.Score = (SELECT MAX(Score) FROM Posts WHERE PostTypeId IN (1, 2)) THEN 'Highest Scoring Post'
            WHEN tp.Score = (SELECT MIN(Score) FROM Posts WHERE PostTypeId IN (1, 2)) THEN 'Lowest Scoring Post'
            WHEN tp.Score > 50 THEN 'High Scoring Post'
            ELSE 'Standard Scoring Post'
        END as ScoringTier
    FROM UserEngagement ue
    INNER JOIN TopPosts tp ON ue.UserId = tp.OwnerUserId
    LEFT JOIN CommentAnalysis ca ON tp.PostId = ca.PostId
    WHERE tp.CreationDate >= TIMESTAMP '2015-01-01'
      AND tp.Score >= 0
      AND tp.ViewCount >= 0
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    TotalQuestionScore,
    TotalAnswerScore,
    AvgQuestionScore,
    AvgAnswerScore,
    LastPostDate,
    BadgeCount,
    BadgeNames,
    EngagementLevel,
    RecognitionLevel,
    TotalScoreRank,
    ReputationRank,
    PostId,
    Title,
    Score,
    ViewCount,
    PostCreationDate,
    ParentId,
    PostTypeId,
    AnswerCount,
    PostCommentCount,
    FavoriteCount,
    TagCount,
    CodeBlockCount,
    HtmlTagCount,
    PreviousScore,
    PostSequence,
    ScoreRank,
    ViewRank,
    ScorePerformance,
    ScoreLag2,
    ScoreLead2,
    MovingAvgScore,
    ScorePercentile,
    ScoreQuartile,
    ActualCommentCount,
    SampleComments,
    FirstCommentDate,
    LastCommentDate,
    AvgCommentScore,
    PostPopularity,
    VisibilityStatus,
    EngagementStatus,
    TopPostRankByUser,
    ForumPerformance,
    DaysSincePost,
    EffectiveAnswerCount,
    EffectiveCommentCount,
    ContentStyle,
    QuestionStatus,
    ScoringTier,
    CASE 
        WHEN TotalPosts >= 100 AND BadgeCount >= 100 THEN 'Legend'
        WHEN TotalPosts >= 50 AND BadgeCount >= 50 THEN 'Veteran'
        WHEN Reputation > 10000 THEN 'Expert'
        WHEN TotalPosts >= 25 THEN 'Active Member'
        ELSE 'Regular Member'
    END as UserTier,
    CASE WHEN Reputation > 10000 AND TotalPosts > 50 AND BadgeCount > 25 THEN 1 ELSE 0 END as EliteMemberIndicator,
    CASE 
        WHEN Reputation = (SELECT MAX(Reputation) FROM Users) THEN 'Top Reputation User'
        WHEN Reputation = (SELECT MIN(Reputation) FROM Users) THEN 'Lowest Reputation User'
        WHEN Reputation >= (SELECT AVG(Reputation) FROM Users) THEN 'Above Average Reputable'
        ELSE 'Below Average Reputable'
    END as ReputationCategory,
    COALESCE(SampleComments, 'No Comments') as CommentSummary,
    ABS(Score - (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2))) as ScoreDeviationFromAverage,
    ROUND((Score * 1.0 / NULLIF(ViewCount, 0)) * 100, 2) as ScoreToViewRatio,
    CASE WHEN DaysSincePost = 0 THEN 'Just Posted' ELSE CONCAT(CAST(DaysSincePost AS VARCHAR), ' days old') END as AgeStatus
FROM FinalResult
WHERE ScorePercentile BETWEEN 0.75 AND 1.0
   AND VisibilityStatus IN ('High Visibility', 'Medium Visibility')
   AND PostPopularity IN ('Viral', 'Popular')
   AND EngagementStatus IN ('Well-Engaged', 'Moderately Engaged')
ORDER BY Score DESC, ViewCount DESC, TotalScoreRank ASC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;