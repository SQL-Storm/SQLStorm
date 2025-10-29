-- {"query": "5560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 748} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.CreationDate) AS LatestQuestion
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
complex_metrics AS (
  SELECT
    qq.PostId,
    qq.Title,
    qq.OwnerUserId,
    qq.CreationDate,
    qq.LastActivityDate,
    COALESCE(vs.TotalUp, 0) AS UpVotes,
    COALESCE(vs.TotalDown, 0) AS DownVotes,
    CASE
      WHEN qq.ViewCount > 1000 THEN TRUE
      ELSE FALSE
    END AS HighlyViewed,
    CASE
      WHEN qq.Score >= 5 THEN 'high'
      WHEN qq.Score BETWEEN -5 AND 4 THEN 'medium'
      ELSE 'low'
    END AS ScoreBand,
    ROW_NUMBER() OVER (PARTITION BY qq.OwnerUserId ORDER BY qq.LastActivityDate DESC) AS rn
  FROM recent_questions qq
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = qq.PostId
  LEFT JOIN Comments c ON c.PostId = qq.PostId
  LEFT JOIN Badges b ON b.UserId = qq.OwnerUserId
),
correlated_subquery AS (
  SELECT
    cm.*,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = cm.OwnerUserId AND p2.CreationDate > cm.CreationDate) AS LaterPostsByOwner
  FROM complex_metrics cm
  WHERE cm.rn = 1
)
SELECT
  cs.PostId,
  cs.Title,
  u.DisplayName AS OwnerDisplayName,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.UpVotes,
  cs.DownVotes,
  cs.HighlyViewed,
  cs.ScoreBand,
  (cs.ViewsAggregate / NULLIF(cs.QuestionCount, 0))::numeric(18,4) AS NormalizedViewsPerQuestion
FROM correlated_subquery cs
JOIN Users u ON u.Id = cs.OwnerUserId
LEFT JOIN (
  SELECT
    OwnerUserId,
    MAX(ViewCount) AS ViewsAggregate,
    SUM(Score) AS SumScores,
    COUNT(*) AS QuestionCount
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY OwnerUserId
) v ON v.OwnerUserId = cs.OwnerUserId
WHERE cs.rn = 1
ORDER BY cs.LastActivityDate DESC
LIMIT 100;