-- {"query": "48073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 839} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions only
),
AggregatedPostData AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostCreationDate,
        rp.OwnerDisplayName,
        rp.OwnerReputation,
        rp.PostScore,
        rp.PostViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS ActualCommentCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId OR pl.RelatedPostId = rp.PostId) AS LinkCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT SUM(Score) FROM Comments c WHERE c.PostId = rp.PostId) AS TotalCommentScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVoteCount
    FROM RankedPosts rp
    WHERE rp.RowNum BETWEEN 1000 AND 2000 -- Selecting a specific range of recent posts
)
SELECT
    apd.PostId,
    apd.Title,
    apd.PostCreationDate,
    apd.OwnerDisplayName,
    apd.OwnerReputation,
    apd.PostScore,
    apd.PostViewCount,
    apd.AnswerCount,
    apd.ActualCommentCount,
    apd.LinkCount,
    apd.EditCount,
    apd.TotalCommentScore,
    apd.UpVoteCount,
    apd.DownVoteCount,
    CASE
        WHEN apd.PostScore > 0 THEN CAST(apd.PostViewCount AS REAL) / apd.PostScore
        ELSE NULL
    END AS ViewScoreRatio,
    CASE
        WHEN apd.AnswerCount > 0 THEN CAST(apd.CommentCount AS REAL) / apd.AnswerCount
        ELSE NULL
    END AS CommentAnswerRatio,
    CASE
        WHEN apd.PostViewCount > 0 THEN CAST(apd.EditCount AS REAL) / apd.PostViewCount
        ELSE NULL
    END AS EditViewRatio,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = apd.PostId) AND b.Class = 1) AS OwnerGoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = apd.PostId) AND b.Class = 2) AS OwnerSilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = apd.PostId) AND b.Class = 3) AS OwnerBronzeBadges
FROM AggregatedPostData apd
ORDER BY apd.PostCreationDate DESC
LIMIT 100;