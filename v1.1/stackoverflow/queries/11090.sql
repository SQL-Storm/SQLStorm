WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
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
        p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
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
        -- convert tags from format '<tag1><tag2>' to array of tag strings in a generic way
        -- use replace to change angle-bracket separators to a delimiter, then split
        TRIM(BOTH '<' FROM p.Tags) AS _tags_raw,
        NULL AS Tags -- placeholder column; final aggregation will parse tags textually
    FROM 
        Posts p
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
    COALESCE(tu.PostCount, 0) AS TopUserPostCount,
    COALESCE(tu.AvgScore, 0) AS TopUserAvgScore,
    -- build comma-separated distinct tags by splitting the raw tag string on '><' after removing leading/trailing angle brackets
    -- use standard string functions: replace '><' with ',' then remove any '<' or '>' left, then split and aggregate distinct parts
    STRING_AGG(DISTINCT TRIM(tag), ', ') AS Tags
FROM 
    RecentPosts rp
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(REPLACE(TRIM(BOTH '<' FROM p.Tags), '><', ','), ',') AS tag
    FROM Posts p
    WHERE p.Id = rp.Id
) pt ON TRUE
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerUserId, rp.OwnerDisplayName, rp.OwnerReputation, rp.VoteCount, rp.UpVoteCount, rp.DownVoteCount, tu.PostCount, tu.AvgScore
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 10;