-- {"query": "17100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2293} 
WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), ', ') 
            FILTER (WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2) AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
BadgeAnalysis AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate,
        DENSE_RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE Class = 1) DESC) AS GoldRank
    FROM Badges
    GROUP BY UserId
),
PostActivity AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        FIRST_VALUE(ph.CreationDate) OVER (
            PARTITION BY p.Id 
            ORDER BY ph.CreationDate DESC
        ) AS LastEditDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST
        ) AS UserPostRank,
        LAG(p.Score, 1, 0) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate
        ) AS PreviousPostScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
        AND (p.Body IS NOT NULL OR p.Title IS NOT NULL)
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, 
             p.AnswerCount, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId,
             p.CreationDate, ph.CreationDate
),
LinkedPosts AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        p1.Score AS SourceScore,
        p2.Score AS TargetScore,
        CASE 
            WHEN p1.Score > p2.Score THEN 'Higher'
            WHEN p1.Score < p2.Score THEN 'Lower'
            WHEN p1.Score = p2.Score THEN 'Equal'
            ELSE 'Unknown'
        END AS ScoreComparison,
        lt.Name AS LinkType
    FROM PostLinks pl
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
)
SELECT 
    um.DisplayName,
    um.Reputation,
    UPPER(SUBSTRING(um.Location FROM 1 FOR 3)) || 
        CASE WHEN LENGTH(um.Location) > 3 THEN '...' ELSE '' END AS LocationAbbr,
    um.TotalPosts,
    um.Questions + um.Answers AS QAPosts,
    ROUND(um.AvgPostScore::numeric, 2) AS AvgScore,
    COALESCE(um.MedianScore, 0) AS MedianScore,
    CASE 
        WHEN um.Questions > 0 THEN ROUND(um.Answers::numeric / um.Questions, 2)
        ELSE NULL
    END AS AnswerQuestionRatio,
    LEFT(COALESCE(um.TopTags, 'no-tags'), 50) AS TopTagsShort,
    COALESCE(ba.TotalBadges, 0) AS Badges,
    COALESCE(ba.GoldBadges, 0) || 'G-' || 
        COALESCE(ba.SilverBadges, 0) || 'S-' || 
        COALESCE(ba.BronzeBadges, 0) || 'B' AS BadgeBreakdown,
    COALESCE(ba.GoldRank, 999) AS GoldBadgeRank,
    COUNT(DISTINCT pa.PostId) AS RecentPosts,
    SUM(CASE WHEN pa.UserPostRank = 1 THEN 1 ELSE 0 END) AS TopUserPosts,
    AVG(pa.Upvotes - pa.Downvotes) FILTER (WHERE pa.Upvotes IS NOT NULL OR pa.Downvotes IS NOT NULL) AS AvgNetVotes,
    MAX(pa.ViewCount) AS MaxPostViews,
    COUNT(DISTINCT lp.RelatedPostId) AS LinkedPostCount,
    STRING_AGG(DISTINCT pa.PostStatus, '/' ORDER BY pa.PostStatus) AS PostStatuses,
    CASE 
        WHEN um.Reputation >= 10000 THEN 'Expert'
        WHEN um.Reputation >= 1000 THEN 'Experienced'
        WHEN um.Reputation >= 100 THEN 'Regular'
        ELSE 'Beginner'
    END AS UserTier,
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - MAX(ba.LastBadgeDate))) / 86400 AS DaysSinceLastBadge,
    EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = um.Id 
            AND p2.Score > (
                SELECT AVG(Score) * 2 
                FROM Posts 
                WHERE OwnerUserId = um.Id 
                    AND Score IS NOT NULL
            )
    ) AS HasOutstandingPost
FROM UserMetrics um
LEFT JOIN BadgeAnalysis ba ON um.Id = ba.UserId
LEFT JOIN PostActivity pa ON um.Id = pa.OwnerUserId
LEFT JOIN LinkedPosts lp ON pa.PostId = lp.PostId
WHERE um.Reputation > 100
    AND (um.Questions > 0 OR um.Answers > 0)
    AND um.DisplayName IS NOT NULL
GROUP BY um.Id, um.DisplayName, um.Reputation, um.Location, um.TotalPosts,
         um.Questions, um.Answers, um.AvgPostScore, um.MedianScore, um.TopTags,
         ba.TotalBadges, ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges,
         ba.GoldRank, ba.LastBadgeDate
HAVING COUNT(DISTINCT pa.PostId) > 0 
    OR COALESCE(ba.TotalBadges, 0) > 5
ORDER BY 
    um.Reputation DESC,
    COALESCE(ba.GoldBadges, 0) DESC,
    um.AvgPostScore DESC NULLS LAST
LIMIT 100;