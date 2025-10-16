-- {"query": "14004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 11675, "output_tokens": 5062} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Body, 
    p.OwnerUserId, 
    u.DisplayName AS OwnerDisplayName,
    p.LastEditorUserId,
    u2.DisplayName AS LastEditorDisplayName,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerRank,
    RANK() OVER (PARTITION BY p.LastEditorUserId ORDER BY p.LastEditDate DESC) AS LastEditorRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
),
summary AS (
  SELECT 
    OwnerUserId,
    OwnerDisplayName,
    LastEditorUserId,
    LastEditorDisplayName,
    COUNT(*) AS TotalPosts,
    SUM(CASE WHEN OwnerRank = 1 THEN 1 ELSE 0 END) AS TopPosts,
    SUM(CASE WHEN LastEditorRank = 1 THEN 1 ELSE 0 END) AS RecentlyEditedTopPosts,
    ROUND(AVG(LENGTH(Body)), 2) AS AvgBodyLength,
    ROUND(AVG(CHAR_LENGTH(REPLACE(Title, ' ', ''))), 2) AS AvgTitleLength,
    STRING_AGG(REPLACE(Tags, '<', ''), '><') AS TopTags
  FROM cte
  GROUP BY OwnerUserId, OwnerDisplayName, LastEditorUserId, LastEditorDisplayName
),
user_stats AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    s.TotalPosts,
    s.TopPosts,
    s.RecentlyEditedTopPosts,
    s.AvgBodyLength,
    s.AvgTitleLength,
    s.TopTags
  FROM Users u
  LEFT JOIN summary s ON u.Id = s.OwnerUserId
)
SELECT
  u.*,
  ROUND(CAST(u.UpVotes AS FLOAT) / NULLIF(u.Views, 0), 2) AS UpVoteRatio,
  ROUND(CAST(u.DownVotes AS FLOAT) / NULLIF(u.Views, 0), 2) AS DownVoteRatio,
  ROUND(CAST(u.UpVotes AS FLOAT) / NULLIF(u.DownVotes, 0), 2) AS VoteRatio,
  CASE 
    WHEN u.Reputation >= 10000 THEN 'Gold'
    WHEN u.Reputation >= 2000 THEN 'Silver'
    ELSE 'Bronze'
  END AS ReputationRank,
  CASE
    WHEN u.TopPosts >= 10 THEN 'Expert'
    WHEN u.TopPosts >= 5 THEN 'Proficient'
    ELSE 'Novice'
  END AS ContentContributionRank,
  CASE
    WHEN u.RecentlyEditedTopPosts >= 5 THEN 'Prolific Editor'
    WHEN u.RecentlyEditedTopPosts >= 2 THEN 'Frequent Editor'
    ELSE 'Occasional Editor'
  END AS EditingRank
FROM user_stats u
ORDER BY u.Reputation DESC;