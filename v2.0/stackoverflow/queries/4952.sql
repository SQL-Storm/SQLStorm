-- {"query": "4952.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1115} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCountPerPost,
        COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpVoteCountPerPost,
        COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownVoteCountPerPost,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY p.Id
),
UserPostHistory AS (
    SELECT
        ph.PostId,
        ph.UserId,
        COUNT(DISTINCT ph.Id) AS HistoryCountForUser,
        MAX(ph.CreationDate) AS LastHistoryDateForUser
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    pe.CommentCountPerPost,
    pe.UpVoteCountPerPost,
    pe.DownVoteCountPerPost,
    pe.TotalBountyAmount,
    CASE
        WHEN rp.Score > 100 AND rp.ViewCount > 10000 THEN 'High Engagement'
        WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Potentially Problematic'
        WHEN rp.FavoriteCount > 50 AND rp.AnswerCount > 20 THEN 'Popular Question'
        ELSE 'Standard'
    END AS PostCategory,
    CASE
        WHEN rp.rn <= 10 THEN 'Top 10 Recent'
        ELSE 'Older'
    END AS RecencyRank,
    rp.PreviousScore,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS OwnerDisplayNameInitial,
    COALESCE(uph.HistoryCountForUser, 0) AS UserHistoryCount,
    uph.LastHistoryDateForUser,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Community'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'User Owned'
    END AS OwnershipType,
    CASE
        WHEN rp.Score < 0 THEN 'Negative Score'
        WHEN rp.Score BETWEEN 0 AND 10 THEN 'Low Score'
        WHEN rp.Score > 10 THEN 'High Score'
        ELSE 'Zero Score'
    END AS ScoreRange,
    COALESCE(rp.Score, 0) + COALESCE(rp.ViewCount, 0) AS ScoreViewSum,
    (rp.AnswerCount * 1.0 / NULLIF(rp.FavoriteCount, 0)) AS AnswerFavoriteRatio
FROM RankedPosts rp
LEFT JOIN PostEngagement pe ON rp.PostId = pe.PostId
LEFT JOIN UserPostHistory uph ON rp.PostId = uph.PostId
WHERE rp.PostTypeId = 1 -- Focusing on Questions
  AND rp.Score > -5
  AND rp.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND rp.OwnerDisplayName IS NOT NULL
  AND rp.OwnerDisplayName <> 'Community'
  AND (pe.UpVoteCountPerPost > 10 OR pe.DownVoteCountPerPost > 5)
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 100;