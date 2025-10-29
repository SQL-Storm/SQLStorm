-- {"query": "7148.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3377} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) as NegativeScorePosts,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Body END, ' | ') as AnswerBodies,
        AVG(p.Score) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as HighViewPosts,
        COUNT(DISTINCT CASE WHEN p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'HasAnswers'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'Other'
        END as QuestionStatus,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as ViewCategory,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyUpvoted'
            WHEN p.Score > 50 THEN 'Upvoted'
            WHEN p.Score > 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END as ScoreStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) as ViewDecile,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPerformance AS (
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
        uas.LastCommentDate,
        uas.PositiveScorePosts,
        uas.NegativeScorePosts,
        uas.QuestionTitles,
        uas.AnswerBodies,
        uas.AvgPostScore,
        uas.HighViewPosts,
        uas.QuestionsWithAnswers,
        CASE 
            WHEN uas.TotalPosts > 0 THEN CAST(uas.PositiveScorePosts AS FLOAT) * 100 / uas.TotalPosts
            ELSE 0
        END as PositiveScorePercentage,
        CASE 
            WHEN uas.TotalPosts > 0 THEN CAST(uas.Answers AS FLOAT) * 100 / uas.Questions
            ELSE 0
        END as AnswerRate,
        CASE 
            WHEN uas.Views > 0 THEN CAST(uas.HighViewPosts AS FLOAT) * 100 / uas.TotalPosts
            ELSE 0
        END as HighViewPercentage,
        CASE 
            WHEN uas.TotalPosts > 0 THEN CAST(uas.Comments AS FLOAT) / uas.TotalPosts
            ELSE 0
        END as CommentsPerPost
    FROM UserActivityStats uas
    WHERE uas.TotalPosts > 0
),
ComplexPosts AS (
    SELECT 
        pc.PostId,
        pc.Title,
        pc.Body,
        pc.Score,
        pc.ViewCount,
        pc.AnswerCount,
        pc.CommentCount,
        pc.FavoriteCount,
        pc.CreationDate,
        pc.LastActivityDate,
        pc.OwnerUserId,
        pc.QuestionStatus,
        pc.ViewCategory,
        pc.ScoreStatus,
        pc.UserPostRank,
        pc.TotalUserPosts,
        pc.UserAvgScore,
        pc.ViewDecile,
        pc.GlobalScoreRank,
        DENSE_RANK() OVER (PARTITION BY pc.OwnerUserId ORDER BY pc.CreationDate DESC) as RecentPostRank,
        CASE 
            WHEN pc.Body IS NOT NULL AND LENGTH(pc.Body) > 1000 THEN 'Long'
            WHEN pc.Body IS NOT NULL AND LENGTH(pc.Body) > 500 THEN 'Medium'
            WHEN pc.Body IS NOT NULL AND LENGTH(pc.Body) > 100 THEN 'Short'
            ELSE 'VeryShort'
        END as BodyLengthCategory,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = pc.PostId AND c.Score > 5) THEN 'HighlyCommented'
            WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = pc.PostId AND c.Score > 0) THEN 'Commented'
            ELSE 'NoComments'
        END as CommentStatus,
        LAG(pc.Score, 1) OVER (PARTITION BY pc.OwnerUserId ORDER BY pc.CreationDate) as PreviousScore,
        LEAD(pc.Score, 1) OVER (PARTITION BY pc.OwnerUserId ORDER BY pc.CreationDate) as NextScore,
        DATEDIFF('DAY', pc.CreationDate, pc.LastActivityDate) as DaysBetweenCreationAndActivity
    FROM PostComplexity pc
),
PerformanceAnalysis AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.Views,
        up.TotalPosts,
        up.Questions,
        up.Answers,
        up.Comments,
        up.Badges,
        up.LastPostDate,
        up.LastCommentDate,
        up.PositiveScorePosts,
        up.NegativeScorePosts,
        up.PositiveScorePercentage,
        up.AnswerRate,
        up.HighViewPercentage,
        up.CommentsPerPost,
        CASE 
            WHEN up.Reputation > 10000 THEN 'Elite'
            WHEN up.Reputation > 5000 THEN 'Experienced'
            WHEN up.Reputation > 1000 THEN 'Advanced'
            WHEN up.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as RepCategory,
        CASE 
            WHEN up.TotalPosts > 100 THEN 'VeryActive'
            WHEN up.TotalPosts > 50 THEN 'Active'
            WHEN up.TotalPosts > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ActivityLevel,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT CASE WHEN pp.QuestionStatus = 'Answered' THEN 'Answered' END, ', ') 
             FROM ComplexPosts pp 
             WHERE pp.OwnerUserId = up.UserId), 
            'None'
        ) as AnswerStatus,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT CASE WHEN pp.ViewCategory = 'Viral' THEN 'Viral' END, ', ') 
             FROM ComplexPosts pp 
             WHERE pp.OwnerUserId = up.UserId), 
            'None'
        ) as ViralPosts,
        COALESCE(
            (SELECT COUNT(*) 
             FROM ComplexPosts pp 
             WHERE pp.OwnerUserId = up.UserId 
               AND pp.ScoreStatus = 'HighlyUpvoted'), 
            0
        ) as HighlyUpvotedCount,
        COALESCE(
            (SELECT AVG(pp.ViewCount) 
             FROM ComplexPosts pp 
             WHERE pp.OwnerUserId = up.UserId), 
            0
        ) as AvgViewsPerPost
    FROM UserPerformance up
)
SELECT 
    pa.UserId,
    pa.DisplayName,
    pa.Reputation,
    pa.Views,
    pa.TotalPosts,
    pa.Questions,
    pa.Answers,
    pa.Comments,
    pa.Badges,
    pa.LastPostDate,
    pa.LastCommentDate,
    pa.PositiveScorePosts,
    pa.NegativeScorePosts,
    pa.PositiveScorePercentage,
    pa.AnswerRate,
    pa.HighViewPercentage,
    pa.CommentsPerPost,
    pa.RepCategory,
    pa.ActivityLevel,
    pa.AnswerStatus,
    pa.ViralPosts,
    pa.HighlyUpvotedCount,
    pa.AvgViewsPerPost,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = pa.UserId 
       AND p.CreationDate > '2023-01-01') as RecentPosts2023,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = pa.UserId 
       AND p.PostTypeId = 1 
       AND p.AnswerCount = 0) as UnansweredQuestions,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = pa.UserId 
       AND p.PostTypeId = 2 
       AND p.Score > 100) as HighScoringAnswers,
    (SELECT COUNT(DISTINCT pp.ParentId) 
     FROM Posts pp 
     WHERE pp.OwnerUserId = pa.UserId 
       AND pp.PostTypeId = 2 
       AND pp.ParentId IS NOT NULL) as AnsweredQuestions,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = pa.UserId 
       AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = pa.UserId 
       AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = pa.UserId 
       AND b.Class = 3) as BronzeBadges,
    NULL as NullTestColumn1,
    NULL as NullTestColumn2,
    NULL as NullTestColumn3,
    (
        CASE 
            WHEN pa.Reputation > 1000 AND pa.TotalPosts > 50 AND pa.Answers > 10 THEN 'HighValueContributor'
            WHEN pa.Reputation > 500 AND pa.TotalPosts > 20 THEN 'ActiveContributor'
            WHEN pa.Reputation > 100 THEN 'RegularUser'
            ELSE 'NewUser'
        END
    ) as UserTier,
    (
        SELECT COUNT(*) 
        FROM VoteTypes vt 
        WHERE vt.Id IN (1, 2, 3, 4, 5, 6)
    ) as ValidVoteTypes,
    (
        SELECT AVG(pa.Views) 
        FROM PerformanceAnalysis pa 
        WHERE pa.Reputation > 1000
    ) as AvgViewsForHighRepUsers,
    (
        CASE 
            WHEN pa.TotalPosts > 0 AND pa.AnswerRate > 50 THEN 'HighAnswerRate'
            WHEN pa.TotalPosts > 0 AND pa.AnswerRate > 25 THEN 'ModerateAnswerRate'
            WHEN pa.TotalPosts > 0 AND pa.AnswerRate > 0 THEN 'LowAnswerRate'
            ELSE 'NoAnswers'
        END
    ) as AnswerRateCategory,
    (
        SELECT STRING_AGG(DISTINCT CASE WHEN pp.ViewCategory = 'Viral' THEN pp.Title END, ' | ') 
        FROM ComplexPosts pp 
        WHERE pp.OwnerUserId = pa.UserId 
          AND pp.ViewCategory = 'Viral'
    ) as ViralPostTitles
