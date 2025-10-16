-- {"query": "15054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 128425, "output_tokens": 38052} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalTagScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserTagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName FROM Posts) t ON 1=1
    WHERE u.Reputation > 1000 AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
CloseStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(v.Id) AS CloseVotes,
        COALESCE(crt.Name, 'Unknown') AS CloseReason,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) AS MedianCloseVoterReputation
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 6
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = crt.Id::text
    LEFT JOIN Users u ON v.UserId = u.Id
    GROUP BY p.Id, p.Title, crt.Name
)
SELECT 
    uts.UserId,
    uts.DisplayName,
    uts.TagName,
    uts.PostCount,
    uts.TotalTagScore,
    cs.Title AS MostCloseAttemptedPost,
    cs.CloseVotes,
    cs.CloseReason,
    CASE 
        WHEN uts.TagRank <= 3 AND uts.UserTagRank <= 5 THEN 'Top Contributor'
        WHEN uts.PostCount > 100 THEN 'Prolific User'
        ELSE 'Active User'
    END AS UserCategory,
    ROUND(100.0 * uts.PostCount / (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = uts.UserId), 2) AS TagPercentage,
    GREATEST(uts.TotalTagScore, 0) * LOG(uts.PostCount + 1) AS TagInfluenceScore
FROM UserTagStats uts
LEFT JOIN CloseStats cs ON uts.UserId = cs.PostId
WHERE uts.PostCount > 10 
    AND (cs.CloseVotes IS NULL OR cs.CloseVotes > 0)
ORDER BY TagInfluenceScore DESC
LIMIT 100;