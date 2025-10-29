-- {"query": "4425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1198} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      p.OwnerUserId AS OriginalOwnerUserId,
      p.PostTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserEditSummary AS (
    SELECT
      UserId,
      COUNT(DISTINCT PostId) AS UniquePostsEdited,
      SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
      AVG(p.Score) AS AvgPostScoreForEditedPosts
    FROM RankedPostEdits AS rpe
    JOIN Posts AS p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      UserId
  ),
  PostEditFrequency AS (
    SELECT
      PostId,
      COUNT(Id) AS EditCount
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      PostId
  ),
  HighEngagementUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavorites
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
    HAVING
      COUNT(p.Id) > 100 AND u.Reputation > 10000
  )
SELECT
  heu.DisplayName AS UserDisplayName,
  heu.Reputation,
  heu.TotalPostsOwned,
  heu.QuestionsOwned,
  heu.AnswersOwned,
  ues.UniquePostsEdited,
  ues.TitleEdits,
  ues.BodyEdits,
  ues.TagEdits,
  COALESCE(ues.AvgPostScoreForEditedPosts, 0) AS AvgScoreOfEditedPosts,
  COALESCE(pref.EditCount, 0) AS TotalEditsByThisUserOnTheirPosts,
  CASE
    WHEN heu.TotalFavorites > 0 THEN heu.TotalFavorites / CAST(heu.TotalPostsOwned AS REAL)
    ELSE 0
  END AS AvgFavoritesPerPost,
  CASE
    WHEN ues.UniquePostsEdited > 0 THEN CAST(ues.BodyEdits AS REAL) / ues.UniquePostsEdited
    ELSE 0
  END AS AvgBodyEditsPerUser,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = heu.Id AND b.Class = 1
    ),
    0
  ) AS GoldBadges,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = heu.Id AND b.Class = 2
    ),
    0
  ) AS SilverBadges,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = heu.Id AND b.Class = 3
    ),
    0
  ) AS BronzeBadges,
  LOWER(SUBSTRING(heu.DisplayName, 1, 3)) AS UserDisplayNamePrefix,
  COALESCE(
    (
      SELECT
        SUM(CAST(ph.CommentCount AS REAL))
      FROM Posts AS p
      JOIN PostHistory AS ph
        ON p.Id = ph.PostId
      WHERE
        p.OwnerUserId = heu.Id AND ph.PostHistoryTypeId = 5 -- Edit Body
    ),
    0
  ) AS TotalCommentEditsOnUserPosts
FROM HighEngagementUsers AS heu
LEFT JOIN UserEditSummary AS ues
  ON heu.Id = ues.UserId
LEFT JOIN PostEditFrequency AS pref
  ON heu.Id = pref.PostId
WHERE
  ues.UniquePostsEdited IS NOT NULL AND ues.UniquePostsEdited > 5
ORDER BY
  heu.Reputation DESC,
  AvgScoreOfEditedPosts DESC NULLS LAST
LIMIT 100;
