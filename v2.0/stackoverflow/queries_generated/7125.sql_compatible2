WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - MAX(p.CreationDate))) / 86400 AS DaysSinceLastPost,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN CAST(SUM(p.Score) AS FLOAT) / COUNT(DISTINCT p.Id)
            ELSE 0 
        END AS AvgScorePerPost,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, '; ') AS RecentQuestionTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CAST('2010-01-01' AS timestamp)
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalScore,
        TotalViews,
        LastPostDate,
        DaysSinceLastPost,
        AvgScorePerPost,
        RecentQuestionTitles,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS RankByScore
    FROM UserActivityStats
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    WHERE b.Date >= CAST('2010-01-01' AS timestamp)
    GROUP BY b.UserId
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.OwnerDisplayName, 'Anonymous') AS OwnerDisplayName,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / 86400 AS DaysOld,
        COALESCE(p.Tags, '') AS Tags,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Engaged'
            WHEN p.Score > 50 THEN 'Moderately Engaged'
            WHEN p.Score > 10 THEN 'Low Engagement'
            ELSE 'Minimal Activity'
        END AS EngagementLevel,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= CAST('2010-01-01' AS timestamp)
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ht.Name AS HistoryTypeName,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ph.CreationDate)) / 86400 AS DaysAgo,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Moderation Action'
            WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (17, 18, 19, 20) THEN 'Post Migration'
            ELSE 'Other'
        END AS ActivityCategory
    FROM PostHistory ph
    JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
    WHERE ph.CreationDate >= CAST('2020-01-01' AS timestamp)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.Title, 'No Excerpt') AS ExcerptTitle,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 100 THEN 'Moderately Popular'
            WHEN t.Count > 10 THEN 'Low Popularity'
            ELSE 'Very Low'
        END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByPopularity
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Count > 0
),
CombinedAnalysis AS (
    SELECT 
        tu.UserId,
        tu.Reputation,
        tu.DisplayName,
        tu.TotalPosts,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalScore,
        tu.TotalViews,
        tu.LastPostDate,
        tu.DaysSinceLastPost,
        tu.AvgScorePerPost,
        tu.RecentQuestionTitles,
        tu.RankByScore,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.BadgeNames,
        CASE 
            WHEN tu.TotalPosts > 0 AND tu.TotalViews > 0 THEN 
                CAST(tu.TotalScore AS FLOAT) * 100 / (tu.TotalViews + 1)
            ELSE 0 
        END AS ScorePerViewMultiplier,
        CASE 
            WHEN ub.TotalBadges > 0 THEN 
                CAST(ub.GoldBadges AS FLOAT) / ub.TotalBadges * 100
            ELSE 0 
        END AS GoldBadgePercentage,
        CASE 
            WHEN LENGTH(tu.RecentQuestionTitles) > 20 THEN 
                CONCAT('Recent Topics: ', SUBSTRING(tu.RecentQuestionTitles FROM 1 FOR 20), '...')
            ELSE tu.RecentQuestionTitles
        END AS SummaryTopics,
        COALESCE(ta.TagCount, 0) AS TopTagCount,
        COALESCE(ta.TagName, 'No Tags') AS TopTag,
        CASE 
            WHEN tu.DaysSinceLastPost > 180 THEN 'Inactive User (6+ Months)'
            WHEN tu.DaysSinceLastPost > 90 THEN 'Semi-active User (3+ Months)'
            WHEN tu.DaysSinceLastPost > 30 THEN 'Active User (1+ Month)'
            ELSE 'Very Active User'
        END AS ActivityStatus,
        CASE 
            WHEN ta.PopularityLevel = 'Highly Popular' THEN 5
            WHEN ta.PopularityLevel = 'Moderately Popular' THEN 4
            WHEN ta.PopularityLevel = 'Low Popularity' THEN 3
            WHEN ta.PopularityLevel = 'Very Low' THEN 2
            ELSE 1 
        END AS TagPopularityScore
    FROM TopUsers tu
    LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT JOIN TagAnalysis ta ON tu.UserId = (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 1 
          AND CreationDate >= CAST('2010-01-01' AS timestamp)
          AND Tags LIKE '%' || ta.TagName || '%'
        LIMIT 1
    )
)
SELECT 
    ca.UserId,
    ca.Reputation,
    ca.DisplayName,
    ca.TotalPosts,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.TotalScore,
    ca.TotalViews,
    ca.LastPostDate,
    ca.DaysSinceLastPost,
    ca.AvgScorePerPost,
    ca.RecentQuestionTitles,
    ca.RankByScore,
    ca.TotalBadges,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.BadgeNames,
    ca.ScorePerViewMultiplier,
    ca.GoldBadgePercentage,
    ca.SummaryTopics,
    ca.TopTagCount,
    ca.TopTag,
    ca.ActivityStatus,
    ca.TagPopularityScore,
    CASE 
        WHEN ca.TotalScore > 5000 AND ca.TotalBadges > 50 THEN 'Elite Contributor'
        WHEN ca.TotalScore > 1000 AND ca.TotalBadges > 10 THEN 'Active Contributor'
        WHEN ca.TotalScore > 200 THEN 'Regular Contributor'
        ELSE 'Occasional Contributor'
    END AS ContributionLevel,
    CASE 
        WHEN ca.ScorePerViewMultiplier > 20 THEN 'High Engagement'
        WHEN ca.ScorePerViewMultiplier > 10 THEN 'Moderate Engagement'
        WHEN ca.ScorePerViewMultiplier > 5 THEN 'Low Engagement'
        ELSE 'Poor Engagement'
    END AS EngagementRating,
    CASE 
        WHEN ca.GoldBadgePercentage > 50 THEN 'Highly Recognized'
        WHEN ca.GoldBadgePercentage > 20 THEN 'Moderately Recognized'
        WHEN ca.GoldBadgePercentage > 5 THEN 'Slightly Recognized'
        ELSE 'Not Recognized'
    END AS RecognitionLevel,
    (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) AS CompositeScore,
    CASE 
        WHEN (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) > 5000 THEN 'Top Performer'
        WHEN (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) > 2000 THEN 'High Performer'
        WHEN (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) > 1000 THEN 'Medium Performer'
        WHEN (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) > 500 THEN 'Low Performer'
        ELSE 'Below Threshold'
    END AS PerformanceLevel
FROM CombinedAnalysis ca
WHERE ca.TotalPosts > 0 
   AND ca.Reputation > 100
ORDER BY (ca.TotalScore + ca.TotalBadges * 10 + (CASE WHEN ca.ActivityStatus LIKE '%Very Active%' THEN 100 ELSE 0 END)) DESC
LIMIT 1000;