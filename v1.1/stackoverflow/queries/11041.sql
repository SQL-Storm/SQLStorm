WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        p.Tags, 
        COUNT(v.Id) AS VoteCount,
        p.OwnerUserId
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, p.Tags, p.OwnerUserId
),
TaggedPosts AS (
    SELECT 
        p.Id AS PostId,
        TRIM(tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag
    ) t
    WHERE p.Tags IS NOT NULL
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
        p.OwnerUserId AS UserId, 
        SUM(p.Score) AS TotalScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
    ORDER BY TotalScore DESC
    LIMIT 10
),
PostHistoryChanges AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM PostHistory ph
    WHERE ph.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH
    GROUP BY ph.PostId, ph.PostHistoryTypeId
),
UserActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT DATE_TRUNC('day', p.CreationDate)) AS ActiveDays
    FROM Posts p
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
    GROUP BY p.OwnerUserId
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
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
ORDER BY rp.CreationDate DESC, rp.Score DESC
LIMIT 100;