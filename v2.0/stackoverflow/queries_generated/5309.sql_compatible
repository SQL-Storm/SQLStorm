WITH
  recent_posts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.Title,
      p.ViewCount,
      p.Score,
      p.CreationDate,
      p.OwnerUserId,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.LastActivityDate,
      p.ContentLicense,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_post
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
  ),
  author_stats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      u.AccountId,
      COUNT(DISTINCT c.PostId) AS recent_comments
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Posts pc ON pc.OwnerUserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.AccountId
  ),
  tag_summary AS (
    SELECT
      t.TagName,
      t.Count,
      t.ExcerptPostId,
      t.WikiPostId,
      ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn_tag
    FROM Tags t
  ),
  combined AS (
    SELECT
      rp.Id AS PostId,
      rp.PostTypeId,
      rp.Title,
      rp.ViewCount,
      rp.Score,
      rp.CreationDate,
      rp.OwnerUserId,
      rp.Tags,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      rp.LastActivityDate,
      rp.ContentLicense,
      asst.UserId AS AuthorUserId,
      asst.DisplayName AS AuthorDisplayName,
      asst.Reputation,
      asst.UserCreationDate,
      asst.LastAccessDate,
      asst.Views,
      asst.UpVotes,
      asst.DownVotes,
      asst.AccountId,
      asst.recent_comments,
      ts.TagName,
      ts.Count AS TagCount
    FROM recent_posts rp
    LEFT JOIN author_stats asst ON asst.UserId = rp.OwnerUserId
    LEFT JOIN tag_summary ts ON ts.rn_tag = 1
    LEFT JOIN (
      SELECT
        p.Id AS PostId,
        COUNT(*) AS recent_comments
      FROM Posts p
      JOIN Comments c ON c.PostId = p.Id
      WHERE c.CreationDate > p.CreationDate - INTERVAL '7 days'
      GROUP BY p.Id
    ) cs ON cs.PostId = rp.Id
  ),
  windowed AS (
    SELECT
      PostId,
      PostTypeId,
      Title,
      ViewCount,
      Score,
      CreationDate,
      OwnerUserId,
      Tags,
      AnswerCount,
      CommentCount,
      FavoriteCount,
      LastActivityDate,
      ContentLicense,
      AuthorUserId,
      AuthorDisplayName,
      Reputation,
      UserCreationDate,
      LastAccessDate,
      Views,
      UpVotes,
      DownVotes,
      AccountId,
      recent_comments,
      TagName,
      TagCount,
      SUM(ViewCount) OVER (PARTITION BY PostTypeId ORDER BY CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS Moving6DayViews,
      MAX(Score) OVER (PARTITION BY PostTypeId) AS MaxScoreByType,
      MIN(CASE WHEN OwnerUserId IS NULL THEN 1 ELSE 0 END) OVER () AS NullOwnerFlag
    FROM combined
    WHERE PostTypeId IN (1,2,3)
  ),
  heavy_pred AS (
    SELECT
      w.PostId,
      w.PostTypeId,
      w.Title,
      w.ViewCount,
      w.Score,
      w.CreationDate,
      w.OwnerUserId,
      w.Tags,
      w.AnswerCount,
      w.CommentCount,
      w.FavoriteCount,
      w.LastActivityDate,
      w.ContentLicense,
      w.AuthorUserId,
      w.AuthorDisplayName,
      w.Reputation,
      w.UserCreationDate,
      w.LastAccessDate,
      w.Views,
      w.UpVotes,
      w.DownVotes,
      w.AccountId,
      w.recent_comments,
      w.TagName,
      w.TagCount,
      w.Moving6DayViews,
      w.MaxScoreByType,
      w.NullOwnerFlag,
      CASE
        WHEN w.Score > 100 THEN 'HighScore'
        WHEN w.ViewCount > 1000 THEN 'Popular'
        ELSE 'Normal'
      END AS RankCategory,
      ARRAY_AGG(DISTINCT CASE WHEN c.PostId IS NOT NULL THEN CAST(c.PostId AS VARCHAR) || '|' || c.Text ELSE NULL END) FILTER (WHERE c.PostId IS NOT NULL) AS CommentSnippets
    FROM windowed w
    LEFT JOIN Comments c ON c.PostId = w.PostId
    GROUP BY w.PostId, w.PostTypeId, w.Title, w.ViewCount, w.Score, w.CreationDate, w.OwnerUserId,
             w.Tags, w.AnswerCount, w.CommentCount, w.FavoriteCount, w.LastActivityDate, w.ContentLicense,
             w.AuthorUserId, w.AuthorDisplayName, w.Reputation, w.UserCreationDate, w.LastAccessDate,
             w.Views, w.UpVotes, w.DownVotes, w.AccountId, w.recent_comments, w.TagName, w.TagCount,
             w.Moving6DayViews, w.MaxScoreByType, w.NullOwnerFlag
  )
SELECT
  hp.PostId,
  hp.PostTypeId,
  pt.Name AS PostTypeName,
  hp.Title,
  hp.ViewCount,
  hp.Score,
  hp.Moving6DayViews,
  hp.MaxScoreByType,
  hp.CreationDate,
  hp.LastActivityDate,
  hp.AuthorDisplayName,
  hp.Reputation,
  hp.CommentCount,
  hp.AnswerCount,
  hp.FavoriteCount,
  hp.TagName,
  hp.TagCount,
  hp.RankCategory,
  hp.CommentSnippets,
  CASE
    WHEN hp.OwnerUserId IS NULL THEN 'Anonymous'
    ELSE 'User'
  END AS OwnerPresence,
  (SELECT STRING_AGG(CONCAT_WS(':', COALESCE(u.DisplayName, ''), COALESCE(CAST(u.Reputation AS VARCHAR), '')), ',')
     FROM Users u
     WHERE u.Id = hp.OwnerUserId) AS OwnerProfile
FROM heavy_pred hp
LEFT JOIN PostTypes pt ON pt.Id = hp.PostTypeId
LEFT JOIN Votes v ON v.PostId = hp.PostId
LEFT JOIN Users u ON u.Id = hp.OwnerUserId
ORDER BY hp.PostTypeId, hp.Moving6DayViews DESC
LIMIT 100;