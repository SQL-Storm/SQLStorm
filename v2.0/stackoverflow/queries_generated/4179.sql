-- {"query": "4179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2725} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9
      )
  ),
  LatestPostRevisions AS (
    SELECT
      rph.PostId,
      rph.UserId AS EditorUserId,
      rph.PostHistoryTypeId AS LastEditTypeId,
      rph.CreationDate AS LastEditDate,
      rph.Comment AS LastEditComment,
      CASE
        WHEN rph.PostHistoryTypeId IN (1, 2, 3)
        THEN 'Initial'
        WHEN rph.PostHistoryTypeId IN (4, 5, 6)
        THEN 'Edit'
        WHEN rph.PostHistoryTypeId IN (7, 8, 9)
        THEN 'Rollback'
        ELSE 'Other'
      END AS EditTypeCategory
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
  ),
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      AVG(p.Score) AS AverageScoreOwned,
      MAX(p.CreationDate) AS LastPostDateOwned
    FROM Posts AS p
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AverageCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpVotes,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS TotalDownVotes,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS TotalFavorites,
      MAX(v.CreationDate) AS LastVoteDate
    FROM Votes AS v
    GROUP BY
      v.UserId
  ),
  ComplexCalculations AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.Views AS ProfileViews,
      u.UpVotes AS ProfileUpVotes,
      u.DownVotes AS ProfileDownVotes,
      u.CreationDate AS UserCreationDate,
      CASE
        WHEN u.WebsiteUrl IS NULL
        THEN 'No Website'
        WHEN INSTR(u.WebsiteUrl, 'http') = 0
        THEN 'Invalid URL Format'
        ELSE 'Valid URL'
      END AS WebsiteUrlStatus,
      COALESCE(ups.TotalPostsOwned, 0) AS TotalPostsOwned,
      COALESCE(ups.QuestionsOwned, 0) AS QuestionsOwned,
      COALESCE(ups.AnswersOwned, 0) AS AnswersOwned,
      COALESCE(ups.AverageScoreOwned, 0.0) AS AverageScoreOwned,
      COALESCE(ucs.TotalComments, 0) AS TotalComments,
      COALESCE(ucs.AverageCommentScore, 0.0) AS AverageCommentScore,
      COALESCE(uvs.TotalUpVotes, 0) AS TotalUpVotes,
      COALESCE(uvs.TotalDownVotes, 0) AS TotalDownVotes,
      COALESCE(uvs.TotalFavorites, 0) AS TotalFavorites,
      lpr.LastEditDate,
      lpr.EditTypeCategory,
      DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays,
      CASE
        WHEN u.LastAccessDate < DATEADD(month, -6, GETDATE())
        THEN 'Inactive'
        ELSE 'Active'
      END AS UserActivityStatus,
      CASE
        WHEN ups.LastPostDateOwned > ucs.LastCommentDate
        AND ups.LastPostDateOwned > uvs.LastVoteDate THEN 'Post Dominant'
        WHEN ucs.LastCommentDate > ups.LastPostDateOwned
        AND ucs.LastCommentDate > uvs.LastVoteDate THEN 'Comment Dominant'
        WHEN uvs.LastVoteDate > ups.LastPostDateOwned
        AND uvs.LastVoteDate > ucs.LastCommentDate THEN 'Vote Dominant'
        ELSE 'Mixed Activity'
      END AS PrimaryActivityType
    FROM Users AS u
    LEFT OUTER JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    LEFT OUTER JOIN UserCommentStats AS ucs
      ON u.Id = ucs.UserId
    LEFT OUTER JOIN UserVoteStats AS uvs
      ON u.Id = uvs.UserId
    LEFT OUTER JOIN LatestPostRevisions AS lpr
      ON u.Id = lpr.UserId AND lpr.rn = 1 -- Correlated subquery logic here implicitly via LEFT JOIN to the already filtered LatestPostRevisions
  )
