-- {"query": "287.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5915} 
WITH
TagLive AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.LastActivityDate,
         p.Score,
         p.OwnerUserId,
         t.TagName
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
),
TopPerTag AS (
  SELECT TagName,
         PostId,
         Title,
         OwnerUserId,
         CreationDate,
         LastActivityDate,
         Score,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY Score DESC, LastActivityDate DESC) AS rn
  FROM TagLive
),
RecentAll AS (
  SELECT p.Id AS PostId,
         p.Title,
         'AllTags' AS TagName,
         p.CreationDate,
         p.LastActivityDate,
         p.Score,
         p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
)
SELECT *
FROM (
  SELECT tt.TagName,
         tt.PostId,
         tt.Title,
         u.DisplayName AS OwnerName,
         u.Reputation,
         tt.CreationDate,
         tt.LastActivityDate,
         tt.Score
  FROM TopPerTag tt
  JOIN Users u ON u.Id = tt.OwnerUserId
  WHERE tt.rn = 1
  UNION ALL
  SELECT ta.TagName,
         ta.PostId,
         ta.Title,
         u.DisplayName AS OwnerName,
         u.Reputation,
         ta.CreationDate,
         ta.LastActivityDate,
         ta.Score
  FROM RecentAll ta
  JOIN Users u ON u.Id = ta.OwnerUserId
) AS combined
ORDER BY TagName, LastActivityDate DESC
LIMIT 200;