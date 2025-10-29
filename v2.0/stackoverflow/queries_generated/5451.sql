-- {"query": "5451.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 830} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    -- derived sentiment-like metric fromVotes ratio and NULL-safe calc
    CASE WHEN (u.Views IS NULL OR u.Views = 0) THEN NULL
         ELSE (CAST(u.UpVotes AS float) - CAST(u.DownVotes AS float)) / NULLIF(CAST(u.Views AS float),0)
    END AS EngagementIndex
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
),
TaggedAgg AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Tags,
    ts.TagName,
    COUNT(*) AS TagScore
  FROM Posts p
  CROSS APPLY (
    SELECT TOP 1 value AS TagName
    FROM string_split(REPLACE(REPLACE(p.Tags, '><', '|'), '<|', ''), '|')
  ) AS ts
  WHERE p.Tags IS NOT NULL
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Tags, ts.TagName
),
WindowPosts AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.PostTypeId,
    ra.UserId,
    ra.DisplayName,
    ra.Reputation,
    ra.UserCreationDate,
    ra.LastAccessDate,
    ra.Location,
    ra.Views,
    ra.UpVotes,
    ra.DownVotes,
    ra.EngagementIndex,
    ROW_NUMBER() OVER (
      PARTITION BY ra.OwnerUserId
      ORDER BY ra.LastActivityDate DESC, ra.Score DESC
    ) AS rn_by_author
  FROM RecentActivity ra
),
Filtered AS (
  SELECT *
  FROM WindowPosts
  WHERE rn_by_author <= 5
),
Correlated AS (
  SELECT
    f.*,
    ta.TagName,
    ta.TagScore
  FROM Filtered f
  LEFT JOIN TaggedAgg ta ON f.PostId = ta.PostId
),
Final AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.PostTypeId,
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.UserCreationDate,
    c.LastAccessDate,
    c.Location,
    c.Views,
    c.UpVotes,
    c.DownVotes,
    c.EngagementIndex,
    c.TagName,
    c.TagScore
  FROM Correlated c
  WHERE c.PostTypeId = 1 -- only questions
     OR c.PostTypeId = 2 -- or answers; keep to benchmark mixed workload
)
SELECT
  PostId,
  Title,
  OwnerUserId,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  Tags,
  PostTypeId,
  UserId,
  DisplayName,
  Reputation,
  UserCreationDate,
  LastAccessDate,
  Location,
  Views,
  UpVotes,
  DownVotes,
  EngagementIndex,
  TagName,
  TagScore
FROM Final
ORDER BY LastActivityDate DESC, PostId ASC
LIMIT 100;