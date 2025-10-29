-- {"query": "4014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1039} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        COUNT(c.Id) OVER(PARTITION BY p.OwnerUserId) AS TotalCommentsByOwner,
        AVG(p.Score) OVER(PARTITION BY p.OwnerUserId) AS AvgScoreByOwner,
        SUM(p.ViewCount) OVER(PARTITION BY p.OwnerUserId) AS TotalViewsByOwner
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserEngagement AS (
    SELECT
        rp.OwnerUserId,
        u.DisplayName AS UserDisplayName,
        rp.TotalCommentsByOwner,
        rp.AvgScoreByOwner,
        rp.TotalViewsByOwner,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotesCast,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotesCast,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LastBadgeDate
    FROM RankedPosts rp
    JOIN Users u ON rp.OwnerUserId = u.Id
    LEFT JOIN Votes v ON rp.OwnerUserId = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Badges b ON rp.OwnerUserId = b.UserId
    GROUP BY rp.OwnerUserId, u.DisplayName, rp.TotalCommentsByOwner, rp.AvgScoreByOwner, rp.TotalViewsByOwner
),
PostMetrics AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ph.PostHistoryTypeId,
        ph.Comment AS HistoryComment,
        CASE
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) THEN JSON_VALUE(ph.Text, '$') -- Assuming Text is JSON for these types
            ELSE ph.Text
        END AS HistoryText,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC) as ph_rn
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 -- Questions only
)
SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    ue.UserDisplayName AS EngagedUserDisplayName,
    ue.TotalCommentsByOwner AS OwnerTotalComments,
    ue.AvgScoreByOwner AS OwnerAvgScore,
    ue.TotalVotesCast AS OwnerTotalVotesCast,
    ue.TotalUpvotesCast AS OwnerTotalUpvotesCast,
    ue.TotalDownvotesCast AS OwnerTotalDownvotesCast,
    ue.TotalBadgesEarned AS OwnerTotalBadgesEarned,
    ue.LastBadgeDate AS OwnerLastBadgeDate,
    pm.PostHistoryTypeId,
    pm.HistoryComment,
    pm.HistoryText AS LatestHistoryText
FROM RankedPosts rp
JOIN UserEngagement ue ON rp.OwnerUserId = ue.OwnerUserId
LEFT JOIN PostMetrics pm ON rp.PostId = pm.Id AND pm.ph_rn = 1
WHERE rp.rn <= 5 -- Top 5 most recent posts by each owner
AND ue.TotalVotesCast > 100 -- Users who have cast more than 100 votes
AND rp.Score > 0 -- Posts with a positive score
ORDER BY rp.OwnerUserId, rp.rn;
