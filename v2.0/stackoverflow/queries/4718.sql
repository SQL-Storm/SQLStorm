-- {"query": "4718.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1486} 
WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      p.OwnerUserId AS PostOwnerUserId,
      p.PostTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
      JOIN Posts AS p ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (2, 5) -- Edits to Body or Initial Body
  ),
  LatestEdits AS (
    SELECT
      PostId,
      UserId AS EditorUserId,
      CreationDate AS EditDate,
      PostOwnerUserId,
      PostTypeId
    FROM
      RankedPostHistory
    WHERE
      rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.LastActivityDate) AS LastPostActivity
    FROM
      Users AS u
      LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
      Badges
    GROUP BY
      UserId
  ),
  PostEditComplexity AS (
    SELECT
      le.PostId,
      le.EditorUserId,
      le.EditDate,
      le.PostOwnerUserId,
      le.PostTypeId,
      u.Reputation AS EditorReputation,
      ua.TotalPosts AS EditorTotalPosts,
      ua.QuestionCount AS EditorQuestionCount,
      ua.AnswerCount AS EditorAnswerCount,
      ubc.GoldBadges AS EditorGoldBadges,
      ubc.SilverBadges AS EditorSilverBadges,
      ubc.BronzeBadges AS EditorBronzeBadges,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.CommentCount AS PostCommentCount,
      LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<p>', '')) AS ParagraphCount, -- Crude estimate of content complexity
      (
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', ''))
      ) AS CodeTagCount -- Another complexity measure
    FROM
      LatestEdits AS le
      JOIN Posts AS p ON le.PostId = p.Id
      JOIN Users AS u ON le.EditorUserId = u.Id
      LEFT JOIN UserActivity AS ua ON le.EditorUserId = ua.UserId
      LEFT JOIN UserBadgeCounts AS ubc ON le.EditorUserId = ubc.UserId
    WHERE
      p.PostTypeId IN (1, 2) -- Only consider Questions and Answers for this analysis
  )
SELECT
  pec.PostId,
  pec.PostTypeId,
  pt.Name AS PostTypeName,
  pec.EditorUserId,
  u_editor.DisplayName AS EditorDisplayName,
  pec.EditDate,
  pec.PostOwnerUserId,
  u_owner.DisplayName AS PostOwnerDisplayName,
  pec.EditorReputation,
  COALESCE(pec.EditorTotalPosts, 0) AS EditorTotalPosts,
  COALESCE(pec.EditorQuestionCount, 0) AS EditorQuestionCount,
  COALESCE(pec.EditorAnswerCount, 0) AS EditorAnswerCount,
  COALESCE(pec.EditorGoldBadges, 0) AS EditorGoldBadges,
  COALESCE(pec.EditorSilverBadges, 0) AS EditorSilverBadges,
  COALESCE(pec.EditorBronzeBadges, 0) AS EditorBronzeBadges,
  pec.PostScore,
  pec.PostViewCount,
  pec.PostCommentCount,
  pec.ParagraphCount,
  pec.CodeTagCount,
  CASE
    WHEN pec.EditDate < u_owner.CreationDate THEN 'Editor Created Before Owner'
    WHEN pec.EditDate > u_owner.LastAccessDate THEN 'Editor Edited After Owner Last Access'
    ELSE 'Standard Edit'
  END AS EditContext,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory AS ph_closed
    WHERE
      ph_closed.PostId = pec.PostId
      AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
      AND ph_closed.CreationDate < pec.EditDate
  ) AS PriorCloseVotes,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = pec.PostId
      AND pl.LinkTypeId = 3 -- Duplicate Link
  ) AS DuplicateLinksToThisPost,
  (
    SELECT
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -- UpVotes
    FROM
      Votes AS v
    WHERE
      v.PostId = pec.PostId
      AND v.CreationDate < pec.EditDate
  ) AS PreEditUpvotes,
  (
    SELECT
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) -- DownVotes
    FROM
      Votes AS v
    WHERE
      v.PostId = pec.PostId
      AND v.CreationDate < pec.EditDate
  ) AS PreEditDownvotes
FROM
  PostEditComplexity AS pec
  JOIN PostTypes AS pt ON pec.PostTypeId = pt.Id
  JOIN Users AS u_editor ON pec.EditorUserId = u_editor.Id
  LEFT JOIN Users AS u_owner ON pec.PostOwnerUserId = u_owner.Id
ORDER BY
  pec.EditDate DESC,
  pec.PostScore DESC
LIMIT 1000;