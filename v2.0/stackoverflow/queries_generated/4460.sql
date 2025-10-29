-- {"query": "4460.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1248} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        p.Title,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT ph.Id) AS EditsMade,
        SUM(CASE WHEN p.OwnerUserId = u.Id THEN p.Score ELSE 0 END) AS TotalScoreOfOwnedPosts
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Posts p ON v.PostId = p.Id OR c.PostId = p.Id OR ph.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostType,
    COALESCE(u_owner.DisplayName, p.OwnerDisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u_editor.DisplayName, rpe.EditorDisplayName, 'Unknown') AS LastEditorDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS Status,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki' ELSE 'User Owned' END AS Ownership,
    ue.UpvotesReceived AS OwnerUpvotesReceived,
    ue.DownvotesReceived AS OwnerDownvotesReceived,
    ue.CommentsMade AS OwnerCommentsMade,
    ue.EditsMade AS OwnerEditsMade,
    ue.TotalScoreOfOwnedPosts AS OwnerTotalScoreOfOwnedPosts,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS LinkedFromCount,
    p.ContentLicense
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
LEFT JOIN Users u_editor ON rpe.UserId = u_editor.Id
LEFT JOIN UserEngagement ue ON p.OwnerUserId = ue.UserId
WHERE p.Score > 10 OR p.ViewCount > 1000
UNION ALL
SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostType,
    COALESCE(u_owner.DisplayName, p.OwnerDisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u_editor.DisplayName, rpe.EditorDisplayName, 'Unknown') AS LastEditorDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS Status,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki' ELSE 'User Owned' END AS Ownership,
    ue.UpvotesReceived AS OwnerUpvotesReceived,
    ue.DownvotesReceived AS OwnerDownvotesReceived,
    ue.CommentsMade AS OwnerCommentsMade,
    ue.EditsMade AS OwnerEditsMade,
    ue.TotalScoreOfOwnedPosts AS OwnerTotalScoreOfOwnedPosts,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS LinkedFromCount,
    p.ContentLicense
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
LEFT JOIN Users u_editor ON rpe.UserId = u_editor.Id
LEFT JOIN UserEngagement ue ON p.OwnerUserId = ue.UserId
WHERE p.Score <= 10 AND p.ViewCount <= 1000 AND p.CreationDate > '2023-01-01';