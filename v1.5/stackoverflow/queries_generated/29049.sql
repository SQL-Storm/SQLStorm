-- {"query": "29049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2155} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.LastActivityDate,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN 'High Score'
            ELSE 'Regular'
        END AS PostStatus,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS TimelineOrder,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
        NTILE(4) OVER (ORDER BY p.ViewCount) AS Quartile,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') ELSE ARRAY[]::TEXT[] END AS TagArray,
        (
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.PostId = p.Id 
              AND c.Score > 0
        ) AS PositiveCommentCount,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = p.Id 
              AND v.VoteTypeId IN (2, 3)
        ) AS VoteCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2022-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY u.Views) AS ViewPercentile,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Elite'
            WHEN u.Reputation >= 10000 THEN 'Veteran'
            WHEN u.Reputation >= 1000 THEN 'Contributor'
            ELSE 'Member'
        END AS UserTier,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        COALESCE(u.Location, 'Unknown Location') AS Location
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.WebsiteUrl, u.Location
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count >= 1000 THEN 'Popular'
            WHEN t.Count >= 100 THEN 'Moderately Popular'
            WHEN t.Count >= 10 THEN 'Emerging'
            ELSE 'Niche'
        END AS TagPopularity,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    WHERE t.Count > 0
),
ComplexPostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.PostStatus,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.ScoreRank,
        ps.TimelineOrder,
        ps.PrevScore,
        ps.NextScore,
        ps.AvgScoreByType,
        ps.Quartile,
        ps.TagArray,
        ps.PositiveCommentCount,
        ps.VoteCount,
        ps.OwnerUserId,
        u.UserTier,
        COALESCE(u.DisplayName, 'Anonymous') AS AuthorName,
        u.Reputation AS AuthorReputation,
        u.Views AS AuthorViews,
        (
            SELECT STRING_AGG(t, ', ')
            FROM unnest(ps.TagArray) AS t
            WHERE t IS NOT NULL AND t != ''
        ) AS CombinedTags,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = ps.PostId
        ) AS LinkCount,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = ps.PostId
              AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        ) AS EditHistoryCount,
        (
            SELECT COUNT(*)
            FROM Votes v
            WHERE v.PostId = ps.PostId
              AND v.VoteTypeId = 1
        ) AS AcceptanceCount,
        (
            CASE 
                WHEN ps.Score > ps.AvgScoreByType * 1.5 AND ps.ViewCount > 100 THEN 'High Engagement'
                WHEN ps.Score > ps.AvgScoreByType AND ps.ViewCount > 50 THEN 'Standard Engagement'
                ELSE 'Low Engagement'
            END
        ) AS EngagementLevel,
        COALESCE(ps.Title, 'No Title') AS Title,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) AS UserPostSequence,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b
            WHERE b.UserId = ps.OwnerUserId
              AND b.Date > '2022-01-01'
        ) AS RecentBadges
    FROM PostStats ps
    LEFT JOIN UserActivity u ON ps.OwnerUserId = u.UserId
    WHERE ps.Score >= 0 
      AND ps.ViewCount >= 0
)

SELECT 
    cpa.PostId,
    cpa.PostStatus,
    cpa.Score,
    cpa.ViewCount,
    cpa.AnswerCount,
    cpa.CommentCount,
    cpa.FavoriteCount,
    cpa.ScoreRank,
    cpa.TimelineOrder,
    cpa.PrevScore,
    cpa.NextScore,
    ROUND(cpa.AvgScoreByType, 2) AS AvgScoreByType,
    cpa.Quartile,
    cpa.CombinedTags,
    cpa.PositiveCommentCount,
    cpa.VoteCount,
    cpa.OwnerUserId,
    cpa.AuthorName,
    CASE 
        WHEN cpa.AuthorReputation IS NULL THEN 'Not Found'
        WHEN cpa.AuthorReputation >= 10000 THEN 'High'
        WHEN cpa.AuthorReputation >= 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    cpa.AuthorViews,
    cpa.LinkCount,
    cpa.EditHistoryCount,
    cpa.AcceptanceCount,
    cpa.EngagementLevel,
    cpa.Title,
    cpa.UserPostSequence,
    COALESCE(cpa.RecentBadges, 'No Recent Badges') AS RecentBadges,
    (
        SELECT COUNT(*) 
        FROM ComplexPostAnalysis cpa2 
        WHERE cpa2.OwnerUserId = cpa.OwnerUserId
    ) AS TotalPostsByAuthor,
    (
        SELECT STRING_AGG(DISTINCT t, ' | ')
        FROM unnest(cpa.TagArray) AS t
        WHERE t IS NOT NULL AND t != ''
    ) AS DistinctTags,
    (
        SELECT AVG(Score) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = cpa.OwnerUserId
          AND p3.CreatedDate >= '2022-01-01'
    ) AS AvgScorePerUser,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph2 
        WHERE ph2.PostId = cpa.PostId
          AND ph2.CreationDate >= '2022-01-01'
    ) AS RecentEdits,
    CASE 
        WHEN cpa.FavoriteCount > 10 THEN 'Highly Favorited'
        WHEN cpa.FavoriteCount > 5 THEN 'Moderately Favorited'
        ELSE 'Less Favorited'
    END AS FavoriteCategory,
    (
        SELECT STRING_AGG(b.Name, ', ')
        FROM Badges b
        WHERE b.UserId = cpa.OwnerUserId
          AND b.Date BETWEEN '2022-01-01' AND '2023-01-01'
          AND b.Class = 1
    ) AS RecentGoldBadges,
    (
        CASE 
            WHEN cpa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.2 THEN 1
            ELSE 0
        END
    ) AS AboveAverageScore,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = cpa.PostId
          AND c.CreationDate >= '2022-01-01'
    ) AS RecentComments,
    (
        SELECT DISTINCT p2.Title
        FROM Posts p2
        JOIN PostLinks pl ON p2.Id = pl.RelatedPostId
        WHERE pl.PostId = cpa.PostId
          AND p2.PostTypeId = 2
        LIMIT 1
    ) AS RelatedAnswerTitle
FROM ComplexPostAnalysis cpa
WHERE cpa.PostStatus != 'Regular'
ORDER BY cpa.Score DESC, cpa.ViewCount DESC, cpa.TimelineOrder ASC
LIMIT 2000 OFFSET 500;