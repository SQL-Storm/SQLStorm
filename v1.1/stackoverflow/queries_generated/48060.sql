-- {"query": "48060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 784} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS Rank
    FROM Posts AS p
    JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.Score > 0
      AND p.CreationDate >= DATE('now', '-1 year')
),
RecentComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS RecentCommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE c.CreationDate >= DATE('now', '-7 days')
    GROUP BY c.PostId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS EditsTitle,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS EditsBody,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 END) AS EditsTags,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 END) AS UndeleteVotes
    FROM PostHistory AS ph
    WHERE ph.CreationDate >= DATE('now', '-1 month')
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    COALESCE(rc.RecentCommentCount, 0) AS RecentComments,
    COALESCE(rc.LastCommentDate, rp.PostCreationDate) AS LastActivityOrComment,
    COALESCE(phs.EditsTitle, 0) AS TitleEditsLastMonth,
    COALESCE(phs.EditsBody, 0) AS BodyEditsLastMonth,
    COALESCE(phs.EditsTags, 0) AS TagEditsLastMonth,
    COALESCE(phs.CloseVotes, 0) AS CloseVotesLastMonth,
    COALESCE(phs.UndeleteVotes, 0) AS UndeleteVotesLastMonth,
    CASE
        WHEN rp.Rank <= 100 THEN 'Top 100 by Score/Favorites'
        WHEN rp.Rank <= 500 THEN 'Top 500 by Score/Favorites'
        ELSE 'Other'
    END AS PopularityTier
FROM RankedPosts AS rp
LEFT JOIN RecentComments AS rc ON rp.PostId = rc.PostId
LEFT JOIN PostHistorySummary AS phs ON rp.PostId = phs.PostId
WHERE rp.Rank <= 500
ORDER BY rp.Rank;
