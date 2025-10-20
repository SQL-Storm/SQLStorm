WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),

PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId, u.DisplayName
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Tags,
        p.AnswerCount,
        p.ViewCount,
        p.Score,
        p.CommentCount,
        COUNT(DISTINCT c.Id) AS RecentCommentCount,
        COUNT(DISTINCT v.Id) AS RecentVoteCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') -- Posts created in the last 30 days
    GROUP BY
        p.Id, p.Title, p.Body, p.CreationDate, p.LastActivityDate, p.OwnerUserId, u.DisplayName, p.Tags, p.AnswerCount, p.ViewCount, p.Score, p.CommentCount
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.DisplayName,
    ua.LastAccessDate,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.Score AS PostScore,
    pm.ViewCount AS PostViewCount,
    pm.AnswerCount AS PostAnswerCount,
    pm.CommentCount AS PostCommentCount,
    pm.FavoriteCount AS PostFavoriteCount,
    pm.OwnerUserId AS PostOwnerUserId,
    pm.OwnerDisplayName AS PostOwnerDisplayName,
    rp.PostId as RecentPostId,
    rp.Title as RecentPostTitle,
    rp.Body as RecentPostBody,
    rp.CreationDate as RecentPostCreationDate,
    rp.LastActivityDate AS RecentPostLastActivityDate,
    rp.OwnerUserId AS RecentPostOwnerUserId,
    rp.OwnerDisplayName AS RecentPostOwnerDisplayName,
    rp.Tags AS RecentPostTags,
    rp.AnswerCount AS RecentPostAnswerCount,
    rp.ViewCount AS RecentPostViewCount,
    rp.Score AS RecentPostScore,
    rp.CommentCount AS RecentPostCommentCount,
    rp.RecentCommentCount,
    rp.RecentVoteCount
FROM
    UserActivity ua
LEFT JOIN
    PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN
    RecentPosts rp ON ua.UserId = rp.OwnerUserId
ORDER BY
  ua.Reputation DESC,
  pm.Score DESC,
  rp.CreationDate DESC
LIMIT 1000;