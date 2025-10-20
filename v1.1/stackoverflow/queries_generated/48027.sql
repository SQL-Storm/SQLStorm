-- {"query": "48027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 429} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions
      AND p.Score > 100
      AND p.AnswerCount BETWEEN 5 AND 50
      AND p.ClosedDate IS NULL
),
PostDetails AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount
    FROM RankedPosts rp
    LEFT JOIN Comments c ON rp.PostId = c.PostId
    LEFT JOIN Votes v ON rp.PostId = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE rp.rn BETWEEN 1 AND 100
    GROUP BY rp.PostId, rp.Title, rp.CreationDate, rp.OwnerDisplayName
)
SELECT
    pd.PostId,
    pd.Title,
    pd.CreationDate,
    pd.OwnerDisplayName,
    pd.CommentCount,
    pd.UpVoteCount,
    pd.DownVoteCount,
    (pd.UpVoteCount - pd.DownVoteCount) AS NetVoteScore,
    (pd.CommentCount * (pd.UpVoteCount - pd.DownVoteCount)) AS EngagementScore
FROM PostDetails pd
ORDER BY EngagementScore DESC
LIMIT 10;