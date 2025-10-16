-- {"query": "11041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 593} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        p.Tags, 
        COUNT(v.Id) AS VoteCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, p.Tags
),
TaggedPosts AS (
    SELECT 
        PostId,
        UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), ''><'')) AS TagName
    FROM Posts
    WHERE Tags IS NOT NULL
),
PostTagCounts AS (
    SELECT 
        PostId, 
        COUNT(*) AS TagCount
    FROM TaggedPosts
    GROUP BY PostId
),
TopUsers AS (
    SELECT 
        UserId, 
        SUM(Score) AS TotalScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY UserId
    ORDER BY TotalScore DESC
    LIMIT 10
),
PostHistoryChanges AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM PostHistory ph
    WHERE ph.CreationDate > NOW() - INTERVAL '6 months'
    GROUP BY ph.PostId, ph.PostHistoryTypeId
),
UserActivity AS (
    SELECT 
        UserId,
        COUNT(DISTINCT CreationDate) AS ActiveDays
    FROM Posts
    WHERE CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY UserId
)
SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.Tags,
    rp.VoteCount,
    ptc.TagCount,
    u.DisplayName AS UserName,
    tu.TotalScore,
    phc.ChangeCount,
    ua.ActiveDays
FROM RecentPosts rp
LEFT JOIN PostTagCounts ptc ON rp.Id = ptc.PostId
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN PostHistoryChanges phc ON rp.Id = phc.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
ORDER BY rp.CreationDate DESC, rp.Score DESC LIMIT 100;
