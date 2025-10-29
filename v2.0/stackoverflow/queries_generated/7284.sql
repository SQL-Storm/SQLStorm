-- {"query": "7284.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2170} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgesCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, TotalPosts DESC) as ScoreRank,
        RANK() OVER (ORDER BY Reputation DESC) as RepRank,
        DENSE_RANK() OVER (ORDER BY BadgesCount DESC) as BadgeRank
    FROM UserPostStats
),
TopUsers AS (
    SELECT 
        *,
        CASE 
            WHEN ScoreRank <= 100 THEN 'Top 100'
            WHEN ScoreRank <= 500 THEN 'Top 500'
            WHEN ScoreRank <= 1000 THEN 'Top 1000'
            ELSE 'Other'
        END as UserTier,
        CASE 
            WHEN Questions > 0 AND Answers > 0 THEN 'Q&A Active'
            WHEN Questions > 0 THEN 'Question Expert'
            WHEN Answers > 0 THEN 'Answer Expert'
            ELSE 'Passive'
        END as ActivityLevel,
        CASE 
            WHEN TotalViews > 100000 THEN 'High Visibility'
            WHEN TotalViews > 50000 THEN 'Medium Visibility'
            WHEN TotalViews > 10000 THEN 'Low Visibility'
            ELSE 'Minimal Visibility'
        END as VisibilityTier
    FROM RankedUsers
),
TagAnalysis AS (
    SELECT 
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        p.PostTypeId,
        COALESCE(SUM(p.Score), 0) as TotalTagScore,
        AVG(p.Score) as AvgTagScore,
        COUNT(DISTINCT p.OwnerUserId) as ActiveUsers,
        AVG(p.ViewCount) as AvgViewCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 100 AND p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count, p.PostTypeId
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.LastActivityDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        CASE 
            WHEN p.Score > 10 THEN 'Highly Rated'
            WHEN p.Score > 5 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Slightly Rated'
            ELSE 'Not Rated'
        END as RatingTier,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Notable'
            ELSE 'Regular'
        END as PopularityTier,
        LEN(p.Title) as TitleLength,
        LEN(p.Body) as BodyLength,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as AgeInDays,
        (CASE 
            WHEN p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount = 1 THEN 'One Answer'
            WHEN p.AnswerCount <= 5 THEN 'Few Answers'
            ELSE 'Many Answers'
        END) as AnswerTier,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = p.Id 
             AND c.CreationDate >= p.CreationDate 
             AND c.CreationDate <= p.LastActivityDate),
            0
        ) as CommentCountInTimeline,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = p.Id 
             AND v.VoteTypeId IN (2,3) 
             AND v.CreationDate >= p.CreationDate),
            0
        ) as VoteCountAfterCreation,
        EXISTS(
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = p.Id 
            AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
            AND ph.CreationDate > p.CreationDate
        ) as HasEdits,
        (
            SELECT TOP 1 pt.Name 
            FROM PostTypes pt 
            WHERE pt.Id = p.PostTypeId
        ) as PostTypeName,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2) 
    AND p.CreationDate >= '2015-01-01'
    AND p.Score >= 0
),
ComprehensiveAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.TotalScore,
        tu.TotalViews,
        tu.BadgesCount,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.UserTier,
        tu.ActivityLevel,
        tu.VisibilityTier,
        ROW_NUMBER() OVER (ORDER BY tu.TotalScore DESC) as OverallScoreRank,
        RANK() OVER (ORDER BY tu.BadgesCount DESC) as TotalBadgesRank,
        COUNT(*) OVER () as TotalUsers,
        AVG(tu.TotalScore) OVER () as AvgScore,
        PERCENT_RANK() OVER (ORDER BY tu.TotalScore) as ScorePercentile,
        tu.RepRank,
        tu.BadgeRank,
        CASE 
            WHEN tu.TotalScore > (SELECT AVG(TotalScore) FROM UserPostStats) 
            THEN 'Above Average'
            ELSE 'Below Average'
        END as PerformanceTier,
        CASE 
            WHEN tu.BadgesCount > 10 AND tu.TotalPosts > 50 
            THEN 'Active Contributor'
            WHEN tu.BadgesCount > 5 OR tu.TotalPosts > 20 
            THEN 'Moderate Contributor'
            ELSE 'New Contributor'
        END as ContributorTier
    FROM TopUsers tu
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.TotalScore,
    ca.TotalViews,
    ca.BadgesCount,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.UserTier,
    ca.ActivityLevel,
    ca.VisibilityTier,
    ca.OverallScoreRank,
    ca.TotalBadgesRank,
    ca.TotalUsers,
    ca.AvgScore,
    ca.ScorePercentile,
    ca.RepRank,
    ca.BadgeRank,
    ca.PerformanceTier,
    ca.ContributorTier,
    COALESCE(
        (SELECT STRING_AGG ta.TagName, ', ') 
        FROM TagAnalysis ta 
        WHERE ta.TagCount > 500 
        AND EXISTS(
            SELECT 1 FROM Posts p 
            WHERE p.OwnerUserId = ca.UserId 
            AND p.Tags LIKE '%' || ta.TagName || '%'
        )
        ORDER BY ta.TagCount DESC
        LIMIT 5
    ) as TopTags,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT pa.PostTypeName, ', ') 
         FROM ComplexPostAnalysis pa 
         WHERE pa.OwnerUserId = ca.UserId 
         GROUP BY pa.OwnerUserId
         ORDER BY COUNT(*) DESC
         LIMIT 3
        ), 
        'No Posts'
    ) as PostTypes,
    CASE 
        WHEN ca.BadgesCount > 0 THEN 
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1) 
        ELSE 0 
    END as GoldBadgeRatio,
    CASE 
        WHEN ca.Answers > 0 THEN 
            (SELECT CAST(COUNT(*) AS FLOAT) * 100 / ca.Answers 
             FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2) 
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN ca.Questions > 0 THEN 
            (SELECT AVG(p.Score) 
             FROM Posts p 
             WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1) 
        ELSE 0 
    END as AvgQuestionScore,
    CASE 
        WHEN ca.Answers > 0 THEN 
            (SELECT AVG(p.Score) 
             FROM Posts p 
             WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2) 
        ELSE 0 
    END as AvgAnswerScore
FROM ComprehensiveAnalysis ca
WHERE ca.BadgesCount > 0
AND ca.ActivityLevel IN ('Q&A Active', 'Question Expert', 'Answer Expert')
AND ca.Reputation > 1000
ORDER BY ca.TotalScore DESC, ca.BadgesCount DESC
LIMIT 500;