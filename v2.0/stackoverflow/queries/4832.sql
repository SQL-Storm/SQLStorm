-- {"query": "4832.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1717}
WITH
  RelevantPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
        ELSE NULL
      END AS MainTag,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.Score > 0
      AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '365' DAY)
  ),
  RecentQuestions AS (
    SELECT
      PostId,
      OwnerUserId,
      OwnerDisplayName,
      PostCreationDate,
      Score,
      ViewCount,
      AnswerCount,
      CommentCount,
      FavoriteCount,
      MainTag,
      ROW_NUMBER() OVER (ORDER BY PostCreationDate DESC) AS q_rn
    FROM RelevantPosts
    WHERE
      PostTypeId = 1
      AND rn <= 500
  ),
  RecentAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswerOwnerUserId,
      u.DisplayName AS AnswerOwnerDisplayName,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS a_rn
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
      AND p.ParentId IN (SELECT PostId FROM RecentQuestions)
      AND p.Score > 0
  ),
  QuestionTags AS (
    SELECT
      Id AS PostId,
      REPLACE(REPLACE(REPLACE(Tags, '<', ''), '>', ''), ' ', ',') AS TagList
    FROM Posts
    WHERE
      PostTypeId = 1
      AND Id IN (SELECT PostId FROM RecentQuestions)
  ),
  TagAnalysis AS (
    SELECT
      q.PostId,
      t.TagName,
      CASE
        WHEN qt.TagList LIKE '%' || t.TagName || '%' THEN 1 ELSE 0
      END AS HasTag,
      COUNT(t.Id) OVER (PARTITION BY q.PostId) AS TotalTags
    FROM RecentQuestions q
    LEFT JOIN Tags t
      ON 1 = 1
    LEFT JOIN QuestionTags qt
      ON q.PostId = qt.PostId
    WHERE
      t.TagName IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.PostId) AS PostsEdited,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END) AS EditsOfTypeBodyOrTitle,
      MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN PostHistory ph
      ON u.Id = ph.UserId
    WHERE
      u.Id IN (SELECT OwnerUserId FROM RecentQuestions)
      OR u.Id IN (SELECT AnswerOwnerUserId FROM RecentAnswers)
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostMetaData AS (
    SELECT
      rq.PostId,
      rq.OwnerDisplayName,
      rq.PostCreationDate,
      rq.Score,
      rq.ViewCount,
      rq.AnswerCount,
      rq.CommentCount,
      rq.FavoriteCount,
      rq.MainTag,
      (
        SELECT COUNT(*)
        FROM Comments c
        WHERE
          c.PostId = rq.PostId
          AND c.CreationDate >= rq.PostCreationDate
      ) AS CommentCountOnPost,
      (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes v
        WHERE
          v.PostId = rq.PostId
          AND v.VoteTypeId IN (2, 3)
      ) AS VoteCountForPost,
      (
        SELECT AVG(ra.AnswerScore)
        FROM RecentAnswers ra
        WHERE
          ra.QuestionId = rq.PostId
      ) AS AvgAnswerScoreForQuestion,
      rq.PostCreationDate AS __dummy_for_grouping
    FROM RecentQuestions rq
  )
SELECT
  pmd.PostId,
  pmd.OwnerDisplayName,
  pmd.PostCreationDate,
  pmd.Score,
  pmd.ViewCount,
  pmd.AnswerCount,
  pmd.CommentCount,
  pmd.FavoriteCount,
  pmd.MainTag,
  pmd.CommentCountOnPost,
  pmd.VoteCountForPost,
  pmd.AvgAnswerScoreForQuestion,
  ua.PostsEdited,
  ua.EditsOfTypeBodyOrTitle,
  ua.LastEditDate,
  STRING_AGG(DISTINCT ta.TagName, ',') AS AllTags,
  SUM(CASE WHEN ta.HasTag = 1 THEN 1 ELSE 0 END) AS PrimaryTagCount,
  ta.TotalTags,
  CASE
    WHEN pmd.PostId IS NOT NULL THEN 'Active' ELSE 'Active'
  END AS PostStatus,
  COALESCE(ua.DisplayName, 'Unknown User') AS UserDisplayNameOrPlaceholder,
  CASE WHEN pmd.ViewCount > 10000 THEN 'High View Count' ELSE 'Standard View Count' END AS ViewCountCategory,
  UPPER(REPLACE(pmd.MainTag, '-', ' ')) AS FormattedMainTag
FROM PostMetaData pmd
LEFT JOIN TagAnalysis ta
  ON pmd.PostId = ta.PostId
LEFT JOIN UserActivity ua
  ON pmd.OwnerDisplayName = ua.DisplayName
GROUP BY
  pmd.PostId,
  pmd.OwnerDisplayName,
  pmd.PostCreationDate,
  pmd.Score,
  pmd.ViewCount,
  pmd.AnswerCount,
  pmd.CommentCount,
  pmd.FavoriteCount,
  pmd.MainTag,
  pmd.CommentCountOnPost,
  pmd.VoteCountForPost,
  pmd.AvgAnswerScoreForQuestion,
  ua.PostsEdited,
  ua.EditsOfTypeBodyOrTitle,
  ua.LastEditDate,
  ta.TotalTags,
  COALESCE(ua.DisplayName, 'Unknown User'),
  CASE WHEN pmd.ViewCount > 10000 THEN 'High View Count' ELSE 'Standard View Count' END,
  UPPER(REPLACE(pmd.MainTag, '-', ' '))
HAVING
  COUNT(ta.TagName) > 0
ORDER BY
  pmd.Score DESC,
  pmd.ViewCount DESC
LIMIT 100;