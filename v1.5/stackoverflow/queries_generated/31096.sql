-- {"query": "31096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 405} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        COUNT(ans.Id) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Posts ans ON ans.ParentId = p.Id AND ans.PostTypeId = 2
        LEFT JOIN Comments c ON c.PostId = p.Id
        LEFT JOIN string_to_array(p.Tags, ',') AS t ON t = ANY(SELECT TagName FROM Tags)
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
        AND p.Score > 0
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName
),
TopPosts AS (
    SELECT * FROM RankedPosts WHERE Rank <= 10
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerDisplayName,
    tp.AnswerCount,
    tp.CommentCount,
    tp.Tags,
    PH.Comment AS ChangeComment,
    PH.UserDisplayName AS EditedBy,
    PH.CreationDate AS EditDate
FROM 
    TopPosts tp
    LEFT JOIN PostHistory PH ON tp.PostId = PH.PostId
WHERE 
    PH.PostHistoryTypeId IN (4, 5, 6)  -- Filtering for edits to Title, Body, or Tags
ORDER BY 
    tp.Score DESC, tp.CreationDate DESC;
