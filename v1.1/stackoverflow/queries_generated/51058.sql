-- {"query": "51058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1529} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountiesOffered,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 8
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
      AND u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) >= 5
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.Score >= 10 THEN p.Id END) AS HighScorePosts,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
        MAX(p.CreationDate) AS LastActivity
    FROM Tags t
    INNER JOIN Posts p ON t.TagName = ANY(
        STRING_TO_ARRAY(
            SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), 
            '><'
        )
    )
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
      AND t.Count > 50
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 10
),
NetworkInfluence AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.PostCount,
        ua.AvgPostScore,
        COUNT(DISTINCT pl.RelatedPostId) AS PostsLinkedTo,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateReferences,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutboundLinks,
        COUNT(DISTINCT v2.PostId) AS PostsVotedOnByOthers,
        CORR(ua.Reputation::float, COUNT(DISTINCT ph.Id)::float) OVER (
            PARTITION BY EXTRACT(YEAR FROM p.CreationDate)
        ) AS RepVsActivityCorrelation
    FROM UserActivity ua
    INNER JOIN Posts p ON p.OwnerUserId = ua.UserId
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId IN (2, 3)
    WHERE p.Score > ua.AvgPostScore - 5  -- Posts close to or above user's average
    GROUP BY ua.UserId, ua.DisplayName, ua.PostCount, ua.AvgPostScore
),
TopContributors AS (
    SELECT 
        ni.UserId,
        ni.DisplayName,
        ni.PostCount,
        ni.AvgPostScore,
        ts.TagName AS PopularTag,
        RANK() OVER (
            PARTITION BY ts.TagName 
            ORDER BY COUNT(DISTINCT p.Id) DESC, ni.Reputation DESC
        ) AS RankInTag,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.ViewCount) AS Top90PercentileViews,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS PostsClosed,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.ParentId IS NULL THEN 1 ELSE 0 END) AS AcceptedQuestions
    FROM NetworkInfluence ni
    INNER JOIN Posts p ON p.OwnerUserId = ni.UserId AND p.PostTypeId = 1
    INNER JOIN TagStats ts ON ts.TagName = ANY(
        STRING_TO_ARRAY(
            SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), 
            '><'
        )
    )
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (10, 11, 12, 13)  -- Moderation events
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '3 months'
      AND ni.PostCount >= 10
    GROUP BY ni.UserId, ni.DisplayName, ni.PostCount, ni.AvgPostScore, ts.TagName
    HAVING COUNT(DISTINCT p.Id) >= 3
)
SELECT 
    tc.DisplayName AS ContributorName,
    tc.PostCount,
    ROUND(tc.AvgPostScore::numeric, 2) AS AveragePostScore,
    tc.PopularTag,
    tc.RankInTag,
    tc.Top90PercentileViews AS HighImpactViews,
    tc.PostsClosed,
    tc.AcceptedQuestions,
    ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges AS TotalBadges,
    ROUND(
        (tc.PostCount * 0.4 + 
         tc.AcceptedQuestions * 2 + 
         (ua.TotalBountiesOffered / NULLIF(tc.PostCount, 0)) * 0.1 + 
         (ua.GoldBadges * 5 + ua.SilverBadges * 2 + ua.BronzeBadges * 1)
        )::numeric, 2
    ) AS InfluenceScore,
    CASE 
        WHEN tc.RankInTag = 1 AND tc.Top90PercentileViews > 1000 THEN 'Elite'
        WHEN tc.PostCount > 50 AND tc.AvgPostScore > 5 THEN 'Veteran'
        WHEN tc.PostsClosed > 5 THEN 'ModeratorInfluence'
        ELSE 'Active'
    END AS ContributorTier,
    ni.PostsLinkedTo,
    ni.DuplicateReferences,
    ts.TotalPosts AS TagPopularity,
    ROW_NUMBER() OVER (ORDER BY InfluenceScore DESC, tc.PostCount DESC) AS GlobalRank
FROM TopContributors tc
INNER JOIN UserActivity ua ON ua.UserId = tc.UserId
INNER JOIN NetworkInfluence ni ON ni.UserId = tc.UserId
INNER JOIN TagStats ts ON ts.TagName = tc.PopularTag
WHERE tc.RankInTag <= 5  -- Top 5 contributors per popular tag
  AND ua.ActivityRank <= 100  -- Most active users overall
ORDER BY InfluenceScore DESC, GlobalRank
LIMIT 50;