SELECT
  cc.UserId,
  cc.DisplayName,
  cc.Reputation,
  cc.ProfileViews,
  cc.AccountAgeDays,
  cc.UserActivityStatus,
  cc.WebsiteUrlStatus,
  cc.TotalPostsOwned,
  cc.QuestionsOwned,
  cc.AnswersOwned,
  cc.AverageScoreOwned,
  cc.TotalComments,
  cc.AverageCommentScore,
  cc.TotalUpVotes,
  cc.TotalDownVotes,
  cc.TotalFavorites,
  cc.LastEditDate,
  cc.EditTypeCategory,
  cc.PrimaryActivityType,
  p.Title,
  pt.Name AS PostTypeName,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.FavoriteCount AS PostFavoriteCount,
  p.ViewCount AS PostViewCount,
  p.CommentCount AS PostCommentCount,
  p.AnswerCount AS PostAnswerCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL
    THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN p.CommunityOwnedDate IS NOT NULL
    THEN 'Community Wiki'
    ELSE 'User Owned'
  END AS PostOwnership,
  p.ContentLicense,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    )
    THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostHistory AS ph_closed
      WHERE
        ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10
    )
    THEN 'Was Closed'
    ELSE 'Never Closed'
  END AS CloseHistoryStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c_sub
    WHERE
      c_sub.PostId = p.Id
  ) AS CommentCountSubquery,
  (
    SELECT
      MAX(v_sub.CreationDate)
    FROM Votes AS v_sub
    WHERE
      v_sub.PostId = p.Id AND v_sub.VoteTypeId = 2
  ) AS LastUpVoteDateSubquery,
  CASE
    WHEN cc.UserCreationDate < DATEADD(year, -1, p.CreationDate)
    THEN 'Older Than 1 Year'
    ELSE 'Younger Than 1 Year'
  END AS UserAgeVsPostAge,
  LEN(p.Body) AS PostBodyLength,
  REPLACE(p.Title, ' ', '_') AS TitleWithUnderscores
FROM ComplexCalculations AS cc
JOIN Posts AS p
  ON cc.UserId = p.OwnerUserId
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
WHERE
  cc.Reputation > 1000
  AND p.Score > 5
  AND cc.TotalPostsOwned BETWEEN 10 AND 1000
  AND p.CreationDate >= DATEADD(month, -12, GETDATE())
  AND cc.UserActivityStatus = 'Active'
  AND pt.Name IN ('Question', 'Answer')
UNION ALL
SELECT
  NULL AS UserId,
  'Community User' AS DisplayName,
  NULL AS Reputation,
  NULL AS ProfileViews,
  NULL AS AccountAgeDays,
  NULL AS UserActivityStatus,
  'No Website' AS WebsiteUrlStatus,
  NULL AS TotalPostsOwned,
  NULL AS QuestionsOwned,
  NULL AS AnswersOwned,
  NULL AS AverageScoreOwned,
  NULL AS TotalComments,
  NULL AS AverageCommentScore,
  NULL AS TotalUpVotes,
  NULL AS TotalDownVotes,
  NULL AS TotalFavorites,
  NULL AS LastEditDate,
  NULL AS EditTypeCategory,
  NULL AS PrimaryActivityType,
  p.Title,
  pt.Name AS PostTypeName,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.FavoriteCount AS PostFavoriteCount,
  p.ViewCount AS PostViewCount,
  p.CommentCount AS PostCommentCount,
  p.AnswerCount AS PostAnswerCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL
    THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN p.CommunityOwnedDate IS NOT NULL
    THEN 'Community Wiki'
    ELSE 'User Owned'
  END AS PostOwnership,
  p.ContentLicense,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    )
    THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostHistory AS ph_closed
      WHERE
        ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10
    )
    THEN 'Was Closed'
    ELSE 'Never Closed'
  END AS CloseHistoryStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c_sub
    WHERE
      c_sub.PostId = p.Id
  ) AS CommentCountSubquery,
  (
    SELECT
      MAX(v_sub.CreationDate)
    FROM Votes AS v_sub
    WHERE
      v_sub.PostId = p.Id AND v_sub.VoteTypeId = 2
  ) AS LastUpVoteDateSubquery,
  NULL AS UserAgeVsPostAge,
  LEN(p.Body) AS PostBodyLength,
  REPLACE(p.Title, ' ', '_') AS TitleWithUnderscores
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
WHERE
  p.OwnerUserId = -1 -- Community User posts
  AND p.Score > 10
  AND p.CreationDate >= DATEADD(month, -12, GETDATE())
  AND pt.Name = 'Answer';
