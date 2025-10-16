-- {"query": "15077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 182130, "output_tokens": 53565} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t ON 1=1
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
QuestionComplexity AS (
    SELECT 
        p.Id,
        p.Title,
        LENGTH(p.Body) AS BodyLength,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) / 2 + 1 AS TagCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    uts.UserId,
    uts.DisplayName,
    uts.TagName,
    uts.PostCount,
    uts.AvgTagScore,
    qc.BodyLength,
    qc.CommentCount,
    qc.TagCount,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uts.UserId AND v.VoteTypeId = 2),
        0
    ) AS UpVotes,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uts.UserId AND b.Class = 1),
        0
    ) AS GoldBadgeCount,
    CASE 
        WHEN uts.AvgTagScore > 10 AND uts.PostCount > 50 THEN 'Top Contributor'
        WHEN uts.AvgTagScore > 5 AND uts.PostCount > 20 THEN 'Active Contributor'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserTagStats uts
JOIN QuestionComplexity qc ON 1=1
WHERE 
    uts.TagRank <= 10 
    AND qc.BodyLength > 500 
    AND qc.TagCount > 2
    AND (qc.IsClosed = 0 OR RANDOM() < 0.5)
ORDER BY 
    uts.PostCount * uts.AvgTagScore DESC
LIMIT 100;