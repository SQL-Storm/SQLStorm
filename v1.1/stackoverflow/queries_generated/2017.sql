-- {"query": "2017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 597} 

WITH RecursiveTagHierarchy AS (
    SELECT
        p.Id AS PostId,
        p.Title AS PostTitle,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagList
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
),
RankedUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        RANK() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM
        Users u
),
PostPerformanceMetrics AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        COUNT(ph.Id) AS EditCount,
        PR.Reputation AS RecentEditorReputation
    FROM
        PostHistory ph
    LEFT OUTER JOIN Users PR ON ph.UserId = PR.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Only edits
        AND ph.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY
        ph.PostId,
        ph.CreationDate,
        PR.Reputation
),
CombinedQuery AS (
    SELECT
        p.Id,
        p.Title,
        r.UserId AS EditorUserId,
        r.DisplayName AS EditorDisplayName,
        r.UserRank,
        (SELECT COUNT(DISTINCT bl.UserId)
        FROM Badges bl
        WHERE bl.UserId = r.UserId) AS BadgeCount,
        COALESCE(pm.EditCount, 0) AS TotalEdits,
        LEAST(pm.RecentEditorReputation, u.Reputation) AS NotableReputation
    FROM
        Posts p
    JOIN RankedUsers r ON p.OwnerUserId = r.UserId
    JOIN PostPerformanceMetrics pm ON p.Id = pm.PostId
    LEFT JOIN Users u ON u.Id = r.UserId
    WHERE
        p.PostTypeId = 2
        AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
)
SELECT
    cq.Id AS PostId,
    cq.Title AS AnswerTitle,
    cq.EditorUserId,
    cq.EditorDisplayName,
    cq.UserRank,
    cq.BadgeCount,
    cq.TotalEdits,
    cq.NotableReputation
FROM
    CombinedQuery cq
JOIN Posts p ON p.Id = cq.Id
LEFT JOIN Votes vt ON vt.PostId = p.Id AND vt.VoteTypeId = 2 -- Only upvotes
WHERE
    p.Score > 0 
    AND (cq.BadgeCount > 2 OR vt.Id IS NULL)
AND EXISTS (
    SELECT 1
    FROM Comments c
    WHERE c.PostId = p.Id
    HAVING COUNT(c.Id) > 5
)
ORDER BY
    cq.NotableReputation DESC,
    cq.TotalEdits DESC;
