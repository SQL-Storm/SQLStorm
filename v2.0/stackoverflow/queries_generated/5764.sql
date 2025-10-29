-- {"query": "5764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 655} 
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    AVG(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600.0) AS HoursActive,
    ROW_NUMBER() OVER (PARTITION BY DATE(p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY p.Id, u.DisplayName
),
CorrelatedTagStats AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.UpVotes,
    r.DownVotes,
    r.HoursActive,
    t.TagName,
    t.Count AS TagCount,
    u.Reputation,
    u.LastAccessDate
  FROM RecentPopularQuestions r
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  LEFT JOIN Tags tg ON tg.TagName = t.TagName
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
),
ComputedMetrics AS (
  SELECT
    QuestionId,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    OwnerUserId,
    OwnerDisplayName,
    UpVotes,
    DownVotes,
    HoursActive,
    TagName,
    TagCount,
    Reputation,
    LastAccessDate,
    CASE
      WHEN UpVotes > 0 THEN UpVotes * 1.0 / NULLIF(DownVotes + 1, 0)
      ELSE NULL
    END AS UpDownRatio,
    (Score + TagCount) AS ScoreWithTags
  FROM CorrelatedTagStats
)
SELECT
  QuestionId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerDisplayName,
  Reputation,
  LastAccessDate,
  TagName,
  TagCount,
  UpVotes,
  DownVotes,
  HoursActive,
  UpDownRatio,
  ScoreWithTags
FROM ComputedMetrics
WHERE
  OwnerUserId IS NOT NULL
  AND LastAccessDate IS NOT NULL
  AND HoursActive IS NOT NULL
  AND TagName IS NOT NULL
ORDER BY ScoreWithTags DESC NULLS LAST
LIMIT 100;