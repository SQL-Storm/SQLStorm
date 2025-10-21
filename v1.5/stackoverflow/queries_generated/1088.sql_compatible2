WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS Author,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, p.PostTypeId
),
TopPosts AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.Author
    FROM 
        RankedPosts rp
    WHERE 
        rp.PostRank <= 5
),
PostAnalytics AS (
    SELECT 
        tp.Id,
        tp.Title,
        tp.ViewCount,
        tp.Score,
        (SELECT AVG(ViewCount) FROM Posts WHERE CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)) AS AverageViewCount,
        CASE 
            WHEN tp.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)) THEN 'Above Average'
            ELSE 'Below Average'
        END AS ViewCountComparison
    FROM 
        TopPosts tp
)
SELECT 
    pa.Id,
    pa.Title,
    pa.ViewCount,
    pa.Score,
    pa.AverageViewCount,
    pa.ViewCountComparison,
    CASE 
        WHEN pa.Score IS NULL THEN 'No Score'
        ELSE CAST(pa.Score AS VARCHAR)
    END AS ScoreDisplay
FROM 
    PostAnalytics pa
ORDER BY 
    pa.Score DESC NULLS LAST;