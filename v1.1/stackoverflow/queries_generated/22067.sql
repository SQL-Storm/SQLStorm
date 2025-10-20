-- {"query": "22067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 999} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.ClosedDate,
        COALESCE(p.Title, '') AS Title,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS UNBOUNDED PRECEDING) AS CumulativeScore,
        CASE WHEN p.Tags IS NOT NULL THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) ELSE 0 END AS TagCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND EXISTS (
          SELECT 1 
          FROM Votes v 
          WHERE v.PostId = p.Id 
            AND v.VoteTypeId IN (2, 3, 5, 8) 
            AND v.UserId IS NOT NULL
      )
),
TopUsers AS (
    SELECT * 
    FROM UserBadgeCounts 
    WHERE Reputation > 1000 
    ORDER BY Reputation DESC 
    LIMIT 100
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalBadges,
        ps.PostId,
        ps.Score,
        ps.BodyLength,
        ps.PostRank,
        ps.CumulativeScore,
        CASE 
            WHEN ps.ClosedDate IS NOT NULL THEN 'Closed' 
            ELSE 'Open' 
        END AS PostStatus,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = ps.PostId 
           AND c.Score > 0 
           AND c.UserId <> tu.UserId) AS HighScoreComments
    FROM TopUsers tu
    FULL OUTER JOIN PostStats ps ON tu.UserId = ps.OwnerUserId
    WHERE ps.Score > 10 OR ps.Score IS NULL
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.TotalBadges,
    AVG(COALESCE(cd.Score, 0)) AS AvgPostScore,
    SUM(COALESCE(cd.BodyLength, 0)) AS TotalBodyLength,
    STRING_AGG(COALESCE(cd.PostStatus, 'No Posts'), '; ') AS PostStatuses,
    RANK() OVER (ORDER BY cd.CumulativeScore DESC NULLS LAST) AS UserRankByScore,
    CASE 
        WHEN cd.HighScoreComments > 5 THEN 'Active Discussion' 
        WHEN cd.HighScoreComments IS NULL THEN 'No Comments' 
        ELSE 'Moderate Discussion' 
    END AS DiscussionLevel,
    (SELECT STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') 
     FROM Posts p 
     WHERE p.Id = cd.PostId 
       AND p.Tags IS NOT NULL 
     ORDER BY LENGTH(p.Tags) DESC 
     LIMIT 1) AS TopTags
FROM CombinedData cd
GROUP BY cd.UserId, cd.DisplayName, cd.Reputation, cd.TotalBadges, cd.CumulativeScore, cd.HighScoreComments, cd.PostId
HAVING COUNT(DISTINCT CASE WHEN cd.PostRank <= 5 THEN cd.PostId END) > 0
UNION ALL
SELECT 
    NULL AS UserId,
    'Anonymous' AS DisplayName,
    0 AS Reputation,
    0 AS TotalBadges,
    NULL AS AvgPostScore,
    NULL AS TotalBodyLength,
    'No Data' AS PostStatuses,
    NULL AS UserRankByScore,
    'No Discussion' AS DiscussionLevel,
    NULL AS TopTags
FROM (
    SELECT 1 AS Dummy
    WHERE NOT EXISTS (
        SELECT 1 
        FROM UserBadgeCounts ubc 
        WHERE ubc.Reputation < 100
    )
) sub
ORDER BY UserRankByScore NULLS LAST, Reputation DESC;