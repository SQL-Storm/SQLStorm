-- {"query": "4803.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1788}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM
      Posts p
    WHERE
      p.PostTypeId = 2
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.Tags,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.ViewCount AS QuestionViewCount,
      q.Score AS QuestionScore,
      q.AnswerCount AS QuestionAnswerCount,
      q.ClosedDate AS QuestionClosedDate,
      u.DisplayName AS QuestionOwnerDisplayName,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.AnswerCount > 100 THEN 'High Answer Count'
        ELSE 'Active'
      END AS QuestionStatus,
      (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = q.Id
      ) AS CommentCount
    FROM
      Posts q
    LEFT JOIN
      Users u
      ON q.OwnerUserId = u.Id
    WHERE
      q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      ph.UserId,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 END) AS TitleEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (3, 6) THEN 1 END) AS TagEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
      SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM
      PostHistory ph
    WHERE
      ph.UserId IS NOT NULL
    GROUP BY
      ph.UserId
  ),
  VoteSummary AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS Favorites
    FROM
      Votes v
    JOIN
      VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  PopularTags AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM
      Tags t
    WHERE
      t.IsModeratorOnly = FALSE
  ),
  QuestionTags AS (
    SELECT
      p.Id AS PostId,
      TRIM(tag) AS TagName
    FROM
      Posts p,
      LATERAL (
        SELECT regexp_split_to_table(
          regexp_replace(regexp_replace(COALESCE(p.Tags, ''), '[<>]', '', 'g'), ',{1,}', ',', 'g'),
          ','
        ) AS tag
      ) t
    WHERE
      p.PostTypeId = 1
  ),
  PostTagRanks AS (
    SELECT
      qt.PostId AS Id,
      pt.TagName,
      pt.TagCount,
      pt.TagRank
    FROM
      QuestionTags qt
    JOIN
      PopularTags pt
      ON qt.TagName = pt.TagName
  )
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.Tags,
  qd.QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionViewCount,
  qd.QuestionScore,
  qd.QuestionAnswerCount,
  qd.QuestionStatus,
  qd.CommentCount,
  qd.QuestionClosedDate,
  ra.OwnerUserId AS BestAnswerOwnerUserId,
  ra.Score AS BestAnswerScore,
  ra.CreationDate AS BestAnswerCreationDate,
  COALESCE(ua.BodyEdits, 0) AS QuestionOwnerBodyEdits,
  COALESCE(ua.TitleEdits, 0) AS QuestionOwnerTitleEdits,
  COALESCE(ua.TagEdits, 0) AS QuestionOwnerTagEdits,
  COALESCE(ua.CloseVotes, 0) AS QuestionOwnerCloseVotes,
  COALESCE(ua.ReopenVotes, 0) AS QuestionOwnerReopenVotes,
  COALESCE(vs.UpVotes, 0) AS QuestionOwnerUpVotes,
  COALESCE(vs.DownVotes, 0) AS QuestionOwnerDownVotes,
  COALESCE(vs.Favorites, 0) AS QuestionOwnerFavorites,
  CASE
    WHEN qd.QuestionScore > 1000 AND qd.QuestionAnswerCount > 50 THEN 'High Performing Question'
    WHEN qd.QuestionViewCount > 10000 THEN 'Popular Question'
    WHEN qd.QuestionClosedDate IS NOT NULL THEN 'Closed Question'
    ELSE 'Standard Question'
  END AS QuestionPerformanceCategory,
  CASE
    WHEN MIN(pt.TagRank) <= 10 THEN MIN(pt.TagName) OVER (PARTITION BY qd.QuestionId)
    ELSE 'Other'
  END AS TopTag1,
  CASE
    WHEN MIN(pt.TagRank) > 10 AND MIN(pt.TagRank) <= 20 THEN MIN(pt.TagName) OVER (PARTITION BY qd.QuestionId)
    ELSE 'Other'
  END AS TopTag2,
  (
    SELECT COUNT(ph.Id)
    FROM PostHistory ph
    WHERE ph.PostId = qd.QuestionId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
  ) AS TotalModerationActions
FROM
  QuestionDetails qd
LEFT JOIN
  RankedAnswers ra
  ON qd.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN
  UserActivity ua
  ON qd.QuestionOwnerUserId = ua.UserId
LEFT JOIN
  VoteSummary vs
  ON qd.QuestionOwnerUserId = vs.UserId
LEFT JOIN
  PostTagRanks pt
  ON qd.QuestionId = pt.Id
WHERE
  qd.QuestionCreationDate >= DATE '2023-01-01'
  AND qd.QuestionScore > 0
  AND pt.TagRank <= 20
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.Tags,
  qd.QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionViewCount,
  qd.QuestionScore,
  qd.QuestionAnswerCount,
  qd.QuestionStatus,
  qd.CommentCount,
  qd.QuestionClosedDate,
  ra.OwnerUserId,
  ra.Score,
  ra.CreationDate,
  ua.BodyEdits,
  ua.TitleEdits,
  ua.TagEdits,
  ua.CloseVotes,
  ua.ReopenVotes,
  vs.UpVotes,
  vs.DownVotes,
  vs.Favorites,
  pt.TagName,
  pt.TagRank,
  pt.TagCount
HAVING
  COUNT(pt.TagName) >= 1;