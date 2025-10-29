-- {"query": "4819.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2101} 

WITH
  PostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      pt.Name AS PostType,
      p.Title,
      p.Score AS PostScore,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COUNT(DISTINCT c.Id) AS CommentCount_
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      pt.Name,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS PostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      MAX(b.Date) AS LastBadgeDate,
      COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpvotesGiven,
      COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownvotesGiven
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostHistoryAnalysis AS (
    SELECT
      ph.PostId,
      COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS CloseVotes,
      MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory AS ph
    GROUP BY
      ph.PostId
  ),
  LaggedPostScores AS (
    SELECT
      PostId,
      PostCreationDate,
      PostScore,
      LAG(PostScore, 1, PostScore) OVER (PARTITION BY OwnerUserId ORDER BY PostCreationDate) AS PreviousPostScore,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY PostCreationDate) AS PostSequence
    FROM PostInteractions
    WHERE
      OwnerUserId IS NOT NULL
  )
SELECT
  pi.PostId,
  pi.PostType,
  pi.Title,
  pi.PostScore,
  pi.AnswerCount,
  pi.CommentCount,
  pi.FavoriteCount,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  ue.UserCreationDate AS OwnerCreationDate,
  CONCAT(
    ue.DisplayName,
    ' (',
    ue.Reputation,
    ')'
  ) AS OwnerInfo,
  pha.TotalHistoryEntries,
  pha.BodyEdits,
  pha.TitleEdits,
  pha.CloseVotes,
  pha.LastHistoryDate,
  CASE
    WHEN lps.PostScore > lps.PreviousPostScore THEN 'Increased'
    WHEN lps.PostScore < lps.PreviousPostScore THEN 'Decreased'
    ELSE 'Unchanged'
  END AS ScoreTrend,
  CASE
    WHEN pi.PostCreationDate < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'Old'
    ELSE 'Recent'
  END AS PostAgeCategory,
  CASE
    WHEN pi.AnswerCount > 10 THEN 'High'
    WHEN pi.AnswerCount > 5 THEN 'Medium'
    ELSE 'Low'
  END AS AnswerActivityLevel,
  CASE
    WHEN ue.BadgesEarned > 50 THEN 'Prolific'
    ELSE 'Standard'
  END AS UserBadgeLevel,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = pi.PostId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinkCount,
  (
    SELECT
      COUNT(*)
    FROM Comments AS sub_c
    WHERE
      sub_c.PostId = pi.PostId
      AND sub_c.UserId IS NULL
  ) AS AnonymousCommentCount,
  CASE
    WHEN pi.PostScore > 100 AND pi.AnswerCount > 20 THEN TRUE
    ELSE FALSE
  END AS IsHighlyRatedAndAnswered,
  ue.UpvotesGiven AS TotalUpvotesGivenByOwner,
  ue.DownvotesGiven AS TotalDownvotesGivenByOwner,
  pi.PostCreationDate AS PostCreationTimestamp,
  pha.LastHistoryDate AS LastPostHistoryTimestamp,
  ue.LastBadgeDate AS OwnerLastBadgeTimestamp,
  lps.PostSequence
FROM PostInteractions AS pi
LEFT JOIN UserEngagement AS ue
  ON pi.OwnerUserId = ue.UserId
LEFT JOIN PostHistoryAnalysis AS pha
  ON pi.PostId = pha.PostId
LEFT JOIN LaggedPostScores AS lps
  ON pi.PostId = lps.PostId
WHERE
  pi.PostType = 'Question' AND pi.PostScore > 0
UNION
SELECT
  pi.PostId,
  pi.PostType,
  pi.Title AS AnswerTitle,
  pi.PostScore,
  NULL AS AnswerCount,
  pi.CommentCount,
  pi.FavoriteCount,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  ue.UserCreationDate AS OwnerCreationDate,
  CONCAT(
    ue.DisplayName,
    ' (',
    ue.Reputation,
    ')'
  ) AS OwnerInfo,
  pha.TotalHistoryEntries,
  pha.BodyEdits,
  pha.TitleEdits,
  pha.CloseVotes,
  pha.LastHistoryDate,
  CASE
    WHEN lps.PostScore > lps.PreviousPostScore THEN 'Increased'
    WHEN lps.PostScore < lps.PreviousPostScore THEN 'Decreased'
    ELSE 'Unchanged'
  END AS ScoreTrend,
  CASE
    WHEN pi.PostCreationDate < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'Old'
    ELSE 'Recent'
  END AS PostAgeCategory,
  CASE
    WHEN pi.CommentCount > 10 THEN 'High'
    ELSE 'Low'
  END AS CommentActivityLevel,
  CASE
    WHEN ue.BadgesEarned > 50 THEN 'Prolific'
    ELSE 'Standard'
  END AS UserBadgeLevel,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = pi.PostId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinkCount,
  (
    SELECT
      COUNT(*)
    FROM Comments AS sub_c
    WHERE
      sub_c.PostId = pi.PostId
      AND sub_c.UserId IS NULL
  ) AS AnonymousCommentCount,
  CASE
    WHEN pi.PostScore > 50 THEN TRUE
    ELSE FALSE
  END AS IsHighlyRated,
  ue.UpvotesGiven AS TotalUpvotesGivenByOwner,
  ue.DownvotesGiven AS TotalDownvotesGivenByOwner,
  pi.PostCreationDate AS PostCreationTimestamp,
  pha.LastHistoryDate AS LastPostHistoryTimestamp,
  ue.LastBadgeDate AS OwnerLastBadgeTimestamp,
  lps.PostSequence
FROM PostInteractions AS pi
LEFT JOIN UserEngagement AS ue
  ON pi.OwnerUserId = ue.UserId
LEFT JOIN PostHistoryAnalysis AS pha
  ON pi.PostId = pha.PostId
LEFT JOIN LaggedPostScores AS lps
  ON pi.PostId = lps.PostId
WHERE
  pi.PostType = 'Answer' AND pi.PostScore > 5;
