-- {"query": "316.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19273} 
WITH UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COALESCE(p.TotalPosts, 0) AS TotalPosts,
    COALESCE(c.TotalComments, 0) AS TotalComments,
    COALESCE(v.TotalUpVotes, 0) AS TotalUpVotes,
    COALESCE(v.TotalDownVotes, 0) AS TotalDownVotes,
    COALESCE(b.TotalBadges, 0) AS TotalBadges,
    (COALESCE(p.TotalPosts, 0) * 5
     + COALESCE(c.TotalComments, 0) * 2
     + COALESCE(v.TotalUpVotes, 0)
     - COALESCE(v.TotalDownVotes, 0)
     + COALESCE(b.TotalBadges, 0) * 3) AS Engagement
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS TotalPosts
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
  ) p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalComments
    FROM Comments
    GROUP BY UserId
  ) c ON c.UserId = u.Id
  LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
)
SELECT
  US.UserId,
  US.DisplayName,
  US.Reputation,
  US.Location,
  US.Engagement,
  US.TotalPosts,
  US.TotalComments,
  US.TotalUpVotes,
  US.TotalDownVotes,
  US.TotalBadges,
  MAX(CASE WHEN PR.rn = 1 THEN PR.Title END) AS Top1_Title,
  MAX(CASE WHEN PR.rn = 1 THEN PR.Score END) AS Top1_Score,
  (SELECT TOP (1) p.Title + ' (' + CAST(p.Score AS varchar(10)) + ')'
   FROM Posts p
   WHERE p.OwnerUserId = US.UserId
   ORDER BY p.LastActivityDate DESC) AS LastActivePostSummary,
  CONCAT('Engagement=', CAST(US.Engagement AS varchar(20)),
         ', Posts=', CAST(US.TotalPosts AS varchar(10)),
         ', Badges=', CAST(US.TotalBadges AS varchar(10))) AS EngagementSummary,
  CASE
     WHEN (US.TotalUpVotes + US.TotalDownVotes) > 0
     THEN CAST(US.TotalUpVotes * 100.0 / (US.TotalUpVotes + US.TotalDownVotes) AS decimal(5,2))
     ELSE NULL
  END AS UpvoteSharePercent,
  DENSE_RANK() OVER (ORDER BY US.Engagement DESC) AS EngagementRank
FROM UserStats US
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
) PR ON PR.UserId = US.UserId
GROUP BY
  US.UserId, US.DisplayName, US.Reputation, US.Location, US.Engagement,
  US.TotalPosts, US.TotalComments, US.TotalUpVotes, US.TotalDownVotes, US.TotalBadges
ORDER BY US.Engagement DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;