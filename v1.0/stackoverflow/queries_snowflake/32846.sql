
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        p.Tags
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= DATEADD(year, -1, '2024-10-01 12:34:56')
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(pl.PostId) AS RelatedPostsCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
),
FrequentTags AS (
    SELECT 
        TRIM(value) AS TagName
    FROM 
        Posts p,
        LATERAL FLATTEN(input => SPLIT(p.Tags, ','))
    WHERE 
        p.CreationDate >= DATEADD(year, -1, '2024-10-01 12:34:56')
),
TagCounts AS (
    SELECT 
        TagName,
        COUNT(*) AS TagUsageCount
    FROM 
        FrequentTags
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName
    FROM 
        TagCounts
    ORDER BY 
        TagUsageCount DESC
    LIMIT 10
)

SELECT 
    ua.DisplayName,
    ua.UserId,
    rp.Title,
    rp.Score,
    rp.CreationDate,
    ta.TagName,
    ua.RelatedPostsCount,
    ua.UpVotesCount,
    ua.DownVotesCount,
    (CASE 
        WHEN rp.PostTypeId = 1 THEN 'Question'
        WHEN rp.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other' 
     END) AS PostType,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCount
FROM 
    RankedPosts rp
JOIN 
    UserActivity ua ON ua.UserId = rp.OwnerUserId 
JOIN 
    TopTags ta ON ta.TagName IN (SELECT value FROM TABLE(FLATTEN(INPUT => SPLIT(rp.Tags, ','))))
WHERE 
    rp.ScoreRank <= 5
ORDER BY 
    rp.Score DESC, 
    ua.UpVotesCount DESC;