FROM PerformanceAnalysis pa
WHERE pa.Reputation > 1000 
  AND pa.TotalPosts > 10
  AND (pa.ViewCategory = 'Viral' OR pa.ScoreStatus = 'HighlyUpvoted')
  AND pa.AnswerRate > 20
  AND pa.HighViewPercentage > 20
ORDER BY pa.Views DESC, pa.Reputation DESC, pa.HighlyUpvotedCount DESC, pa.AvgViewsPerPost DESC
LIMIT 1000
EXCEPT
SELECT 
    pa.UserId,
    pa.DisplayName,
    pa.Reputation,
    pa.Views,
    pa.TotalPosts,
    pa.Questions,
    pa.Answers,
    pa.Comments,
    pa.Badges,
    pa.LastPostDate,
    pa.LastCommentDate,
    pa.PositiveScorePosts,
    pa.NegativeScorePosts,
    pa.PositiveScorePercentage,
    pa.AnswerRate,
    pa.HighViewPercentage,
    pa.CommentsPerPost,
    pa.RepCategory,
    pa.ActivityLevel,
    pa.AnswerStatus,
    pa.ViralPosts,
    pa.HighlyUpvotedCount,
    pa.AvgViewsPerPost,
    NULL as NullTestColumn1,
    NULL as NullTestColumn2,
    NULL as NullTestColumn3,
    NULL as NullTestColumn4,
    0 as ValidVoteTypes,
    0 as AvgViewsForHighRepUsers,
    NULL as AnswerRateCategory,
    NULL as ViralPostTitles
