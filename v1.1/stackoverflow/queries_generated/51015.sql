-- {"query": "51015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 854} 

WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         COUNT(DISTINCT p.Id) as PostCount,
         AVG(p.Score) as AvgPostScore,
         COUNT(DISTINCT COALESCE(a.Id, p.Id)) as AnswerCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING u.Reputation >= 10000
),
EngagedPosts AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
         p.OwnerUserId, p.Tags,
         COUNT(v.Id) as TotalVotes,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
         COUNT(DISTINCT c.Id) as CommentCount,
         COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) as CloseVotes,
         COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) as ReopenVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id 
    AND ph.PostHistoryTypeId IN (10, 11)
  WHERE p.PostTypeId = 1 
    AND p.DeletionDate IS NULL
    AND p.ViewCount > 1000
  GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, 
           p.OwnerUserId, p.Tags
  HAVING COUNT(v.Id) > 50 OR p.Score > 10
),
TagStats AS (
  SELECT t.TagName,
         COUNT(DISTINCT ep.Id) as QuestionCount,
         AVG(ep.TotalVotes) as AvgVotes,
         SUM(ep.ViewCount) as TotalViews,
         STRING_AGG(DISTINCT tu.DisplayName, ',') as TopContributors
  FROM Tags t
  JOIN Posts ep ON ep.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN TopUsers tu ON ep.OwnerUserId = tu.Id
  WHERE t.Count > 100
  GROUP BY t.TagName
  HAVING COUNT(DISTINCT ep.Id) >= 5
)
SELECT 
  tu.DisplayName as UserName,
  tu.Reputation,
  tu.PostCount,
  tu.AvgPostScore,
  ts.TagName,
  ts.QuestionCount as TagQuestionCount,
  ts.AvgVotes as AvgTagVotes,
  ep.Title,
  ep.Score as QuestionScore,
  ep.TotalVotes,
  (ep.UpVotes - ep.DownVotes) as NetVotes,
  ep.CommentCount,
  ep.ViewCount,
  (ep.CloseVotes - ep.ReopenVotes) as NetCloseActivity,
  DENSE_RANK() OVER (
    PARTITION BY ts.TagName 
    ORDER BY ep.TotalVotes DESC, ep.ViewCount DESC
  ) as RankInTag,
  ROW_NUMBER() OVER (
    ORDER BY (ep.TotalVotes * 0.7 + ep.ViewCount * 0.3) DESC
  ) as OverallRank
FROM EngagedPosts ep
JOIN TopUsers tu ON ep.OwnerUserId = tu.Id
JOIN TagStats ts ON ep.Tags LIKE '%' || ts.TagName || '%'
LEFT JOIN Badges b ON b.UserId = tu.Id 
  AND b.TagBased = 1 
  AND b.Date > ep.CreationDate - INTERVAL '1 year'
WHERE ep.CreationDate >= NOW() - INTERVAL '2 years'
  AND ts.TotalViews > 100000
  AND (b.Id IS NOT NULL OR tu.Reputation > 50000)
ORDER BY OverallRank, ts.AvgTagVotes DESC, tu.Reputation DESC
LIMIT 100;
