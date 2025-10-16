-- {"query": "29025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3458} 
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
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (ORDER BY u.Views DESC) AS ViewRank,
        DENSE_RANK() OVER (PARTITION BY CASE WHEN u.Reputation > 10000 THEN 'High' ELSE 'Low' END ORDER BY u.Reputation DESC) AS ReputationTierRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL 
      AND u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        ViewRank,
        ReputationRank,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        LatestPostDate,
        ReputationTierRank,
        CASE 
            WHEN Reputation > 100000 THEN 'Superstar'
            WHEN Reputation > 50000 THEN 'Elite'
            WHEN Reputation > 10000 THEN 'Veteran'
            ELSE 'Regular'
        END AS UserTier,
        CASE 
            WHEN PostCount >= 1000 AND AnswerCount >= 500 THEN 'Active Contributor'
            WHEN PostCount >= 500 THEN 'Regular Contributor'
            WHEN PostCount >= 100 THEN 'Occasional Contributor'
            ELSE 'Newbie'
        END AS ContributionLevel
    FROM UserStats
    WHERE Reputation > 1000
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
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
                    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
                    ELSE 'Unanswered'
                END
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostStatus,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Well Voted'
            WHEN p.Score > 0 THEN 'Moderately Voted'
            WHEN p.Score = 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END AS VoteStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequence,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) AS ViewDecile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsPerUser,
        COALESCE(p.Tags, '') AS CleanTags,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS TagsWithoutBrackets,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        CASE 
            WHEN p.Tags LIKE '%<%' AND p.Tags LIKE '%>%' THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1)
            ELSE 0
        END AS TagCount,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' AND p.Tags LIKE '%<%' THEN 
                (SELECT COUNT(*) FROM unnest(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag WHERE tag = 'python')
            ELSE 0
        END AS PythonTagCount
    FROM Posts p
    WHERE p.CreationDate >= '2012-01-01'
),
UserPostActivity AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.ReputationTierRank,
        u.PostCount,
        u.CommentCount,
        u.BadgeCount,
        u.QuestionCount,
        u.AnswerCount,
        u.AvgPostScore,
        p.PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostStatus,
        p.VoteStatus,
        p.PostSequence,
        p.ScoreRank,
        p.ViewDecile,
        p.PrevScore,
        p.NextScore,
        p.AvgScorePerUser,
        p.TotalPostsPerUser,
        p.TagCount,
        p.PythonTagCount,
        CASE 
            WHEN (p.Score - COALESCE(p.PrevScore, 0)) > 50 THEN 'Large Improvement'
            WHEN (p.Score - COALESCE(p.PrevScore, 0)) > 10 THEN 'Moderate Improvement'
            WHEN (p.Score - COALESCE(p.PrevScore, 0)) > 0 THEN 'Slight Improvement'
            WHEN (p.Score - COALESCE(p.PrevScore, 0)) < -10 THEN 'Significant Decline'
            ELSE 'No Change'
        END AS ScoreChangeAnalysis,
        CASE 
            WHEN p.PostStatus = 'Answered' AND p.Score > 10 THEN 'High Value Answer'
            WHEN p.PostStatus = 'Answered' THEN 'Standard Answer'
            WHEN p.PostStatus = 'Unanswered' AND p.Score > 10 THEN 'High Value Question'
            ELSE 'Standard Question'
        END AS ContentCategory
    FROM TopUsers u
    INNER JOIN PostAnalysis p ON u.UserId = p.OwnerUserId
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
),
FinalAnalysis AS (
    SELECT 
       upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.ReputationTierRank,
        upa.PostCount,
        upa.CommentCount,
        upa.BadgeCount,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgPostScore,
        upa.PostId,
        upa.Title,
        upa.Score,
        upa.ViewCount,
        upa.CreationDate,
        upa.PostStatus,
        upa.VoteStatus,
        upa.PostSequence,
        upa.ScoreRank,
        upa.ViewDecile,
        upa.PrevScore,
        upa.NextScore,
        upa.AvgScorePerUser,
        upa.TotalPostsPerUser,
        upa.TagCount,
        upa.PythonTagCount,
        upa.ScoreChangeAnalysis,
        upa.ContentCategory,
        CASE 
            WHEN upa.TagCount > 0 AND EXISTS (SELECT 1 FROM unnest(STRING_TO_ARRAY(SUBSTRING(upa.TagsWithoutBrackets, 1, LENGTH(upa.TagsWithoutBrackets)), '><')) AS tag WHERE tag = 'python') 
                 AND (upa.Score > 50 OR upa.ViewCount > 1000)
            THEN 'Python Experts'
            WHEN upa.PythonTagCount > 0 AND (upa.Score > 30 OR upa.ViewCount > 500)
            THEN 'Python Enthusiasts'
            WHEN upa.TagCount > 1
            THEN 'Multi-Tag Contributors'
            ELSE 'Single Tag Focus'
        END AS TaggingStrategy,
        DENSE_RANK() OVER (ORDER BY upa.ViewCount DESC) AS ViewRankAcrossPosts,
        RANK() OVER (ORDER BY upa.Score DESC) AS ScoreRankAcrossAllPosts,
        ROW_NUMBER() OVER (ORDER BY upa.CreationDate DESC) AS NewestPostOrder,
        (upa.Score * 1.5 + upa.ViewCount * 0.2) AS WeightedPopularityScore,
        (upa.Reputation * 0.8 + upa.PostCount * 2.5 + upa.ViewCount * 0.01 + upa.CommentCount * 1.2) AS OverallUserMetric,
        CASE 
            WHEN upa.PostStatus = 'Answered' THEN
                (SELECT AVG(p2.Score) 
                 FROM Posts p2 
                 WHERE p2.PostTypeId = 1 
                 AND p2.OwnerUserId = upa.UserId 
                 AND p2.AcceptedAnswerId IS NOT NULL)
            ELSE NULL
        END AS AvgScoreOfAnsweredQuestions
    FROM UserPostActivity upa
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.ReputationTierRank,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.AvgPostScore,
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.PostStatus,
    fa.VoteStatus,
    fa.PostSequence,
    fa.ScoreRank,
    fa.ViewDecile,
    fa.PrevScore,
    fa.NextScore,
    fa.AvgScorePerUser,
    fa.TotalPostsPerUser,
    fa.TagCount,
    fa.PythonTagCount,
    fa.ScoreChangeAnalysis,
    fa.ContentCategory,
    fa.TaggingStrategy,
    fa.ViewRankAcrossPosts,
    fa.ScoreRankAcrossAllPosts,
    fa.NewestPostOrder,
    fa.WeightedPopularityScore,
    fa.OverallUserMetric,
    fa.AvgScoreOfAnsweredQuestions,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = fa.UserId 
     AND p.PostTypeId IN (1, 2)) AS TotalQuestionAndAnswerCount,
    (SELECT COUNT(DISTINCT ph.PostHistoryTypeId) 
     FROM PostHistory ph 
     WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)) AS HistoryTypesCount,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)
     AND v.VoteTypeId IN (2, 3)) AS TotalVoteCount,
    (SELECT STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ',') 
     FROM Votes v 
     WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)) AS VoteTypeCombinations,
    CASE 
        WHEN fa.Reputation > 10000 THEN 'Expert Level'
        WHEN fa.Reputation > 5000 THEN 'Intermediate Level'
        WHEN fa.Reputation > 1000 THEN 'Beginner Level'
        ELSE 'Novice Level'
    END AS UserExperienceLevel,
    ROUND(CAST(fa.Reputation AS FLOAT) / CAST(NULLIF(fa.PostCount, 0) AS FLOAT), 2) AS RepPerPost,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = fa.UserId 
     AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = fa.UserId 
     AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = fa.UserId 
     AND b.Class = 3) AS BronzeBadgeCount,
    CASE 
        WHEN fa.PostCount > 1000 THEN 'Highly Active'
        WHEN fa.PostCount > 500 THEN 'Active'
        WHEN fa.PostCount > 100 THEN 'Moderately Active'
        WHEN fa.PostCount > 50 THEN 'Low Activity'
        ELSE 'Very Low Activity'
    END AS ActivityLevel,
    CASE 
        WHEN (fa.ViewCount / NULLIF(fa.Score, 0)) > 1000 THEN 'Highly Engaged'
        WHEN (fa.ViewCount / NULLIF(fa.Score, 0)) > 100 THEN 'Moderately Engaged'
        WHEN (fa.ViewCount / NULLIF(fa.Score, 0)) > 10 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END AS EngagementStatus,
    ABS(fa.Score - COALESCE(fa.AvgScorePerUser, 0)) AS ScoreDeviationFromUserAvg,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = fa.UserId 
     AND p.PostTypeId = 1 
     AND p.AcceptedAnswerId IS NOT NULL) AS AnsweredQuestionsCount,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = fa.UserId 
     AND c.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)) AS UserCommentsOnOwnPosts,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p 
            WHERE p.OwnerUserId = fa.UserId 
            AND (p.Score > 100 OR p.ViewCount > 1000)
        ) THEN 'Has Popular Posts'
        ELSE 'No Popular Posts'
    END AS PopularPostIndicator,
    CASE 
        WHEN fa.Reputation >= 100000 AND fa.PostCount >= 2000 THEN 'Legendary Contributor'
        WHEN fa.Reputation >= 50000 AND fa.PostCount >= 1000 THEN 'Veteran Contributor'
        WHEN fa.Reputation >= 10000 AND fa.PostCount >= 500 THEN 'Experienced Contributor'
        ELSE 'Regular Contributor'
    END AS ContributorStatus,
    COALESCE(fa.Score - fa.PrevScore, 0) AS NetScoreChange,
    CASE 
        WHEN (fa.NextScore - fa.PrevScore) > 50 THEN 'Significant Momentum'
        WHEN (fa.NextScore - fa.PrevScore) > 10 THEN 'Moderate Momentum'
        WHEN (fa.NextScore - fa.PrevScore) > 0 THEN 'Minor Momentum'
        ELSE 'No Momentum'
    END AS MomentumIndicator,
    ROUND(SUM(fa.ViewCount) OVER (ORDER BY fa.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS CumulativeViews,
    ROUND(AVG(fa.Score) OVER (ORDER BY fa.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 2) AS RollingAvgScore,
    ROUND(STDDEV(fa.Score) OVER (ORDER BY fa.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW), 2) AS RollingStdDevScore,
    ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', fa.CreationDate) ORDER BY fa.CreationDate) AS DailyOrderInMonth,
    COUNT(*) OVER (PARTITION BY DATE_TRUNC('year', fa.CreationDate)) AS YearlyPostCount,
    LAG(fa.Score, 3) OVER (ORDER BY fa.CreationDate) AS ScoreThreePostsAgo
FROM FinalAnalysis fa
WHERE fa.CreationDate >= '2012-01-01'
  AND fa.Reputation > 1000
ORDER BY fa.CreationDate DESC, fa.WeightedPopularityScore DESC
LIMIT 10000;