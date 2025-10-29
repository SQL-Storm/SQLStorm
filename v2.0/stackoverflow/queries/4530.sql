WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.ViewCount > 100
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
ComplexPostDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryUserId,
        u.DisplayName AS HistoryUserDisplayName,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryTextOrRelatedIds,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as history_rn
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS RecentCommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS RecentUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS RecentDownvotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.CreationDate > p.LastActivityDate - INTERVAL '7' DAY
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate > p.LastActivityDate - INTERVAL '7' DAY
    GROUP BY p.Id
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PostsWithPositiveScore,
        AVG(p.Score) AS AverageScoreForTag,
        SUM(p.AnswerCount) AS TotalAnswersForTag,
        AVG(p.FavoriteCount) AS AverageFavoritesForTag,
        (SELECT COUNT(*) FROM Tags sub_t WHERE sub_t.TagName LIKE '%' || t.TagName || '%') AS SimilarTagCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE t.TagName NOT IN ('sql', 'performance', 'database', 'query')
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    ups.DisplayName AS OwnerDisplayName,
    ups.Reputation,
    ups.UserCreationDate,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    cd.Title,
    cd.Tags,
    cd.HistoryTypeName,
    cd.HistoryUserDisplayName,
    cd.HistoryComment,
    cd.HistoryTextOrRelatedIds,
    ra.RecentCommentCount,
    ra.RecentUpvotes,
    ra.RecentDownvotes,
    tp.TagName,
    tp.AverageScoreForTag,
    tp.TotalAnswersForTag,
    tp.AverageFavoritesForTag,
    tp.SimilarTagCount,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    CASE
        WHEN rp.PostTypeId = 1 THEN 'Is Question'
        WHEN rp.PostTypeId = 2 THEN 'Is Answer'
        ELSE 'Other'
    END AS PostTypeCategory,
    COALESCE(rp.AnswerCount, 0) AS NonNullAnswerCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    rp.PostCreationDate,
    (rp.PostScore * 1.0 / NULLIF(rp.PostViewCount, 0)) AS ScorePerViewRatio,
    UPPER(SUBSTRING(cd.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE
        WHEN ups.Reputation > 100000 THEN 'High Reputation'
        WHEN ups.Reputation BETWEEN 10000 AND 100000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationLevel,
    CASE
        WHEN COALESCE(ra.RecentUpvotes,0) > COALESCE(ra.RecentDownvotes,0) * 2 AND COALESCE(ra.RecentUpvotes,0) > 5 THEN 'Trending Up'
        WHEN COALESCE(ra.RecentDownvotes,0) > COALESCE(ra.RecentUpvotes,0) * 2 AND COALESCE(ra.RecentDownvotes,0) > 5 THEN 'Trending Down'
        ELSE 'Stable'
    END AS RecentVoteTrend
FROM RankedPosts rp
JOIN UserPostStats ups ON rp.OwnerUserId = ups.UserId
LEFT JOIN ComplexPostDetails cd ON rp.PostId = cd.Id AND cd.history_rn = 1
LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId
LEFT JOIN TagPerformance tp ON cd.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
WHERE rp.rn <= 10
  AND (tp.TagName IS NOT NULL OR rp.PostTypeId = 1)
ORDER BY rp.PostCreationDate DESC, tp.AverageScoreForTag DESC
LIMIT 100;