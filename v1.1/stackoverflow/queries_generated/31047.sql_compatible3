WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= (DATE '2024-10-01' - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, u.DisplayName, p.OwnerUserId
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        ViewCount,
        Score,
        OwnerDisplayName,
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        PostRank = 1
),
AllTags AS (
    SELECT
        p.Id AS PostId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) AS CleanTags
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
PopularTags AS (
    SELECT
        tag AS Tag,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            PostId,
            CASE WHEN CleanTags = '' THEN NULL ELSE CleanTags END AS remaining
        FROM AllTags
    ) t
    JOIN LATERAL (
        WITH RECURSIVE split(postid, remaining, tag) AS (
            SELECT t.PostId, t.remaining,
                   NULL
            WHERE t.remaining IS NOT NULL
            UNION ALL
            SELECT
                postid,
                CASE
                    WHEN POSITION('><' IN remaining) > 0 THEN SUBSTRING(remaining FROM POSITION('><' IN remaining) + 2)
                    ELSE ''
                END,
                CASE
                    WHEN POSITION('><' IN remaining) > 0 THEN SUBSTRING(remaining FROM 1 FOR POSITION('><' IN remaining) - 1)
                    ELSE remaining
                END
            FROM split
            WHERE remaining IS NOT NULL AND remaining <> ''
        )
        SELECT postid, tag
        FROM split
        WHERE tag IS NOT NULL
    ) s ON TRUE
    GROUP BY tag
    ORDER BY TagCount DESC
    LIMIT 10
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.ViewCount,
    tp.Score,
    tp.OwnerDisplayName,
    tp.VoteCount,
    pt.Tag AS PopularTag
FROM 
    TopPosts tp
JOIN 
    PopularTags pt ON tp.Score > 10
ORDER BY 
    tp.Score DESC
LIMIT 20;