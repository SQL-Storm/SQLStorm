WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        p.OwnerUserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts p
    INNER JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (DATE '2024-10-01' - INTERVAL '1' MONTH)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore, 
        SUM(ViewCount) AS TotalViews
    FROM 
        Posts
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        TRIM(tag) AS TagName
    FROM 
        Posts p,
        LATERAL (
            -- remove leading '<' and trailing '>' if present, then replace '><' with a delimiter and split
            SELECT unnest(string_to_array(replace(substring(CASE WHEN p.Tags IS NULL THEN '' ELSE p.Tags END from 2 for GREATEST(length(CASE WHEN p.Tags IS NULL THEN '' ELSE p.Tags END)-2,0)), '><', '||'), '||')) AS tag
        ) tags
),
TagFrequency AS (
    SELECT 
        TagName, 
        COUNT(*) AS Frequency
    FROM 
        PostTags
    GROUP BY 
        TagName
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    tu.PostCount, 
    tu.AvgScore, 
    tu.TotalViews, 
    tg.TagName, 
    tg.Frequency
FROM 
    RecentPosts rp
INNER JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    TagFrequency tg ON pt.TagName = tg.TagName
WHERE 
    rp.Score > (SELECT AVG(Score) FROM Posts)
GROUP BY
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.OwnerReputation, rp.VoteCount, rp.UpVoteCount, rp.DownVoteCount,
    rp.OwnerUserId,
    tu.PostCount, tu.AvgScore, tu.TotalViews, tg.TagName, tg.Frequency
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    tg.Frequency DESC
LIMIT 10;