FROM PerformanceAnalysis pa
WHERE pa.UserId BETWEEN 5000 AND 5010
   OR pa.Reputation BETWEEN 100 AND 110
   OR pa.Views BETWEEN 1000 AND 1100
   OR pa.TotalPosts BETWEEN 1 AND 10
   OR pa.Badges BETWEEN 1 AND 10
   OR pa.Answers BETWEEN 1 AND 5
   OR pa.Comments BETWEEN 1 AND 5
ORDER BY pa.UserId ASC
UNION ALL
SELECT 
    pa.UserId,
    pa.DisplayName,
    pa.Reputation,
    pa.Views,
    pa.TotalPosts,
    pa.Questions,
    pa.Answers,
    pa.Comments,
    pa.Badges,
    pa.LastPostDate,
    pa.LastCommentDate,
    pa.PositiveScorePosts,
    pa.NegativeScorePosts,
    pa.PositiveScorePercentage,
    pa.AnswerRate,
    pa.HighViewPercentage,
    pa.CommentsPerPost,
    pa.RepCategory,
    pa.ActivityLevel,
    pa.AnswerStatus,
    pa.ViralPosts,
    pa.HighlyUpvotedCount,
    pa.AvgViewsPerPost,
    NULL as NullTestColumn1,
    NULL as NullTestColumn2,
    NULL as NullTestColumn3,
    NULL as NullTestColumn4,
    0 as ValidVoteTypes,
    0 as AvgViewsForHighRepUsers,
    NULL as AnswerRateCategory,
    NULL as ViralPostTitles
FROM PerformanceAnalysis pa
WHERE pa.Reputation IN (
    SELECT DISTINCT Reputation FROM Users WHERE Reputation > 5000
    INTERSECT
    SELECT DISTINCT Reputation FROM Users WHERE Reputation < 15000
    EXCEPT
    SELECT DISTINCT Reputation FROM Users WHERE Reputation = 10000
) 
  AND pa.TotalPosts BETWEEN 20 AND 100
ORDER BY pa.Reputation DESC, pa.Views DESC, pa.TotalPosts DESC
LIMIT 500;