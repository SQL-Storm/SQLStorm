-- {"query": "15087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 205480, "output_tokens": 60382} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY AVG(p.Score) DESC) AS TagScoreRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN Tags t ON t.Id IN (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))
    WHERE p.PostTypeId = 1 AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
),
CloseAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        ph.CreationDate AS ClosedDate,
        ct.Name AS CloseReason,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph2 
             WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (10, 11)),
            0
        ) AS CloseReopenCycles
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes ct ON CAST(ph.Comment AS smallint) = ct.Id
)
SELECT 
    uts.UserId,
    uts.DisplayName,
    uts.TagName,
    uts.PostCount,
    uts.AvgTagScore,
    ca.PostId,
    ca.Title,
    ca.ClosedDate,
    ca.CloseReason,
    ca.CloseReopenCycles,
    CASE 
        WHEN uts.TagRank <= 3 AND uts.TagScoreRank <= 5 THEN 'Top Contributor'
        WHEN ca.CloseReopenCycles > 2 THEN 'Controversial Content'
        ELSE 'Standard User'
    END AS UserCategory,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId IN (2, 3)) AS TotalVotes,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2) / 
        NULLIF((SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId IN (2, 3)), 0),
        2
    ) AS UpvotePercentage
FROM UserTagStats uts
FULL OUTER JOIN CloseAnalysis ca ON 1=1
WHERE 
    uts.PostCount > 10 
    AND (ca.CloseReopenCycles > 0 OR uts.AvgTagScore > 5)
ORDER BY uts.PostCount DESC, uts.AvgTagScore DESC
LIMIT 100;