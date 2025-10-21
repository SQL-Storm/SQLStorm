-- {"query": "22040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1215} 
WITH UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(u.WebsiteUrl, 'N/A') AS Website,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        AVG(EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, u.CreationDate))) AS AccountAgeYears
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.WebsiteUrl, u.CreationDate
),
PostVoteSummary AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        COALESCE(p.ViewCount, 0) AS Views,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        ARRAY_TO_STRING(STRING_TO_ARRAY(COALESCE(p.Tags, ''), '><'), ',') AS TagList,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetUpvotes,
        COUNT(v.Id) AS TotalVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRankByScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Body, p.Tags
),
CorrelatedSubqueryExample AS (
    SELECT 
        p.PostId,
        p.NetUpvotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.PostId OR pl.RelatedPostId = p.PostId) AS LinkCount
    FROM PostVoteSummary p
),
CombinedSummary AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.Website,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.TotalBadges,
        u.AccountAgeYears,
        COALESCE(p.NetUpvotes, 0) AS BestPostNetUpvotes,
        COALESCE(p.Views, 0) AS BestPostViews,
        p.TagList AS BestPostTags,
        p.BodyLength AS BestPostBodyLength,
        c.LinkCount,
        CASE 
            WHEN u.Reputation > 1000 AND u.TotalBadges > 10 THEN 'High Contributor'
            WHEN u.Reputation BETWEEN 100 AND 1000 THEN 'Mid Contributor'
            ELSE 'New Contributor'
        END AS ContributorLevel,
        RANK() OVER (ORDER BY u.Reputation DESC, u.TotalBadges DESC) AS GlobalRank,
        DENSE_RANK() OVER (PARTITION BY LEFT(COALESCE(u.Location, 'Unknown'), 10) ORDER BY u.Reputation DESC) AS LocationRank
    FROM UserBadgeSummary u
    LEFT JOIN PostVoteSummary p ON u.UserId = p.OwnerUserId AND p.PostRankByScore = 1
    LEFT JOIN CorrelatedSubqueryExample c ON p.PostId = c.PostId
    WHERE u.Reputation IS NOT NULL AND (u.TotalBadges > 0 OR p.NetUpvotes IS NOT NULL)
),
UnionExample AS (
    SELECT 'Questions' AS PostType, Id, OwnerUserId, Score FROM Posts WHERE PostTypeId = 1 AND Score > 10
    UNION ALL
    SELECT 'Answers' AS PostType, Id, OwnerUserId, Score FROM Posts WHERE PostTypeId = 2 AND Score > 10
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.Location,
    cs.Website,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.TotalBadges,
    cs.AccountAgeYears,
    cs.BestPostNetUpvotes,
    cs.BestPostViews,
    cs.BestPostTags,
    cs.BestPostBodyLength,
    cs.LinkCount,
    cs.ContributorLevel,
    cs.GlobalRank,
    cs.LocationRank,
    CASE WHEN cs.BestPostNetUpvotes > cs.TotalBadges THEN 'Post Star' ELSE 'Badge Collector' END AS Category,
    COUNT(ue.Id) OVER (PARTITION BY cs.UserId) AS QualifyingPosts,
    SUM(CASE WHEN ue.PostType = 'Questions' THEN ue.Score ELSE 0 END) OVER (PARTITION BY cs.UserId) AS QuestionScoreSum,
    AVG(ue.Score) OVER (PARTITION BY cs.UserId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgScore
FROM CombinedSummary cs
LEFT JOIN UnionExample ue ON cs.UserId = ue.OwnerUserId
WHERE cs.Reputation > 50 
  AND (cs.BestPostViews IS NULL OR cs.BestPostViews > 100)
  AND SUBSTRING(COALESCE(cs.BestPostTags, ''), 1, 10) NOT LIKE '%java%'
  AND cs.ContributorLevel IN ('High Contributor', 'Mid Contributor')
  AND (cs.LinkCount IS NULL OR cs.LinkCount > 1)
ORDER BY cs.GlobalRank, cs.LocationRank
LIMIT 1000;