WITH
  PostEditSummary AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestEdits AS (
    SELECT
      PostId,
      EditorDisplayName,
      EditDate,
      EditType
    FROM PostEditSummary
    WHERE
      rn = 1
  ),
  PostTagCounts AS (
    SELECT
      p.Id AS PostId,
      COUNT(t.TagName) AS NumberOfTags
    FROM Posts p
    CROSS JOIN LATERAL (
      -- split tags like '<tag1><tag2>' into rows by extracting between '<' and '>'
      SELECT TRIM(value) AS value
      FROM (
        SELECT regexp_split_to_table(replace(replace(p.Tags, E'\\n', ' '), '><', '>|<'), E'\\|') AS value_raw
      ) sub1
      CROSS JOIN LATERAL (
        SELECT regexp_replace(value_raw, '^<|>$', '') AS value
      ) sub2
      WHERE p.Tags IS NOT NULL
    ) ts
    JOIN Tags t
      ON ts.value = t.TagName
    WHERE
      p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY
      p.Id
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate,
      LastAccessDate
    FROM Users
    WHERE
      Reputation >= 10000
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(pu.TotalPosts, 0) AS OwnerTotalPosts,
  COALESCE(pu.QuestionCount, 0) AS OwnerQuestionCount,
  COALESCE(pu.AnswerCount, 0) AS OwnerAnswerCount,
  pu.AverageScore AS OwnerAverageScore,
  COALESCE(le.EditorDisplayName, 'Community') AS LastEditorDisplayName,
  le.EditDate AS LastEditDate,
  le.EditType AS LastEditType,
  COALESCE(ptc.NumberOfTags, 0) AS NumberOfTags,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  hru.DisplayName AS HighReputationUserDisplayName,
  hru.Reputation AS HighReputationUserReputation,
  DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate) AS DaysSinceCreation
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserPostActivity pu
  ON p.OwnerUserId = pu.OwnerUserId
LEFT JOIN LatestEdits le
  ON p.Id = le.PostId
LEFT JOIN PostTagCounts ptc
  ON p.Id = ptc.PostId
LEFT JOIN HighReputationUsers hru
  ON p.OwnerUserId = hru.Id AND hru.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
WHERE
  p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years') AND p.Score > 50
UNION ALL
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(pu.TotalPosts, 0) AS OwnerTotalPosts,
  COALESCE(pu.QuestionCount, 0) AS OwnerQuestionCount,
  COALESCE(pu.AnswerCount, 0) AS OwnerAnswerCount,
  pu.AverageScore AS OwnerAverageScore,
  COALESCE(le.EditorDisplayName, 'Community') AS LastEditorDisplayName,
  le.EditDate AS LastEditDate,
  le.EditType AS LastEditType,
  COALESCE(ptc.NumberOfTags, 0) AS NumberOfTags,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  hru.DisplayName AS HighReputationUserDisplayName,
  hru.Reputation AS HighReputationUserReputation,
  DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate) AS DaysSinceCreation
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserPostActivity pu
  ON p.OwnerUserId = pu.OwnerUserId
LEFT JOIN LatestEdits le
  ON p.Id = le.PostId
LEFT JOIN PostTagCounts ptc
  ON p.Id = ptc.PostId
LEFT JOIN HighReputationUsers hru
  ON p.OwnerUserId = hru.Id AND hru.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
WHERE
  p.AnswerCount > 10 AND p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months');