-- {"query": "4161.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1470}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (
        PARTITION BY p.ParentId
        ORDER BY p.Score DESC, p.CreationDate ASC
      ) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  QuestionStats AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.AnswerCount,
      q.ViewCount AS QuestionViewCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      q.ClosedDate AS QuestionClosedDate,
      COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
      MAX(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts q
    LEFT JOIN Comments c ON q.Id = c.PostId
    WHERE q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.OwnerUserId,
      q.Title,
      q.CreationDate,
      q.Score,
      q.AnswerCount,
      q.ViewCount,
      q.FavoriteCount,
      q.ClosedDate
  ),
  TopAnswers AS (
    SELECT
      ra.QuestionId,
      ra.PostId AS TopAnswerId,
      ra.OwnerUserId AS TopAnswerOwnerUserId,
      ra.Score AS TopAnswerScore,
      ra.AnswerCreationDate AS TopAnswerCreationDate
    FROM RankedAnswers ra
    WHERE ra.AnswerRank = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS TotalPostEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (3, 6) THEN 1 ELSE 0 END) AS TagEdits
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinksToOtherPosts,
      COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId ELSE NULL END) AS NumberOfDuplicateLinks,
      SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
      SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
  )
SELECT
  qs.QuestionId,
  qs.QuestionTitle,
  qs.QuestionScore,
  qs.QuestionViewCount,
  qs.QuestionFavoriteCount,
  qs.QuestionCreationDate,
  qs.QuestionOwnerUserId,
  ua.DisplayName AS QuestionOwnerDisplayName,
  qs.HasAcceptedAnswer,
  ta.TopAnswerId,
  ta.TopAnswerScore,
  ta.TopAnswerOwnerUserId,
  ua_ta.DisplayName AS TopAnswerOwnerDisplayName,
  qs.CommentCountOnQuestion,
  COALESCE(pla.NumberOfLinksToOtherPosts, 0) AS TotalLinksFromQuestion,
  COALESCE(pla.NumberOfDuplicateLinks, 0) AS DuplicateLinksFromQuestion,
  ua_editor.TotalPostEdits AS QuestionEditorActivity,
  ua_editor.BodyEdits AS QuestionBodyEditorActivity,
  ua_editor.TitleEdits AS QuestionTitleEditorActivity,
  ua_editor.TagEdits AS QuestionTagEditorActivity,
  CAST(DATE_PART('day', AGE(TIMESTAMP '2024-10-01 12:34:56', qs.QuestionCreationDate)) AS INTEGER) AS DaysSinceCreation,
  CASE
    WHEN qs.QuestionClosedDate IS NOT NULL THEN CAST(DATE_PART('day', AGE(qs.QuestionClosedDate, qs.QuestionCreationDate)) AS INTEGER)
    ELSE NULL
  END AS DaysToClose,
  CASE WHEN qs.QuestionClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
  (UPPER(SUBSTRING(qs.QuestionTitle FROM 1 FOR 1)) || LOWER(SUBSTRING(qs.QuestionTitle FROM 2 FOR CHAR_LENGTH(qs.QuestionTitle)))) AS FormattedQuestionTitle
FROM QuestionStats qs
LEFT JOIN UserActivity ua ON qs.QuestionOwnerUserId = ua.UserId
LEFT JOIN TopAnswers ta ON qs.QuestionId = ta.QuestionId
LEFT JOIN UserActivity ua_ta ON ta.TopAnswerOwnerUserId = ua_ta.UserId
LEFT JOIN PostLinkAnalysis pla ON qs.QuestionId = pla.PostId
LEFT JOIN UserActivity ua_editor ON qs.QuestionOwnerUserId = ua_editor.UserId
WHERE
  qs.QuestionScore > 10
  AND qs.AnswerCount BETWEEN 2 AND 10
  AND qs.QuestionViewCount > 1000
  AND qs.QuestionCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
  AND qs.QuestionOwnerUserId IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM Comments c_sub
    WHERE c_sub.PostId = qs.QuestionId
      AND c_sub.Text LIKE '%interesting%'
  )
ORDER BY
  qs.QuestionScore DESC,
  qs.QuestionViewCount DESC;