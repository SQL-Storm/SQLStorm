-- {"query": "15059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 140100, "output_tokens": 41066} 
WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        p.PostTypeId,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecentActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100 AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, p.PostTypeId
),
TagPopularity AS (
    SELECT 
        UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagFrequency,
        AVG(Score) AS AvgTagScore
    FROM Posts
    WHERE Tags IS NOT NULL
    GROUP BY TagName
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    tp.TagName,
    upa.PostCount,
    upa.AvgPostScore,
    tp.TagFrequency,
    tp.AvgTagScore,
    CASE 
        WHEN upa.MaxViewCount > 10000 THEN 'High Impact'
        WHEN upa.MaxViewCount BETWEEN 1000 AND 10000 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = upa.UserId AND v.VoteTypeId IN (2, 3)
        ), 0
    ) AS TotalVotes
FROM UserPostActivity upa
JOIN TagPopularity tp ON EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = upa.UserId 
    AND POSITION(tp.TagName IN p.Tags) > 0
)
WHERE upa.RecentActivityRank = 1 
  AND upa.AvgPostScore > (
      SELECT AVG(Score) 
      FROM Posts 
      WHERE PostTypeId = upa.PostTypeId
  )
ORDER BY upa.PostCount * tp.TagFrequency DESC
LIMIT 100;