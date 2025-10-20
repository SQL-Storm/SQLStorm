WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT ans.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        STRING_AGG(DISTINCT tg.TagName, ', ') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank,
        p.PostTypeId
    FROM 
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Posts ans ON ans.ParentId = p.Id AND ans.PostTypeId = 2
        LEFT JOIN Comments c ON c.PostId = p.Id
        LEFT JOIN Tags tg ON tg.TagName = ANY (string_to_array(p.Tags, ',')) 
    WHERE 
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        AND p.Score > 0
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, p.PostTypeId
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
    LEFT JOIN (
        SELECT PostId, Comment, UserDisplayName, CreationDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6)
    ) PH ON tp.PostId = PH.PostId
ORDER BY 
    tp.Score DESC, tp.CreationDate DESC;