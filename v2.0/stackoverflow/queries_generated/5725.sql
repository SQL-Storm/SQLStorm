-- {"query": "5725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 694} 
WITH RecentActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.DeletionDate IS NULL
),
AuthorStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts t WHERE t.OwnerUserId = u.Id) AS PostCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
),
TagPopularity AS (
  SELECT
    t.TagName,
    SUM(p.ViewCount) AS TotalViewsForTag,
    AVG(p.Score) AS AvgPostScore,
    COUNT(*) AS QuestionCount
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(p.Tags, ',') ) AS tag
    ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
Combined AS (
  SELECT
    q.PostId,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionDate,
    q.ViewCount,
    q.Score,
    a.UserId AS AuthorId,
    a.DisplayName AS AuthorName,
    a.Reputation,
    q.Tags,
    q.LastActivityDate,
    -- correlate with author stats
    asv.PostCount,
    asv.BadgeCount,
    -- compute a derived metric from complex expression
    (q.ViewCount * 1.0 / NULLIF(q.Score, 0)) AS ViewsPerScore,
    -- window function example: rank questions by activity recency
    ROW_NUMBER() OVER (PARTITION BY a.Id ORDER BY q.LastActivityDate DESC) AS RecencyRank
  FROM RecentActiveQuestions q
  LEFT JOIN AuthorStats a ON a.UserId = q.OwnerUserId
  LEFT JOIN AuthorStats asv ON asv.UserId = q.OwnerUserId
)
SELECT
  c.PostId,
  c.QuestionTitle,
  c.QuestionDate,
  c.ViewCount,
  c.Score,
  c.AuthorName,
  c.Tags,
  c.LastActivityDate,
  c.ViewsPerScore,
  c.RecencyRank,
  c.AvgPostScore
FROM Combined c
LEFT JOIN (
  SELECT
    t.TagName,
    AVG(p.Score) AS AvgScoreForTag
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(p.Tags, ',') ) AS tag
    ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
) AS tstats ON tstats.TagName = (SELECT unnest(string_to_array(c.Tags, ',') ) FROM Combined c WHERE c.PostId = c.PostId LIMIT 1)
WHERE c.RecencyRank = 1
ORDER BY c.QuestionDate DESC
LIMIT 100;