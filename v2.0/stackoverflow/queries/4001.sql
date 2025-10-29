-- {"query": "4001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1161}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn,
      LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS prev_edit_date
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserEditFrequency AS (
    SELECT
      re.UserId,
      COUNT(DISTINCT re.PostId) AS distinct_posts_edited,
      COUNT(*) AS total_edits,
      AVG(EXTRACT(EPOCH FROM (re.CreationDate - re.prev_edit_date))) AS avg_time_between_edits
    FROM
      RankedPostEdits re
    WHERE
      re.rn = 1
    GROUP BY
      re.UserId
    HAVING
      COUNT(*) > 5
  ),
  PostEditMetrics AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.UserId END) AS distinct_title_editors,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.UserId END) AS distinct_body_editors,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.UserId END) AS distinct_tag_editors,
      MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS last_body_edit_date,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS total_body_edits,
      MAX(p.LastEditDate) AS post_last_edit_date
    FROM
      Posts p
    LEFT JOIN
      PostHistory ph ON p.Id = ph.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate
  )
SELECT
  u.DisplayName AS EditorDisplayName,
  uef.total_edits AS TotalEditsByEditor,
  uef.distinct_posts_edited AS DistinctPostsEditedByEditor,
  uef.avg_time_between_edits AS AvgTimeBetweenEditorEdits,
  pem.PostId,
  pem.PostCreationDate,
  pem.distinct_title_editors AS DistinctTitleEditorsForPost,
  pem.distinct_body_editors AS DistinctBodyEditorsForPost,
  pem.distinct_tag_editors AS DistinctTagEditorsForPost,
  pem.total_body_edits AS TotalBodyEditsForPost,
  pem.post_last_edit_date AS PostLastEditDate,
  COALESCE(pht.Name, 'Unknown') AS LastEditType,
  CASE
    WHEN uef.UserId IS NULL THEN 'No Significant Editing Activity'
    WHEN uef.total_edits < 10 THEN 'Infrequent Editor'
    ELSE 'Frequent Editor'
  END AS EditorActivityLevel,
  UPPER(SUBSTRING(p.Title FROM 1 FOR 3)) AS TitlePrefix,
  LENGTH(p.Tags) AS TagLength,
  CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  CASE WHEN p.OwnerUserId = u.Id THEN 'Original Poster' ELSE 'Other' END AS EditorRelationship
FROM
  UserEditFrequency uef
JOIN
  Users u ON uef.UserId = u.Id
LEFT JOIN
  PostEditMetrics pem ON u.Id = (
    SELECT
      ph2.UserId
    FROM
      PostHistory ph2
    WHERE
      ph2.PostId = pem.PostId
      AND ph2.PostHistoryTypeId IN (4, 5, 6)
      AND ph2.CreationDate = pem.post_last_edit_date
    LIMIT 1
  )
LEFT JOIN
  Posts p ON pem.PostId = p.Id
LEFT JOIN
  PostHistoryTypes pht ON pht.Id = (
    SELECT
      ph3.PostHistoryTypeId
    FROM
      PostHistory ph3
    WHERE
      ph3.PostId = p.Id
      AND ph3.CreationDate = pem.post_last_edit_date
    LIMIT 1
  )
WHERE
  pem.last_body_edit_date IS NOT NULL
  AND pem.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year')
  AND LENGTH(p.Title) > 10
GROUP BY
  u.DisplayName,
  uef.total_edits,
  uef.distinct_posts_edited,
  uef.avg_time_between_edits,
  pem.PostId,
  pem.PostCreationDate,
  pem.distinct_title_editors,
  pem.distinct_body_editors,
  pem.distinct_tag_editors,
  pem.total_body_edits,
  pem.post_last_edit_date,
  pht.Name,
  uef.UserId,
  p.Title,
  p.Tags,
  p.ClosedDate,
  p.OwnerUserId,
  u.Id
ORDER BY
  EditorActivityLevel DESC,
  TotalEditsByEditor DESC,
  PostCreationDate ASC
LIMIT 100;