
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        @row_num := IF(@prev_user = p.OwnerUserId, @row_num + 1, 1) AS PostRank,
        @prev_user := p.OwnerUserId,
        COALESCE(u.Reputation, 0) AS UserReputation
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id,
        (SELECT @row_num := 0, @prev_user := NULL) r
    WHERE 
        p.CreationDate >= NOW() - INTERVAL 1 YEAR
        AND p.PostTypeId = 1  
),
TopPosts AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.ViewCount,
        rp.Score,
        rp.UserReputation,
        CASE WHEN rp.UserReputation > 1000 THEN 'Veteran' ELSE 'Newbie' END AS UserTier
    FROM 
        RankedPosts rp
    WHERE 
        rp.PostRank <= 5  
),
CommentsSummary AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
FinalResults AS (
    SELECT 
        tp.Title,
        tp.ViewCount,
        tp.Score,
        tp.UserReputation,
        tp.UserTier,
        COALESCE(cs.CommentCount, 0) AS TotalComments,
        COALESCE(cs.LastCommentDate, '1970-01-01') AS LastCommentDate
    FROM 
        TopPosts tp
    LEFT JOIN 
        CommentsSummary cs ON tp.Id = cs.PostId
)
SELECT 
    fr.Title,
    fr.ViewCount,
    fr.Score,
    fr.UserTier,
    fr.TotalComments,
    fr.LastCommentDate,
    CONCAT('Reputation is ', CASE 
        WHEN fr.UserReputation IS NULL THEN 'Not Available' 
        WHEN fr.UserReputation < 500 THEN 'Low'
        WHEN fr.UserReputation BETWEEN 500 AND 1000 THEN 'Moderate' 
        ELSE 'High' 
    END) AS ReputationValue,
    CASE 
        WHEN fr.TotalComments > 10 THEN 'Highly Discussed' 
        WHEN fr.TotalComments BETWEEN 1 AND 10 THEN 'Moderately Discussed' 
        ELSE 'Not Discussed' 
    END AS DiscussionLevel
FROM 
    FinalResults fr
WHERE 
    fr.ViewCount > 100 
ORDER BY 
    fr.Score DESC, fr.ViewCount DESC
LIMIT 25;
