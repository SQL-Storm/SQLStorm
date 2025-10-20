-- {"query": "48044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 420} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100
),
PostInteractions AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY p.Id
)
SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    pi.CommentCount,
    pi.VoteCount,
    pi.UpVoteCount,
    pi.DownVoteCount,
    pi.FavoriteCount,
    CAST(rp.Score AS REAL) / pi.VoteCount AS ScorePerVoteRatio,
    CAST(pi.CommentCount AS REAL) / (pi.VoteCount + 1) AS CommentsPerVoteRatio
FROM RankedPosts rp
JOIN PostInteractions pi ON rp.PostId = pi.PostId
WHERE rp.RowNum BETWEEN 1 AND 1000
ORDER BY rp.Score DESC;