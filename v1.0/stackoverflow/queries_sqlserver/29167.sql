
WITH TagUsage AS (
    SELECT 
        value AS Tag,
        Id AS PostId
    FROM 
        Posts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><')
    WHERE 
        PostTypeId = 1 
),
TagStats AS (
    SELECT 
        Tag,
        COUNT(DISTINCT PostId) AS TagCount
    FROM 
        TagUsage
    GROUP BY 
        Tag
),
TopTags AS (
    SELECT 
        Tag,
        TagCount,
        ROW_NUMBER() OVER (ORDER BY TagCount DESC) AS Rank
    FROM 
        TagStats
),
PostInteraction AS (
    SELECT 
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        ISNULL(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        ISNULL(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount,
        ISNULL(SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END), 0) AS CloseVoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        p.Id
),
FinalStats AS (
    SELECT 
        tt.Tag,
        pi.PostId,
        p.Title,
        pi.CommentCount,
        pi.UpvoteCount,
        pi.DownvoteCount,
        pi.CloseVoteCount
    FROM 
        PostInteraction pi
    JOIN 
        Posts p ON pi.PostId = p.Id
    JOIN 
        TopTags tt ON tt.Rank <= 10 
    WHERE 
        tt.Tag IN (SELECT value FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><'))
)
SELECT 
    fs.Tag,
    COUNT(fs.PostId) AS PostCount,
    SUM(fs.CommentCount) AS TotalComments,
    SUM(fs.UpvoteCount) AS TotalUpvotes,
    SUM(fs.DownvoteCount) AS TotalDownvotes,
    SUM(fs.CloseVoteCount) AS TotalCloseVotes
FROM 
    FinalStats fs
GROUP BY 
    fs.Tag
ORDER BY 
    PostCount DESC, 
    TotalUpvotes DESC;
