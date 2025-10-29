-- {"query": "4455.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1527} 

WITH
  TopPosters AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM Posts
    WHERE
      PostTypeId = 1
    GROUP BY
      OwnerUserId
    ORDER BY
      PostCount DESC
    LIMIT 10
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IN (
        SELECT
          OwnerUserId
        FROM TopPosters
      )
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AverageCommentScore
    FROM Comments AS c
    WHERE
      c.UserId IN (
        SELECT
          OwnerUserId
        FROM TopPosters
      )
    GROUP BY
      c.UserId
  ),
  UserBadgeCount AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM Badges AS b
    WHERE
      b.UserId IN (
        SELECT
          OwnerUserId
        FROM TopPosters
      )
    GROUP BY
      b.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVotes,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE NULL END) AS FavoriteVotes
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IN (
        SELECT
          OwnerUserId
        FROM TopPosters
      )
    GROUP BY
      v.UserId
  ),
  UserPostEngagement AS (
    SELECT
      upa.OwnerUserId,
      upa.PostId,
      upa.PostTypeName,
      upa.PostScore,
      upa.PostViewCount,
      upa.IsClosed,
      uca.CommentCount,
      uca.TotalCommentScore,
      ubc.GoldBadges,
      ubc.SilverBadges,
      ubc.BronzeBadges,
      uvs.UpVotes AS UserUpVotes,
      uvs.DownVotes AS UserDownVotes
    FROM UserPostActivity AS upa
    LEFT JOIN UserCommentActivity AS uca
      ON upa.OwnerUserId = uca.UserId
    LEFT JOIN UserBadgeCount AS ubc
      ON upa.OwnerUserId = ubc.UserId
    LEFT JOIN UserVoteStats AS uvs
      ON upa.OwnerUserId = uvs.UserId
    WHERE
      upa.RowNum <= 5
  )
SELECT
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.Views AS UserTotalViews,
  u.UpVotes AS UserTotalUpVotes,
  u.DownVotes AS UserTotalDownVotes,
  COALESCE(SUM(upe.PostScore), 0) AS TotalScoreOfTop5Posts,
  COALESCE(SUM(upe.PostViewCount), 0) AS TotalViewCountOfTop5Posts,
  COALESCE(COUNT(CASE WHEN upe.IsClosed = 1 THEN upe.PostId ELSE NULL END), 0) AS ClosedPostCount,
  COALESCE(AVG(upe.PostScore), 0.0) AS AverageScoreOfTop5Posts,
  COALESCE(MAX(upe.PostCreationDate), u.CreationDate) AS LastPostCreationDate,
  COALESCE(MAX(uca.CommentCount), 0) AS TotalCommentsMade,
  COALESCE(MAX(uca.TotalCommentScore), 0) AS TotalCommentScoreReceived,
  COALESCE(MAX(ubc.GoldBadges), 0) AS GoldBadgeCount,
  COALESCE(MAX(ubc.SilverBadges), 0) AS SilverBadgeCount,
  COALESCE(MAX(ubc.BronzeBadges), 0) AS BronzeBadgeCount,
  COALESCE(MAX(uvs.UpVotes), 0) AS UserTotalUpVotesCast,
  COALESCE(MAX(uvs.DownVotes), 0) AS UserTotalDownVotesCast,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
    ELSE 'No Website'
  END AS WebsiteStatus,
  UPPER(SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 3)) AS LocationAbbreviation,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = ANY (
        SELECT
          PostId
        FROM UserPostActivity AS upa_inner
        WHERE
          upa_inner.OwnerUserId = u.Id
      )
      AND pl.LinkTypeId = 3
  ) AS TotalDuplicateLinksCreated
FROM Users AS u
LEFT JOIN UserPostEngagement AS upe
  ON u.Id = upe.OwnerUserId
LEFT JOIN UserCommentActivity AS uca
  ON u.Id = uca.UserId
LEFT JOIN UserBadgeCount AS ubc
  ON u.Id = ubc.UserId
LEFT JOIN UserVoteStats AS uvs
  ON u.Id = uvs.UserId
WHERE
  u.Id IN (
    SELECT
      OwnerUserId
    FROM TopPosters
  )
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.WebsiteUrl,
  u.Location
ORDER BY
  u.Reputation DESC;
