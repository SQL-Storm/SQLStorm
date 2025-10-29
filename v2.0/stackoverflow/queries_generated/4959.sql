-- {"query": "4959.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1606} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(p.ViewCount) AS TotalViews,
      SUM(p.AnswerCount) AS TotalAnswers,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  RecentEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS EditorUserId,
      rpe.CreationDate AS EditDate
    FROM
      RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
      AND rpe.CreationDate > DATE('now', '-30 day')
  ),
  EditorReputation AS (
    SELECT
      re.EditorUserId,
      u.Reputation,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes
    FROM
      RecentEdits AS re
      JOIN Users AS u
        ON re.EditorUserId = u.Id
  ),
  PostDetails AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      p.Title,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      p.ClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions only for this example
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
      SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount
    FROM
      Comments AS c
    GROUP BY
      c.PostId
  ),
  VoteAnalysis AS (
    SELECT
      v.PostId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVoteCount,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVoteCount,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE NULL END) AS FavoriteVoteCount
    FROM
      Votes AS v
      JOIN VoteTypes AS vt
        ON v.VoteTypeId = vt.Id
    WHERE
      vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY
      v.PostId
  )
SELECT
  pd.PostId,
  pd.Title,
  pd.PostTypeName,
  pd.OwnerDisplayName,
  pd.OwnerReputation,
  pd.Score,
  pd.ViewCount,
  pd.AnswerCount,
  pd.CommentCount AS PostCommentCount,
  pd.FavoriteCount AS PostFavoriteCount,
  pd.PostCreationDate,
  pd.LastActivityDate,
  pd.IsClosed,
  pd.IsCommunityOwned,
  COALESCE(ca.CommentCount, 0) AS TotalCommentsOnPost,
  COALESCE(ca.PositiveCommentCount, 0) AS PositiveCommentsOnPost,
  COALESCE(ca.AnonymousCommentCount, 0) AS AnonymousCommentsOnPost,
  COALESCE(va.UpVoteCount, 0) AS TotalUpVotes,
  COALESCE(va.DownVoteCount, 0) AS TotalDownVotes,
  COALESCE(va.FavoriteVoteCount, 0) AS TotalFavorites,
  COALESCE(ua.PostCount, 0) AS OwnerTotalPosts,
  COALESCE(ua.TotalViews, 0) AS OwnerTotalViews,
  COALESCE(ua.TotalAnswers, 0) AS OwnerTotalAnswers,
  ua.AverageScore AS OwnerAverageScore,
  ua.LastPostDate AS OwnerLastPostDate,
  ed.Reputation AS MostRecentEditorReputation,
  ed.UserUpVotes AS MostRecentEditorUpVotes,
  ed.UserDownVotes AS MostRecentEditorDownVotes,
  CASE
    WHEN pd.OwnerReputation > 10000 AND pd.Score > 50 THEN 'HighReputationHighScore'
    WHEN pd.OwnerReputation < 1000 AND pd.Score < 5 THEN 'LowReputationLowScore'
    WHEN pd.IsClosed = 1 THEN 'ClosedQuestion'
    WHEN pd.PostCreationDate < DATE('now', '-365 day') THEN 'OldQuestion'
    ELSE 'Standard'
  END AS QuestionCategory,
  SUBSTR(pd.Title, 1, 50) || '...' AS ShortTitle,
  CAST(STRFTIME('%Y-%m', pd.PostCreationDate) AS TEXT) AS PostCreationYearMonth,
  CASE
    WHEN UPPER(pd.Title) LIKE '%PERFORMANCE%' OR UPPER(pd.Title) LIKE '%BENCHMARK%' OR pd.OwnerUserId = 1 THEN 'PerformanceRelated'
    ELSE 'Other'
  END AS TitlePerformanceIndicator
FROM
  PostDetails AS pd
  LEFT JOIN CommentAnalysis AS ca
    ON pd.PostId = ca.PostId
  LEFT JOIN VoteAnalysis AS va
    ON pd.PostId = va.PostId
  LEFT JOIN UserActivity AS ua
    ON pd.OwnerUserId = ua.OwnerUserId
  LEFT JOIN EditorReputation AS ed
    ON pd.PostId = ANY (
      SELECT
        re.PostId
      FROM
        RecentEdits AS re
      WHERE
        re.EditorUserId = ed.EditorUserId
    )
WHERE
  pd.PostTypeId = 1
ORDER BY
  pd.Score DESC,
  pd.LastActivityDate DESC
LIMIT 100;
