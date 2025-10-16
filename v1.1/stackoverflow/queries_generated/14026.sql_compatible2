WITH cte AS (
    SELECT 
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        COALESCE(p.Score, 0) AS Score,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        COALESCE(u.Views, 0) AS OwnerViews,
        COALESCE(u.UpVotes, 0) AS OwnerUpVotes,
        COALESCE(u.DownVotes, 0) AS OwnerDownVotes,
        COALESCE(b.Name, '') AS OwnerBadges,
        COALESCE(b.Class, 0) AS OwnerBadgeClass,
        CASE WHEN b.TagBased IS NULL THEN 0 ELSE CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END END AS OwnerBadgeTagBased,
        COALESCE(b.Date, p.CreationDate) AS OwnerBadgeDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        CASE WHEN p.ParentId IS NOT NULL THEN 1 ELSE 0 END AS IsAnswer,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        CASE WHEN p.CreationDate BETWEEN (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') AND CAST('2024-10-01' AS DATE) THEN 1 ELSE 0 END AS IsRecent,
        CASE WHEN p.CreationDate BETWEEN (CAST('2024-10-01' AS DATE) - INTERVAL '1 month') AND CAST('2024-10-01' AS DATE) THEN 1 ELSE 0 END AS IsVeryRecent
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
),
post_stats AS (
    SELECT 
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes
    GROUP BY PostId
),
comment_stats AS (
    SELECT 
        PostId, 
        COUNT(*) AS CommentCount,
        SUM(Score) AS CommentScore
    FROM Comments
    GROUP BY PostId
)
SELECT
    cte.PostId,
    cte.ParentId,
    cte.PostTypeId,
    cte.CreationDate,
    cte.OwnerUserId,
    cte.Title,
    cte.Tags,
    cte.Score,
    cte.AnswerCount,
    cte.CommentCount,
    cte.FavoriteCount,
    cte.OwnerDisplayName,
    cte.OwnerReputation,
    cte.OwnerViews,
    cte.OwnerUpVotes,
    cte.OwnerDownVotes,
    cte.OwnerBadges,
    cte.OwnerBadgeClass,
    cte.OwnerBadgeTagBased,
    cte.OwnerBadgeDate,
    cte.IsClosed,
    cte.IsCommunityOwned,
    cte.HasAcceptedAnswer,
    cte.IsAnswer,
    cte.ViewCount,
    cte.FavoriteCount AS PostFavoriteCount,
    cte.CommentCount AS PostCommentCount,
    cte.AnswerCount AS PostAnswerCount,
    cte.Score AS PostScore,
    cte.IsRecent,
    cte.IsVeryRecent,
    COALESCE(post_stats.UpVotes, 0) AS PostUpVotes,
    COALESCE(post_stats.DownVotes, 0) AS PostDownVotes,
    COALESCE(post_stats.Favorites, 0) AS PostFavorites,
    COALESCE(comment_stats.CommentCount, 0) AS TotalCommentCount,
    COALESCE(comment_stats.CommentScore, 0) AS TotalCommentScore
FROM cte
LEFT JOIN post_stats ON cte.PostId = post_stats.PostId
LEFT JOIN comment_stats ON cte.PostId = comment_stats.PostId
ORDER BY cte.CreationDate DESC
LIMIT 100;