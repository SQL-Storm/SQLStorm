-- {"query": "5202.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 601} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore
  FROM Posts p
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName)
  ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
    SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativePosts,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexBench AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.CreationDate AS PostDate,
    rh.OwnerUserId,
    va.DisplayName AS OwnerName,
    va.Reputation,
    va.PostCount,
    va.PositivePosts,
    va.NegativePosts,
    va.LastActive,
    tt.TagName,
    tt.TagCount,
    tt.AvgScore,
    ROW_NUMBER() OVER (ORDER BY rh.LastActivityDate DESC, va.Reputation DESC NULLS LAST) AS seq
  FROM RecentHot rh
  LEFT JOIN UserActivity va ON rh.OwnerUserId = va.UserId
  LEFT JOIN LATERAL (
    SELECT t.TagName, t.TagCount, t.AvgScore
    FROM TagPopularity t
    ORDER BY t.TagCount DESC
    LIMIT 3
  ) tt ON TRUE
)
SELECT
  cb.seq,
  cb.PostId,
  cb.Title,
  cb.Tags,
  cb.PostDate,
  cb.OwnerName,
  cb.Reputation,
  cb.PostCount,
  cb.PositivePosts,
  cb.NegativePosts,
  cb.LastActive,
  cb.TagName AS TopTag,
  cb.TagCount AS TopTagCount,
  cb.AvgScore AS TopTagAvgScore
FROM ComplexBench cb
ORDER BY cb.seq
LIMIT 100;