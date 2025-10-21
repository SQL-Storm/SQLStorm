WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(Name, ', ') AS BadgeList
    FROM Badges
    GROUP BY UserId
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        COALESCE(p.ViewCount, 0) AS Views,
        p.AnswerCount,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT v.Id) AS Votes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetUpvotes,
        CASE 
            WHEN p.Tags IS NOT NULL THEN CAST(REGEXP_REPLACE(p.Tags, '^\\[|\\]$', '', 'g') AS VARCHAR)
            ELSE ''
        END AS TagArrayRaw,
        p.CreationDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.Tags, p.CreationDate
),
RankedUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.TotalPosts,
        ups.Questions,
        ups.Answers,
        ROUND(ups.AvgScore, 2) AS AvgScore,
        ups.TotalViews,
        ups.LastPostDate,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        LENGTH(COALESCE(ubs.BadgeList, '')) AS BadgeListLength,
        ROW_NUMBER() OVER (ORDER BY ups.TotalPosts DESC, ups.TotalViews DESC) AS PostRank
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
),
TopPosts AS (
    SELECT 
        pe.PostId,
        pe.OwnerUserId,
        pe.Score,
        pe.Views,
        pe.AnswerCount,
        pe.Comments,
        pe.Votes,
        pe.NetUpvotes,
        ARRAY_LENGTH(string_to_array(pe.TagArrayRaw, ','), 1) AS NumTags,
        DATE_TRUNC('month', pe.CreationDate) AS PostMonth,
        ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.NetUpvotes DESC) AS TopPostRank
    FROM PostEngagement pe
),
CombinedMetrics AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.TotalPosts,
        ru.Questions,
        ru.Answers,
        ru.AvgScore,
        ru.TotalViews,
        ru.TotalBadges,
        ru.GoldBadges,
        ru.SilverBadges,
        ru.BronzeBadges,
        ru.BadgeListLength,
        ru.PostRank,
        tp.Score AS BestPostScore,
        tp.Views AS BestPostViews,
        tp.AnswerCount AS BestPostAnswers,
        tp.Comments AS BestPostComments,
        tp.NetUpvotes AS BestPostNetUpvotes,
        tp.NumTags AS BestPostNumTags,
        tp.PostMonth AS BestPostMonth
    FROM RankedUsers ru
    LEFT JOIN TopPosts tp ON ru.UserId = tp.OwnerUserId AND tp.TopPostRank = 1
)
SELECT 
    UserId,
    DisplayName,
    TotalPosts,
    Questions,
    Answers,
    AvgScore,
    TotalViews,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    BadgeListLength,
    PostRank,
    BestPostScore,
    BestPostViews,
    BestPostAnswers,
    BestPostComments,
    BestPostNetUpvotes,
    BestPostNumTags,
    BestPostMonth,
    CASE 
        WHEN Answers > 0 AND Questions > 0 THEN ROUND(CAST(Answers AS DOUBLE PRECISION) / CAST(Questions AS DOUBLE PRECISION), 3)
        ELSE NULL
    END AS AnswerToQuestionRatio,
    CASE 
        WHEN TotalPosts > 0 THEN ROUND(CAST(TotalViews AS DOUBLE PRECISION) / CAST(TotalPosts AS DOUBLE PRECISION), 2)
        ELSE 0
    END AS AvgViewsPerPost,
    COALESCE(BestPostScore, 0) + COALESCE(BestPostNetUpvotes, 0) AS BestPostOverall,
    ROW_NUMBER() OVER (PARTITION BY (PostRank <= 100) ORDER BY TotalPosts DESC, TotalViews DESC, BadgeListLength DESC) AS SubRank
FROM CombinedMetrics
WHERE PostRank <= 1000
  AND (BestPostScore IS NOT NULL OR BestPostNetUpvotes > 0)
  AND EXISTS (
      SELECT 1 FROM Votes v 
      WHERE v.UserId = CombinedMetrics.UserId 
        AND v.VoteTypeId IN (1, 2, 3) 
        AND v.CreationDate > DATE '2020-01-01'
  )
ORDER BY PostRank ASC, SubRank ASC
LIMIT 50;