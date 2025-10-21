-- {"query": "14053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 934}
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.AnswerCount, 
         CAST(ROUND(DATEDIFF(p.LastActivityDate, p.CreationDate) / 365.0, 2) AS DECIMAL(5,2)) AS age_in_years,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS post_status,
         COALESCE(NULLIF(LENGTH(p.Tags), 0), 0) AS num_tags,
         CASE 
           WHEN p.AnswerCount = 0 THEN 'Unanswered'
           WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
           ELSE 'Partially Answered'
         END AS answer_status,
         CASE 
           WHEN p.OwnerUserId IS NULL THEN 'Community'
           ELSE CAST(u.Reputation AS CHAR) 
         END AS owner_reputation,
         CASE 
           WHEN p.OwnerUserId IS NULL THEN 'Community'
           ELSE u.DisplayName
         END AS owner_name,
         CASE
           WHEN p.OwnerUserId IS NULL THEN -1
           ELSE p.OwnerUserId
         END AS owner_id,
         DATEDIFF(CURDATE(), p.CreationDate) AS days_since_creation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT
  cte.Id,
  cte.PostTypeId,
  cte.CreationDate,
  cte.age_in_years,
  cte.post_status,
  cte.num_tags,
  cte.answer_status,
  cte.owner_reputation,
  cte.owner_name,
  cte.owner_id,
  cte.days_since_creation,
  CASE 
    WHEN cte.post_status = 'Closed' THEN (
      SELECT CloseReasonTypes.Name
      FROM PostHistory ph
      JOIN CloseReasonTypes ON ph.Comment = CAST(CloseReasonTypes.Id AS VARCHAR)
      WHERE ph.PostId = cte.Id AND ph.PostHistoryTypeId = 10
      ORDER BY ph.CreationDate DESC
      LIMIT 1
    )
    ELSE NULL
  END AS close_reason,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = cte.Id AND v.VoteTypeId = 2
  ) AS upvotes,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = cte.Id AND v.VoteTypeId = 3
  ) AS downvotes,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = cte.Id AND v.VoteTypeId = 5
  ) AS favorites,
  (
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.PostId = cte.Id
  ) AS comment_count,
  (
    SELECT COUNT(*)
    FROM PostLinks pl
    WHERE pl.PostId = cte.Id AND pl.LinkTypeId = 3
  ) AS num_duplicate_links,
  COALESCE((
    SELECT STRING_AGG(CAST(t.TagName AS VARCHAR), ',')
    FROM Tags t
    WHERE FIND_IN_SET(CAST(t.Id AS VARCHAR), SUBSTRING(cte.Tags, 2, LENGTH(cte.Tags) - 2))
  ), '') AS tag_list
FROM cte
ORDER BY cte.days_since_creation DESC;
