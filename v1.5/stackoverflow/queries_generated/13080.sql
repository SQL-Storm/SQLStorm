-- {"query": "13080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 647} 

WITH UserScores AS (
    SELECT 
        OwnerUserId,
        SUM(Score) AS TotalScore,
        COUNT(Id) AS PostCount,
        MAX(LastActivityDate) AS LastActivity
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        us.TotalScore,
        us.PostCount,
        us.LastActivity,
        ROW_NUMBER() OVER (ORDER BY us.TotalScore DESC) AS Rank
    FROM Users u
    JOIN UserScores us ON u.Id = us.OwnerUserId
    WHERE u.Reputation > 1000
),
RecentEdits AS (
    SELECT 
        PostId,
        MAX(CreationDate) AS LastEditDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
),
FinalResult AS (
    SELECT 
        tc.Id,
        tc.DisplayName,
        tc.TotalScore,
        tc.PostCount,
        tc.LastActivity,
        p.Title,
        p.Tags,
        re.LastEditDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tc.Id AND b.Class = 1) AS GoldBadges,
        CASE 
            WHEN LENGTH(COALESCE(p.Body, '')) > 500 THEN CONCAT(LEFT(p.Body, 500), '...')
            ELSE p.Body
        END AS BodySnippet
    FROM TopContributors tc
    LEFT JOIN Posts p ON tc.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN RecentEdits re ON p.Id = re.PostId
    WHERE tc.Rank <= 10 AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 year'
)
SELECT 
    f.Id,
    f.DisplayName,
    f.TotalScore,
    f.PostCount,
    f.LastActivity,
    f.Title,
    STRING_TO_ARRAY(SUBSTRING(COALESCE(f.Tags, ''), 2, LENGTH(COALESCE(f.Tags, '')) - 2), '><') AS TagArray,
    f.LastEditDate,
    f.GoldBadges,
    f.BodySnippet,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = f.Id AND v.VoteTypeId = 8) AS AvgBounty
FROM FinalResult f
ORDER BY f.TotalScore DESC, f.LastActivity DESC;
