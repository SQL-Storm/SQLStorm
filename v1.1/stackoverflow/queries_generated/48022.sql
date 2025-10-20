-- {"query": "48022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 353} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
TopPostAuthors AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS NumberOfTopPosts
    FROM RankedPosts
    WHERE rn <= 100
    GROUP BY OwnerUserId
    ORDER BY NumberOfTopPosts DESC
    LIMIT 10
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    rp.PostScore,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.CommentCount,
    rp.LinkCount,
    tpa.NumberOfTopPosts AS AuthorTopPostCount
FROM RankedPosts rp
JOIN TopPostAuthors tpa ON rp.OwnerUserId = tpa.OwnerUserId
WHERE rp.rn <= 200
ORDER BY rp.rn;