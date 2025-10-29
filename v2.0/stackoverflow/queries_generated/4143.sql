-- {"query": "4143.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1313} 
WITH RECURSIVE TagHierarchy AS (
  SELECT
    Id,
    TagName,
    Count,
    0 AS Depth,
    CAST(TagName AS VARCHAR(8000)) AS Path
  FROM Tags
  WHERE
    Id IN (
      SELECT
        Id
      FROM Tags
      ORDER BY
        Count DESC
      LIMIT 5
    )
  UNION ALL
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    th.Depth + 1,
    CAST(th.Path || ' > ' || t.TagName AS VARCHAR(8000))
  FROM Tags t
  JOIN PostLinks pl
    ON t.Id = pl.RelatedPostId
  JOIN TagHierarchy th
    ON pl.PostId = Tags.Id
  WHERE
    th.Depth < 5
), RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn,
    SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalScore,
    AVG(p.AnswerCount) OVER (PARTITION BY p.OwnerUserId) AS AvgAnswerCount,
    COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId) AS PostCount
  FROM Posts p
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= DATE('now', '-365 day')
), UserActivity AS (
  SELECT
    UserId,
    COUNT(Id) AS CommentCount,
    SUM(Score) AS TotalCommentScore,
    MAX(CreationDate) AS LastCommentDate
  FROM Comments
  WHERE
    UserId IS NOT NULL
  GROUP BY
    UserId
), PostEngagement AS (
  SELECT
    p.Id AS PostId,
    COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
    COALESCE(COUNT(c.Id), 0) AS TotalComments,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
    COALESCE(COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END), 0) AS UpVotes,
    COALESCE(COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END), 0) AS DownVotes
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.Id
), UserPerformance AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(SUM(ph.Id IS NOT NULL), 0) AS PostHistoryEdits,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END), 0) AS ModerationActions,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 16 THEN 1 ELSE 0 END), 0) AS SuggestedEditsApproved
  FROM Users u
  LEFT JOIN PostHistory ph
    ON u.Id = ph.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId AND v.VoteTypeId = 16
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate
)
SELECT
  rp.Id AS QuestionId,
  rp.Title AS QuestionTitle,
  rp.OwnerDisplayName,
  rp.CreationDate AS QuestionCreationDate,
  rp.Score AS QuestionScore,
  rp.AnswerCount AS QuestionAnswerCount,
  rp.TotalScore AS OwnerTotalScore,
  rp.PostCount AS OwnerPostCount,
  ua.CommentCount AS OwnerCommentCount,
  ua.TotalCommentScore AS OwnerTotalCommentScore,
  pe.TotalComments AS QuestionTotalComments,
  pe.TotalCommentScore AS QuestionTotalCommentScore,
  pe.UpVotes AS QuestionUpVotes,
  pe.DownVotes AS QuestionDownVotes,
  up.PostHistoryEdits AS OwnerPostHistoryEdits,
  up.ModerationActions AS OwnerModerationActions,
  up.SuggestedEditsApproved AS OwnerSuggestedEditsApproved,
  th.Path AS RelatedTagPath
FROM RankedPosts rp
LEFT JOIN UserActivity ua
  ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostEngagement pe
  ON rp.Id = pe.PostId
LEFT JOIN UserPerformance up
  ON rp.OwnerUserId = up.UserId
LEFT JOIN Posts p_tag
  ON rp.Id = p_tag.Id
LEFT JOIN Tags t
  ON t.TagName IN (
    SELECT
      TRIM(value)
    FROM STRING_SPLIT(p_tag.Tags, '><')
  )
LEFT JOIN TagHierarchy th
  ON t.Id = th.Id
WHERE
  rp.rn <= 5
  AND ua.TotalCommentScore > 500
  AND pe.TotalComments > 10
  AND rp.Score > 100
ORDER BY
  rp.OwnerTotalScore DESC,
  rp.Score DESC,
  rp.QuestionCreationDate
LIMIT 100;