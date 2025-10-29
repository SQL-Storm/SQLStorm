-- {"query": "4976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1487} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.ViewCount AS NUMERIC)) AS AvgViewCount,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
      p.OwnerUserId
  ),
  TopContributors AS (
    SELECT
      upa.OwnerUserId,
      u.DisplayName,
      upa.TotalPosts,
      upa.TotalScore,
      upa.AvgViewCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges AS b
        WHERE
          b.UserId = upa.OwnerUserId
          AND b.Class = 1 -- Gold Badges
      ) AS GoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges AS b
        WHERE
          b.UserId = upa.OwnerUserId
          AND b.Class = 2 -- Silver Badges
      ) AS SilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges AS b
        WHERE
          b.UserId = upa.OwnerUserId
          AND b.Class = 3 -- Bronze Badges
      ) AS BronzeBadgeCount
    FROM
      UserPostActivity AS upa
    JOIN
      Users AS u
      ON upa.OwnerUserId = u.Id
    WHERE
      upa.TotalPosts > 100 -- Consider users with significant activity
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionDate,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      pt.Name AS PostTypeName,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.AnswerCount = 0 THEN 'Unanswered'
        WHEN q.FavoriteCount > 10 THEN 'Popular'
        ELSE 'Active'
      END AS QuestionStatus
    FROM
      Posts AS q
    JOIN
      PostTypes AS pt
      ON q.PostTypeId = pt.Id
    WHERE
      q.PostTypeId = 1 -- Questions only
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.Score AS AnswerScore,
      a.CreationDate AS AnswerDate,
      a.LastEditDate,
      CASE
        WHEN a.Score > (SELECT AVG(Score) FROM Posts WHERE ParentId = a.ParentId AND PostTypeId = 2) THEN 'Above Average'
        WHEN a.Score < (SELECT AVG(Score) FROM Posts WHERE ParentId = a.ParentId AND PostTypeId = 2) THEN 'Below Average'
        ELSE 'Average'
      END AS AnswerQuality,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM
      Posts AS a
    WHERE
      a.PostTypeId = 2 -- Answers only
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.QuestionDate,
  tc.DisplayName AS TopContributorName,
  tc.TotalPosts,
  tc.TotalScore,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.QuestionStatus,
  ad.AnswerId,
  ad.AnswerOwnerUserId,
  ad.AnswerScore,
  ad.AnswerDate,
  ad.AnswerQuality,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = qd.QuestionId
        AND pl.LinkTypeId = 3 -- Duplicate link
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateStatus,
  COALESCE(u.DisplayName, 'Unknown User') AS QuestionOwnerDisplayName,
  ph.UserDisplayName AS LastEditorDisplayName,
  ph.EditDate AS LastEditDate,
  DATEDIFF(day, qd.QuestionDate, GETDATE()) AS DaysSinceQuestion,
  CASE
    WHEN qd.ClosedDate IS NOT NULL THEN FORMAT(qd.ClosedDate, 'yyyy-MM-dd')
    ELSE 'Not Closed'
  END AS FormattedClosedDate,
  (
    SELECT
      STRING_AGG(u2.DisplayName, ', ')
    FROM
      Comments AS c
    JOIN
      Users AS u2
      ON c.UserId = u2.Id
    WHERE
      c.PostId = qd.QuestionId
      AND c.Score > 5
  ) AS TopCommentersForQuestion
FROM
  QuestionDetails AS qd
LEFT OUTER JOIN
  TopContributors AS tc
  ON qd.QuestionOwnerUserId = tc.OwnerUserId
LEFT OUTER JOIN
  AnswerDetails AS ad
  ON qd.QuestionId = ad.QuestionId
  AND ad.AnswerRank = 1 -- Only the best answer
LEFT OUTER JOIN
  Users AS u
  ON qd.QuestionOwnerUserId = u.Id
LEFT OUTER JOIN
  RankedPostEdits AS ph
  ON qd.QuestionId = ph.PostId
  AND ph.rn = 1 -- Latest edit
WHERE
  qd.QuestionOwnerUserId IS NOT NULL
  AND qd.AnswerCount > 0
  AND qd.QuestionStatus <> 'Closed'
  AND DATEDIFF(day, qd.QuestionDate, GETDATE()) BETWEEN 30 AND 365 -- Questions posted within the last year, but older than 30 days
ORDER BY
  qd.FavoriteCount DESC,
  qd.AnswerCount DESC,
  qd.QuestionDate ASC;
