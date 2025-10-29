-- {"query": "4295.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2476} 
WITH RelevantPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PrimaryPostType,
        COALESCE(p.Title, 'N/A') AS PostTitle,
        CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN '[]'
            ELSE p.Tags
        END AS PostTags
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2023-01-01' AND p.Score > 0
),
PostHistoryAggregates AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN ph.Id END) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN ph.CreationDate END) AS LastEditDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVoteCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseVoteDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) AS UndeleteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.Id END) AS ProtectCount
    FROM PostHistory AS ph
    WHERE ph.PostId IN (SELECT PostId FROM RelevantPosts)
    GROUP BY ph.PostId
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS DECIMAL(10, 2))) AS AverageCommentScore,
        COUNT(DISTINCT CASE WHEN c.UserId IS NULL THEN c.Id END) AS AnonymousCommentCount
    FROM Comments AS c
    WHERE c.PostId IN (SELECT PostId FROM RelevantPosts)
    GROUP BY c.PostId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS UserPostCount,
        SUM(p.Score) AS UserTotalPostScore,
        MAX(p.CreationDate) AS UserLastPostDate,
        COUNT(DISTINCT b.Id) AS UserBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS UserGoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS UserSilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS UserBronzeBadgeCount
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RelevantPosts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostTitle,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostAnswerCount,
    rp.PostCommentCount,
    rp.PostFavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    ph.EditCount,
    ph.LastEditDate,
    ph.CloseVoteCount,
    ph.LastCloseVoteDate,
    ph.UndeleteCount,
    ph.ProtectCount,
    cs.CommentCount AS DistinctCommentCount,
    cs.TotalCommentScore,
    cs.AverageCommentScore,
    cs.AnonymousCommentCount,
    ua.UserPostCount,
    ua.UserTotalPostScore,
    ua.UserLastPostDate,
    ua.UserBadgeCount,
    ua.UserGoldBadgeCount,
    ua.UserSilverBadgeCount,
    ua.UserBronzeBadgeCount,
    ROW_NUMBER() OVER (ORDER BY rp.PostScore DESC, rp.PostCreationDate ASC) AS RankByScore,
    DENSE_RANK() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.PostFavoriteCount DESC) AS RankWithinTypeByFavorites,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CONCAT(
        COALESCE(ua.UserReputation, 0),
        ' (',
        COALESCE(CAST(ua.UserGoldBadgeCount AS VARCHAR), '0'),
        'G, ',
        COALESCE(CAST(ua.UserSilverBadgeCount AS VARCHAR), '0'),
        'S, ',
        COALESCE(CAST(ua.UserBronzeBadgeCount AS VARCHAR), '0'),
        'B)'
    ) AS UserReputationWithBadges,
    CASE
        WHEN LOWER(rp.PostTags) LIKE '%<sql>%' THEN 'Contains SQL Tag'
        WHEN LOWER(rp.PostTags) LIKE '%<performance>%' THEN 'Contains Performance Tag'
        ELSE 'Other Tags'
    END AS TagCategory,
    IIF(rp.PostAnswerCount > 10 AND rp.PostScore > 50, 'Highly Engaged', 'Standard') AS EngagementLevel
FROM RelevantPosts AS rp
LEFT JOIN PostHistoryAggregates AS ph ON rp.PostId = ph.PostId
LEFT JOIN CommentStats AS cs ON rp.PostId = cs.PostId
LEFT JOIN (
    SELECT
        u.Id AS UserId,
        u.Reputation AS UserReputation,
        COUNT(DISTINCT b.Id) AS UserBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS UserGoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS UserSilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS UserBronzeBadgeCount
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RelevantPosts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.Reputation
) AS ua ON rp.OwnerUserId = ua.UserId
WHERE rp.PostScore > (SELECT AVG(PostScore) FROM RelevantPosts)
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostTitle,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostAnswerCount,
    rp.PostCommentCount,
    rp.PostFavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    ph.EditCount,
    ph.LastEditDate,
    ph.CloseVoteCount,
    ph.LastCloseVoteDate,
    ph.UndeleteCount,
    ph.ProtectCount,
    cs.CommentCount AS DistinctCommentCount,
    cs.TotalCommentScore,
    cs.AverageCommentScore,
    cs.AnonymousCommentCount,
    ua.UserPostCount,
    ua.UserTotalPostScore,
    ua.UserLastPostDate,
    ua.UserBadgeCount,
    ua.UserGoldBadgeCount,
    ua.UserSilverBadgeCount,
    ua.UserBronzeBadgeCount,
    ROW_NUMBER() OVER (ORDER BY rp.PostScore DESC, rp.PostCreationDate ASC) AS RankByScore,
    DENSE_RANK() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.PostFavoriteCount DESC) AS RankWithinTypeByFavorites,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CONCAT(
        COALESCE(ua.UserReputation, 0),
        ' (',
        COALESCE(CAST(ua.UserGoldBadgeCount AS VARCHAR), '0'),
        'G, ',
        COALESCE(CAST(ua.UserSilverBadgeCount AS VARCHAR), '0'),
        'S, ',
        COALESCE(CAST(ua.UserBronzeBadgeCount AS VARCHAR), '0'),
        'B)'
    ) AS UserReputationWithBadges,
    CASE
        WHEN LOWER(rp.PostTags) LIKE '%<sql>%' THEN 'Contains SQL Tag'
        WHEN LOWER(rp.PostTags) LIKE '%<performance>%' THEN 'Contains Performance Tag'
        ELSE 'Other Tags'
    END AS TagCategory,
    IIF(rp.PostAnswerCount > 10 AND rp.PostScore > 50, 'Highly Engaged', 'Standard') AS EngagementLevel
FROM RelevantPosts AS rp
JOIN PostHistoryAggregates AS ph ON rp.PostId = ph.PostId
LEFT JOIN CommentStats AS cs ON rp.PostId = cs.PostId
LEFT JOIN (
    SELECT
        u.Id AS UserId,
        u.Reputation AS UserReputation,
        COUNT(DISTINCT b.Id) AS UserBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS UserGoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS UserSilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS UserBronzeBadgeCount
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RelevantPosts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.Reputation
) AS ua ON rp.OwnerUserId = ua.UserId
WHERE rp.PostAnswerCount > (SELECT AVG(PostAnswerCount) FROM RelevantPosts) AND rp.ClosedDate IS NULL;