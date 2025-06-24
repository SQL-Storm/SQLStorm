WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.LastActivityDate,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS RankPerTag,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1 -- Filter for questions only
    GROUP BY 
        p.Id, u.DisplayName, p.Title, p.Body, p.Tags, p.CreationDate, p.LastActivityDate, p.AcceptedAnswerId
),
TagSummary AS (
    SELECT 
        UNNEST(string_to_array(Tags, '>')) AS TagName,
        COUNT(*) AS PostCount,
        SUM(UpvoteCount - DownvoteCount) AS NetVotes
    FROM 
        RankedPosts
    WHERE 
        RankPerTag = 1 -- Only consider the top post per tag
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        NetVotes,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, NetVotes DESC) AS TagRanking
    FROM 
        TagSummary
)
SELECT 
    tt.TagName,
    tt.PostCount,
    tt.NetVotes,
    rp.Title AS TopPostTitle,
    rp.OwnerDisplayName,
    rp.CreationDate
FROM 
    TopTags tt
JOIN 
    RankedPosts rp ON rp.Tags LIKE '%' || tt.TagName || '%'
WHERE 
    tt.TagRanking <= 5 -- Get top 5 tags
AND 
    rp.RankPerTag = 1 -- Ensure we get the top post per tag
ORDER BY 
    tt.TagRanking;
