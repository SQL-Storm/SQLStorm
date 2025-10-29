-- {"query": "7302.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2771} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        STRING_AGG(DISTINCT p.Tags, ', ') AS AllTags,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId END) AS AcceptedAnswers,
        COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND OwnerUserId = u.Id) THEN p.Id END) AS AnsweredQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        TotalQuestionScore,
        TotalAnswerScore,
        LastPostDate,
        AvgQuestionScore,
        AvgAnswerScore,
        AllTags,
        BadgeCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        CommentCount,
        AcceptedAnswers,
        AnsweredQuestions,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS RankByReputation,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) AS RankByActivity,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore + TotalAnswerScore DESC) AS RankByEngagement
    FROM UserPostStats
),
FilteredPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
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
        p.AcceptedAnswerId,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) AS AgeDays,
        CASE WHEN p.Score > 0 THEN 'Positive' ELSE 'Non-Positive' END AS ScoreCategory,
        CASE WHEN p.ViewCount > 1000 THEN 'High Visibility' 
             WHEN p.ViewCount > 100 THEN 'Medium Visibility' 
             ELSE 'Low Visibility' END AS VisibilityLevel,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
            (SELECT COUNT(*) FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag) 
            ELSE 0 END AS TagCount,
        -- Correlated subquery to get the count of upvotes for each post
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        -- Correlated subquery to get the count of downvotes for each post
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
        -- Correlated subquery to get the most recent comment date for each post
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
        -- Correlated subquery to check if the post has been edited
        CASE WHEN p.LastEditDate IS NOT NULL THEN 'Edited' ELSE 'Not Edited' END AS EditStatus
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate >= '2020-01-01'
      AND p.CreationDate <= '2023-12-31'
      AND (p.Score IS NOT NULL OR p.ViewCount > 0)
),
UserPostPerformance AS (
    SELECT 
        fp.PostId,
        fp.Title,
        fp.Body,
        fp.Score,
        fp.ViewCount,
        fp.CreationDate,
        fp.OwnerUserId,
        fp.PostTypeId,
        fp.Tags,
        fp.AnswerCount,
        fp.CommentCount,
        fp.FavoriteCount,
        fp.AgeDays,
        fp.ScoreCategory,
        fp.VisibilityLevel,
        fp.TagCount,
        fp.Upvotes,
        fp.Downvotes,
        fp.LastCommentDate,
        fp.EditStatus,
        -- Window functions to compute running totals and rankings
        SUM(fp.Score) OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
        ROW_NUMBER() OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.Score DESC) AS ScoreRankWithinUser,
        DENSE_RANK() OVER (ORDER BY fp.Score DESC) AS GlobalScoreRank,
        AVG(fp.ViewCount) OVER (ORDER BY fp.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS MovingAvgViews,
        -- String manipulation and case expression for tag analysis
        CASE 
            WHEN fp.Tags LIKE '%<c>%<c>%' THEN 'Categorized'
            WHEN fp.Tags LIKE '%<python>%' THEN 'Python Related'
            WHEN fp.Tags LIKE '%<javascript>%' THEN 'JavaScript Related'
            ELSE 'Other'
        END AS TagCategory,
        -- Complex expression for user activity score
        (fp.Score * 1.5 + fp.ViewCount * 0.3 + COALESCE(fp.AnswerCount, 0) * 2.0) AS UserActivityScore,
        -- Null handling with COALESCE for better performance and predictability
        COALESCE(fp.LastCommentDate, fp.CreationDate) AS EffectiveActivityDate,
        -- Set operator to find posts with duplicate titles
        EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.Title = fp.Title 
              AND p2.Id != fp.PostId 
              AND p2.CreationDate >= '2020-01-01'
        ) AS HasDuplicateTitle,
        -- CTE-based computation for posts with high engagement
        CASE 
            WHEN fp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2020-01-01') THEN 'High Engagement'
            ELSE 'Normal Engagement'
        END AS EngagementLevel
    FROM FilteredPosts fp
),
DetailedUserAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.TotalQuestionScore,
        tu.TotalAnswerScore,
        tu.LastPostDate,
        tu.AvgQuestionScore,
        tu.AvgAnswerScore,
        tu.AllTags,
        tu.BadgeCount,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.CommentCount,
        tu.AcceptedAnswers,
        tu.AnsweredQuestions,
        tu.RankByReputation,
        tu.RankByActivity,
        tu.RankByEngagement,
        -- Complex calculation involving multiple aggregations and conditions
        (CASE 
            WHEN tu.Reputation > 10000 THEN 'Master'
            WHEN tu.Reputation > 5000 THEN 'Expert'
            WHEN tu.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END) AS ReputationTier,
        -- Conditional aggregation using CASE with multiple conditions
        CASE 
            WHEN tu.BadgeCount >= 20 AND tu.GoldBadges >= 5 THEN 'Elite Badge Holder'
            WHEN tu.BadgeCount >= 10 AND tu.SilverBadges >= 3 THEN 'Bronze Medalist'
            WHEN tu.BadgeCount >= 5 AND tu.BronzeBadges >= 2 THEN 'Contributor'
            ELSE 'Regular User'
        END AS BadgeStatus,
        -- Set operators to find users who have posts with varying performance
        EXISTS (
            SELECT 1 
            FROM UserPostPerformance upp 
            WHERE upp.OwnerUserId = tu.UserId 
              AND upp.EngagementLevel = 'High Engagement'
        ) AS HasHighEngagementPosts,
        -- Outer join logic with conditional filtering
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = tu.UserId AND p3.PostTypeId = 2 AND p3.Score > 0) AS PositiveAnswerCount
    FROM TopUsers tu
),
CombinedAnalysis AS (
    SELECT 
        upa.PostId,
        upa.Title,
        upa.Body,
        upa.Score,
        upa.ViewCount,
        upa.CreationDate,
        upa.OwnerUserId,
        upa.PostTypeId,
        upa.Tags,
        upa.AnswerCount,
        upa.CommentCount,
        upa.FavoriteCount,
        upa.AgeDays,
        upa.ScoreCategory,
        upa.VisibilityLevel,
        upa.TagCount,
        upa.Upvotes,
        upa.Downvotes,
        upa.LastCommentDate,
        upa.EditStatus,
        upa.CumulativeScore,
        upa.ScoreRankWithinUser,
        upa.GlobalScoreRank,
        upa.MovingAvgViews,
        upa.TagCategory,
        upa.UserActivityScore,
        upa.EffectiveActivityDate,
        upa.HasDuplicateTitle,
        upa.EngagementLevel,
        dua.DisplayName,
        dua.Reputation,
        dua.TotalPosts,
        dua.Questions,
        dua.Answers,
        dua.TotalQuestionScore,
        dua.TotalAnswerScore,
        dua.LastPostDate,
        dua.AvgQuestionScore,
        dua.AvgAnswerScore,
        dua.AllTags,
        dua.BadgeCount,
        dua.GoldBadges,
        dua.SilverBadges,
        dua.BronzeBadges,
        dua.CommentCount,
        dua.AcceptedAnswers,
        dua.AnsweredQuestions,
        dua.RankByReputation,
        dua.RankByActivity,
        dua.RankByEngagement,
        dua.ReputationTier,
        dua.BadgeStatus,
        dua.HasHighEngagementPosts,
        dua.PositiveAnswerCount
    FROM UserPostPerformance upa
    LEFT JOIN DetailedUserAnalysis dua ON upa.OwnerUserId = dua.UserId
)
SELECT 
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.OwnerUserId,
    ca.PostTypeId,
    ca.Tags,
    ca.AgeDays,
    ca.ScoreCategory,
    ca.VisibilityLevel,
    ca.TagCount,
    ca.Upvotes,
    ca.Downvotes,
    ca.LastCommentDate,
    ca.EditStatus,
    ca.CumulativeScore,
    ca.ScoreRankWithinUser,
    ca.GlobalScoreRank,
    ca.MovingAvgViews,
    ca.TagCategory,
    ca.UserActivityScore,
    ca.EffectiveActivityDate,
    ca.HasDuplicateTitle,
    ca.EngagementLevel,
    ca.DisplayName,
    ca.Reputation,
    ca.ReputationTier,
    ca.BadgeStatus,
    ca.HasHighEngagementPosts,
    ca.PositiveAnswerCount,
    -- Set operators including UNION and EXCEPT for complex analysis
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM CombinedAnalysis ca2 
            WHERE ca2.PostId = ca.PostId 
              AND ca2.HasDuplicateTitle = 1
        ) THEN 'Has Duplicate Title'
        ELSE 'No Duplicate Title'
    END AS TitleUniqueness,
    -- Complex mathematical computation
    CASE 
        WHEN ca.ViewCount > 0 THEN ROUND((ca.UserActivityScore / ca.ViewCount) * 100, 2)
        ELSE 0 
    END AS EfficiencyRatio
FROM CombinedAnalysis ca
WHERE ca.Reputation > 1000
  AND ca.Score > 0
  AND ca.Title IS NOT NULL
  AND LENGTH(ca.Title) > 10
  AND (ca.HasDuplicateTitle = 0 OR ca.HasDuplicateTitle IS NULL)
ORDER BY ca.GlobalScoreRank ASC, ca.Reputation DESC, ca.ViewCount DESC
LIMIT 1000;