-- {"query": "2011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 415} 

WITH RecentEdits AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RowNum
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (5, 6) -- Edit Body or Edit Tags
),
TopEditors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS EditedPostsCount
    FROM 
        Users u
    INNER JOIN RecentEdits re ON u.Id = re.EditorId
    INNER JOIN Posts p ON p.Id = re.PostId
    WHERE 
        re.RowNum = 1 -- Only consider the most recent edit
    GROUP BY 
        u.Id, u.DisplayName
    ORDER BY 
        EditedPostsCount DESC
    LIMIT 10
),
HighReputationUsers AS (
    SELECT 
        Id AS UserId,
        DisplayName,
        Reputation
    FROM 
        Users
    WHERE 
        Reputation > 10000
),
TagDetails AS (
    SELECT 
        TagName,
        Count,
        IsModeratorOnly
    FROM 
        Tags
    WHERE 
        IsRequired = 1
)
SELECT 
    te.DisplayName AS EditorName,
    te.EditedPostsCount,
    hru.DisplayName AS HighReputationUser,
    hru.Reputation,
    td.TagName,
    td.Count AS TagUsageCount
FROM 
    TopEditors te
LEFT JOIN HighReputationUsers hru ON te.Id = hru.UserId
CROSS JOIN TagDetails td
WHERE 
    COALESCE(hru.Reputation, 0) < 50000
  AND td.Count > 100
  AND td.Count < 1000
ORDER BY 
    te.EditedPostsCount DESC,
    hru.Reputation DESC,
    td.Count ASC;
