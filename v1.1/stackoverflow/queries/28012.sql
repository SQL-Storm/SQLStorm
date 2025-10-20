-- {"query": "28012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 3737} 
WITH BadgeSummary AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges
    GROUP BY UserId
), PostActivity AS (
    SELECT p.OwnerUserId,
           COUNT(*) AS TotalPosts,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
           MAX(p.CreationDate) AS LastActivity,
           STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags) - 2), ', ') AS CommonTags
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
), VoteAnalysis AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS Bounties
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id AND p.PostTypeId = 1
    GROUP BY v.UserId
), RankedUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           COALESCE(u.Location, 'Unknown') AS Location,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
           NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile
    FROM Users u
)
SELECT ru.*,
       bs.Gold,
       bs.Silver,
       bs.Bronze,
       pa.TotalPosts,
       pa.AvgQuestionScore,
       pa.CommonTags,
       va.Upvotes,
       va.Downvotes,
       va.Bounties,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ru.Id) AS TotalComments,
       (SELECT COUNT(*) FROM PostHistory ph
        WHERE ph.UserId = ru.Id AND ph.PostHistoryTypeId IN (2,5,8)
        AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-01-01') AS EditsLast3Years,
       CASE WHEN EXISTS (
           SELECT 1 FROM Posts p
           WHERE p.OwnerUserId = ru.Id
           AND p.PostTypeId = 1
           AND p.ClosedDate IS NOT NULL
           AND p.Score > 50
       ) THEN 1 ELSE 0 END AS HasPopularClosedQuestion
FROM RankedUsers ru
LEFT JOIN BadgeSummary bs ON ru.Id = bs.UserId
LEFT JOIN PostActivity pa ON ru.Id = pa.OwnerUserId
LEFT JOIN VoteAnalysis va ON ru.Id = va.UserId
WHERE ru.ReputationQuartile = 1
  AND ru.LocationRank = 1
  AND (va.Bounties > 0 OR pa.AvgQuestionScore > 20)
  AND ru.CreationDate < '2022-01-01'
ORDER BY 
  CASE WHEN ru.Location = 'Unknown' THEN 1 ELSE 0 END,
  ru.Reputation DESC,
  va.Upvotes DESC
LIMIT 100;