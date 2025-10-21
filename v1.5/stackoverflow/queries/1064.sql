WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR
        AND p.Score > 10
), HighScorers AS (
    SELECT 
        PostId, 
        Title, 
        OwnerDisplayName, 
        Score
    FROM 
        RankedPosts
    WHERE 
        rn <= 10
), PopularTags AS (
    SELECT 
        TRIM(SUBSTRING(tag.TagName FROM 2 FOR LENGTH(tag.TagName) - 2)) AS CleanedTag,
        COUNT(p.Id) AS TagFrequency
    FROM 
        Tags tag
    JOIN 
        Posts p ON POSITION(',' IN tag.TagName) IS NOT NULL
    GROUP BY 
        TRIM(SUBSTRING(tag.TagName FROM 2 FOR LENGTH(tag.TagName) - 2))
    HAVING 
        COUNT(p.Id) > 5
    ORDER BY 
        TagFrequency DESC
    LIMIT 5
), PostVotes AS (
    SELECT 
        v.PostId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Votes v 
    GROUP BY 
        v.PostId
)

SELECT 
    hp.PostId,
    hp.Title,
    hp.OwnerDisplayName,
    hp.Score,
    pt.CleanedTag,
    pv.UpVotes,
    pv.DownVotes
FROM 
    HighScorers hp
LEFT JOIN 
    PostVotes pv ON hp.PostId = pv.PostId
JOIN 
    PopularTags pt ON pt.TagFrequency > 0
ORDER BY 
    hp.Score DESC, 
    pv.UpVotes DESC NULLS LAST
LIMIT 50;