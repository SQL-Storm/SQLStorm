
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        STRING_SPLIT(REPLACE(p.Tags, '><', ','), ',') AS TagsArray
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, u.DisplayName
),
TagStats AS (
    SELECT 
        value AS Tag,
        COUNT(*) AS PostCount
    FROM 
        PostStats
    CROSS APPLY TagsArray
    GROUP BY 
        value
),
PopularTags AS (
    SELECT 
        Tag,
        PostCount,
        DENSE_RANK() OVER (ORDER BY PostCount DESC) AS TagRank
    FROM 
        TagStats
    WHERE 
        PostCount > 1 
),
TagBenchmark AS (
    SELECT 
        pt.Tag,
        pt.PostCount,
        ps.OwnerDisplayName,
        ps.Title,
        ps.CommentCount,
        ps.VoteCount,
        ps.CreationDate
    FROM 
        PopularTags pt
    JOIN 
        PostStats ps ON CHARINDEX(pt.Tag, ps.TagsArray) > 0
)
SELECT 
    Tag,
    COUNT(*) AS TotalPosts,
    AVG(CommentCount) AS AvgCommentCount,
    AVG(VoteCount) AS AvgVoteCount,
    MIN(CreationDate) AS FirstPostDate,
    MAX(CreationDate) AS LastPostDate
FROM 
    TagBenchmark
GROUP BY 
    Tag
ORDER BY 
    AvgCommentCount DESC, 
    AvgVoteCount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
