WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId IN (1, 2) AND p.Score > 0
),
TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 100
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS HistoryCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (3, 5, 6)
    GROUP BY 
        ph.PostId
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore
    FROM 
        Tags t
    JOIN 
        Posts p ON t.WikiPostId = p.Id
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT ph.PostId) AS EditCount,
        COUNT(DISTINCT v.PostId) AS VoteCount
    FROM 
        Users u
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    WHERE 
        (ph.PostHistoryTypeId IN (3, 5, 6)) OR (v.VoteTypeId IN (2, 3))
    GROUP BY 
        u.Id, u.DisplayName
),
PostTags AS (
    SELECT
        p.Id AS PostId,
        TRIM(tag) AS Tag
    FROM
        Posts p,
        LATERAL (
            SELECT TRIM(value) AS tag
            FROM (
                SELECT
                    CAST(value AS VARCHAR(4000)) AS value
                FROM
                    (SELECT REPLACE(REPLACE(COALESCE(p.Tags, ''), '<', ' '), '>', ' ') AS tags_text) t,
                    LATERAL (
                        SELECT
                            REGEXP_SPLIT_TO_TABLE(t.tags_text, '\s+') AS value
                    ) s
            ) x
        ) lt
),
PostTagAgg AS (
    SELECT
        pt.PostId,
        STRING_AGG(pt.Tag, ' ') AS AllTags
    FROM
        PostTags pt
    GROUP BY
        pt.PostId
)
SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.OwnerDisplayName,
    rp.PostRank,
    tu.DisplayName AS TopUser,
    tu.Reputation,
    tu.BadgeCount,
    tu.UserRank,
    phs.HistoryCount,
    phs.LastEditDate,
    ts.TagName,
    ts.PostCount,
    ts.AvgScore,
    ua.EditCount,
    ua.VoteCount
FROM 
    RankedPosts rp
JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.Id
JOIN 
    PostHistorySummary phs ON rp.Id = phs.PostId
-- join to TagStats kept as cross join on condition in WHERE; remove invalid placeholder join
JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.Id
LEFT JOIN
    PostTagAgg pta ON rp.Id = pta.PostId
LEFT JOIN
    TagStats ts ON POSITION(ts.TagName IN COALESCE(pta.AllTags, '')) > 0
WHERE 
    rp.PostRank <= 10
    AND EXISTS (
        SELECT 1
        FROM TagStats t2
        WHERE
            rp.PostTypeId = 1
            AND POSITION(t2.TagName IN COALESCE(pta.AllTags, '')) > 0
    )
ORDER BY 
    rp.PostRank, tu.UserRank;