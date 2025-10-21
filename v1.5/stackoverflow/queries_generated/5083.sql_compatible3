WITH
MostDiscussedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 10 THEN 1 ELSE 0 END) AS HiScoreComments,
        MAX(c.Score) AS MaxCommentScore,
        MIN(c.Score) AS MinCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' YEAR)
      AND p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.PostTypeId, u.DisplayName
    HAVING COUNT(c.Id) > 0 + 10
),
TopVotedPostsCTE AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.Score > 50
      AND p.ViewCount > 5000
      AND p.PostTypeId = 1
),
BadgersCTE AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
ClosedPostsCTE AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        cr.Name AS CloseReason,
        ph.UserId AS ClosedByUserId,
        ph.CreationDate AS ClosedDate
    FROM Posts p
    INNER JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INTEGER) = cr.Id
    WHERE p.ClosedDate IS NOT NULL AND p.PostTypeId = 1
)
SELECT
    md.PostId,
    md.Title,
    pt.Name AS PostType,
    COALESCE(md.OwnerName, 'Anonymous') AS OwnerName,
    md.CommentCount,
    md.HiScoreComments,
    md.MaxCommentScore,
    md.MinCommentScore,
    md.LastCommentDate,
    CASE WHEN tvp.Id IS NOT NULL THEN 'HighScore' ELSE NULL END AS HighScoreTag,
    bct.DistinctBadges,
    bct.GoldBadges,
    cp.CloseReason,
    CAST(cp.ClosedDate AS TIMESTAMP) AS ClosedDate,
    CONCAT('https://stackoverflow.com/posts/', md.PostId) AS PostUrl
FROM MostDiscussedPosts md
LEFT JOIN TopVotedPostsCTE tvp ON md.PostId = tvp.Id AND tvp.rn <= 100
LEFT JOIN BadgersCTE bct ON COALESCE(md.OwnerName, '') = bct.DisplayName
LEFT JOIN PostTypes pt ON md.PostTypeId = pt.Id
LEFT OUTER JOIN ClosedPostsCTE cp ON md.PostId = cp.PostId
WHERE (md.HiScoreComments > 1 AND (md.MaxCommentScore - md.MinCommentScore) > 3)
   OR cp.CloseReason IS NOT NULL
   OR bct.GoldBadges >= 2
ORDER BY
    md.CommentCount DESC,
    md.HiScoreComments DESC,
    COALESCE(bct.GoldBadges, 0) DESC
LIMIT 50;