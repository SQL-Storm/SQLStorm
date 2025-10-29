-- {"query": "5828.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 629} 
WITH prolific_posters AS (
  SELECT
    p.OwnerUserId,
    u.DisplayName,
    COUNT(*) AS post_count,
    SUM(p.ViewCount) AS total_views,
    AVG(p.Score) AS avg_score,
    MAX(p.LastActivityDate) AS most_recent_activity
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- questions and answers
    AND p.CreationDate >= DATEADD(year, -2, GETDATE())
  GROUP BY p.OwnerUserId, u.DisplayName
),
recent_closed AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    pc.Name AS CloseReason,
    vh.CreationDate AS CloseVoteDate,
    v.UserId AS VoterId
  FROM Posts p
  LEFT JOIN PostHistory vh ON vh.PostId = p.Id
  LEFT JOIN PostHistoryTypes pht ON pht.Id = vh.PostHistoryTypeId
  LEFT JOIN CloseReasonTypes pc ON pc.Id = CAST(JSON_VALUE(vh.Text, '$.CloseReasonId') AS int)
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 6
  WHERE p.ClosedDate IS NOT NULL
),
complex_expression AS (
  SELECT
    LTRIM(RTRIM(p.Title)) AS clean_title,
    p.Id,
    p.Tags,
    CASE
      WHEN p.ViewCount > 1000 THEN 'hot'
      WHEN p.ViewCount BETWEEN 100 AND 1000 THEN 'warm'
      ELSE 'cool'
    END AS heat_segment,
    CASE
      WHEN p.Score >= 10 THEN 'high_score'
      WHEN p.Score >= 0 THEN 'neutral'
      ELSE 'low_score'
    END AS score_tier,
    LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<', '')) AS angle_brackets_in_body
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  -- metrics from prolific posters
  up.OwnerUserId,
  up.DisplayName AS poster_display,
  up.post_count,
  up.total_views,
  up.avg_score,
  up.most_recent_activity,

  -- detailed closed post info
  rcl.PostId,
  rcl.Title AS closed_post_title,
  rcl.CloseReason,
  rcl.CloseVoteDate,
  rcl.VoterId,

  -- complex expression features
  ce.clean_title,
  ce.Tags,
  ce.heat_segment,
  ce.score_tier,
  ce.angle_brackets_in_body

FROM prolific_posters up
LEFT JOIN recent_closed rcl
  ON rcl.OwnerUserId = up.OwnerUserId
LEFT JOIN complex_expression ce
  ON ce.Id = rcl.PostId
ORDER BY up.total_views DESC, up.post_count DESC
LIMIT 100;