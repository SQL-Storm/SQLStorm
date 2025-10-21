-- {"query": "28032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1341} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        AVG(p.Score) OVER (PARTITION BY u.Location) AS AvgLocationScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.Location
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.Tags,
        COALESCE(NULLIF(p.ClosedDate, '1970-01-01'), CURRENT_TIMESTAMP) AS EffectiveClosedDate,
        STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><') AS TagArray,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes
    FROM Posts p
    WHERE p.PostTypeId = 1
),
CombinedData AS (
    SELECT 
        us.Id AS UserId,
        us.Reputation,
        us.GoldBadges,
        pa.Score AS PostScore,
        pa.Upvotes,
        pa.TagArray[1] AS PrimaryTag,
        CASE 
            WHEN us.Reputation > 100000 THEN 'Legendary'
            WHEN us.GoldBadges > 10 AND us.TotalPosts > 100 THEN 'PowerUser'
            ELSE 'Regular'
        END AS UserClass,
        ROUND(EXTRACT(EPOCH FROM (pa.EffectiveClosedDate - p.CreationDate)) / 86400, 2) AS DaysOpen,
        DENSE_RANK() OVER (PARTITION BY us.Location ORDER BY us.Reputation DESC) AS LocationRank
    FROM UserStats us
    LEFT JOIN PostAnalysis pa ON us.Id = pa.OwnerUserId
    LEFT JOIN Posts p ON pa.Id = p.Id
    WHERE us.Location IS NOT NULL
      AND pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
)
SELECT 
    cd.UserId,
    cd.UserClass,
    cd.PrimaryTag,
    SUM(cd.Upvotes) OVER (PARTITION BY cd.PrimaryTag ORDER BY cd.PostScore DESC) AS CumulativeUpvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = cd.UserId AND c.CreationDate BETWEEN '2022-01-01' AND '2023-01-01') AS AnnualComments,
    COALESCE((SELECT STRING_AGG(ph.Text, ' | ') 
              FROM PostHistory ph 
              WHERE ph.PostId = cd.UserId 
                AND ph.PostHistoryTypeId IN (2,5) 
              LIMIT 3), 'No Edits') AS RecentEdits
FROM CombinedData cd
WHERE cd.DaysOpen < (SELECT AVG(DaysOpen) FROM CombinedData WHERE UserClass = cd.UserClass)
UNION ALL
SELECT 
    u.Id AS UserId,
    'Inactive' AS UserClass,
    NULL AS PrimaryTag,
    0 AS CumulativeUpvotes,
    0 AS AnnualComments,
    'No Activity' AS RecentEdits
FROM Users u
WHERE u.Id NOT IN (SELECT UserId FROM CombinedData)
ORDER BY CumulativeUpvotes DESC, LocationRank;
