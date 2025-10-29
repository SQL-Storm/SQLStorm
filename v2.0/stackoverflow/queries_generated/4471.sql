-- {"query": "4471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1594} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      u.DisplayName AS OwnerDisplayName,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.ViewCount AS QuestionViewCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      pt.Name AS PostTypeName,
      COUNT(c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM
      Posts AS p
      JOIN Users AS u
      ON p.OwnerUserId = u.Id
      JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Comments AS c
      ON p.Id = c.PostId
      LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id,
      p.Title,
      p.CreationDate,
      u.DisplayName,
      p.Score,
      p.AnswerCount,
      p.ViewCount,
      p.ClosedDate,
      pt.Name
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      a.OwnerUserId,
      a.CommunityOwnedDate,
      CASE
        WHEN a.Id = q.AcceptedAnswerId THEN 1
        ELSE 0
      END AS IsAcceptedAnswer,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM
      Posts AS a
      JOIN Posts AS q
      ON a.ParentId = q.Id
    WHERE
      a.PostTypeId = 2 -- Answers only
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN PostTypeId = 5 THEN 1 ELSE 0 END) AS TagWikiCount,
      SUM(CASE WHEN PostTypeId = 4 THEN 1 ELSE 0 END) AS TagWikiExcerptCount,
      MAX(CreationDate) AS LastPostDate,
      COUNT(DISTINCT PostId) AS DistinctPostsParticipated
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY
      UserId
  ),
  LaggedPostScore AS (
    SELECT
      PostId,
      Score,
      CreationDate,
      LAG(Score, 1, 0) OVER (PARTITION BY PostId ORDER BY CreationDate) AS PreviousScore,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
  ),
  RecentPostEdits AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastEditDate
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 7, 8) -- Title/Body edits/rollbacks
    GROUP BY
      PostId
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.QuestionScore,
  qd.AnswerCount AS TotalAnswers,
  qd.QuestionViewCount,
  qd.IsClosed,
  qd.PostTypeName,
  qd.CommentCount,
  qd.UpVoteCount,
  qd.DownVoteCount,
  ad.AnswerId,
  ad.AnswerScore,
  ad.AnswerCreationDate,
  ad.IsAcceptedAnswer,
  ad.AnswerRank,
  ua.TotalPosts AS OwnerTotalPosts,
  ua.QuestionCount AS OwnerQuestionCount,
  ua.AnswerCount AS OwnerAnswerCount,
  ua.TagWikiCount AS OwnerTagWikiCount,
  ua.TagWikiExcerptCount AS OwnerTagWikiExcerptCount,
  ua.LastPostDate AS OwnerLastPostDate,
  ua.DistinctPostsParticipated AS OwnerDistinctPostsParticipated,
  lps.Score AS LatestBodyScore,
  lps.PreviousScore AS PreviousBodyScore,
  CASE
    WHEN rpe.LastEditDate > qd.QuestionCreationDate THEN 1
    ELSE 0
  END AS HasRecentEdit,
  COALESCE(
    (
      SELECT
        GROUP_CONCAT(t.TagName, ', ')
      FROM
        Tags AS t
      WHERE
        INSTR(qd.Tags, '<' || t.TagName || '>') > 0
    ),
    'None'
  ) AS FormattedTags
FROM
  QuestionDetails AS qd
LEFT JOIN AnswerDetails AS ad
  ON qd.QuestionId = ad.QuestionId
LEFT JOIN UserActivity AS ua
  ON qd.OwnerUserId = ua.UserId
LEFT JOIN LaggedPostScore AS lps
  ON qd.QuestionId = lps.PostId AND lps.rn = 1
LEFT JOIN RecentPostEdits AS rpe
  ON qd.QuestionId = rpe.PostId
WHERE
  qd.QuestionScore > 10
  AND qd.AnswerCount BETWEEN 3 AND 10
  AND qd.QuestionViewCount > 5000
  AND qd.OwnerTotalPosts > 50
  AND LENGTH(qd.QuestionTitle) < 150
  AND qd.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
UNION
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM
  Posts AS p
WHERE
  p.PostTypeId = 1
  AND p.Score <= 0
  AND p.AnswerCount = 0
  AND p.ViewCount < 100
  AND p.CreationDate < DATE('now', '-365 day')
LIMIT
  1000;
