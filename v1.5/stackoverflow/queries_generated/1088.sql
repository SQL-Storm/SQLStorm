-- {"query": "1088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 385} 

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
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, u.DisplayName
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
        (SELECT AVG(ViewCount) FROM Posts WHERE CreationDate >= NOW() - INTERVAL '1 year') AS AverageViewCount,
        CASE 
            WHEN tp.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE CreationDate >= NOW() - INTERVAL '1 year') THEN 'Above Average'
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
        ELSE pa.Score::varchar
    END AS ScoreDisplay
FROM 
    PostAnalytics pa
ORDER BY 
    pa.Score DESC NULLS LAST;
