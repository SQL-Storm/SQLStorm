WITH TopUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighScorePosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.CreationDate,
           (p.Score + COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) AS EffectiveScore
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes vt
        WHERE vt.PostId = p.Id
    ) AS v ON TRUE
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
      AND p.Score > 10
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.BadgeCount,
        hp.PostId,
        hp.CreationDate,
        hp.EffectiveScore,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY hp.EffectiveScore DESC) AS Rank
    FROM TopUsers tu
    JOIN HighScorePosts hp ON tu.UserId = hp.OwnerUserId
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.BadgeCount,
    STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS AssociatedTags,
    SUM(cd.EffectiveScore) AS TotalEffectiveScore
FROM CombinedData cd
LEFT JOIN (
    SELECT
        p.Id AS PostId,
        TRIM(REGEXP_REPLACE(p.Tags, '<|>', '', 'g')) AS TagName
    FROM Posts p
) AS t ON cd.PostId = t.PostId
WHERE cd.Rank <= 5
GROUP BY cd.UserId, cd.DisplayName, cd.BadgeCount
HAVING COUNT(t.TagName) > 0;