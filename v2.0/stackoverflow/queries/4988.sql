WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      (
        SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id
      ) AS ActualCommentCount,
      (
        SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVoteCount,
      (
        SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3
      ) AS DownVoteCount,
      (
        SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM
      Posts p
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadges,
      (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
      ) AS EditedPostCount,
      MAX(pe.PostCreationDate) AS LastPostDate,
      MAX(pe.UserPostRank) AS MaxUserPostRank
    FROM
      Users u
    LEFT JOIN
      PostEngagement pe
      ON u.Id = pe.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  COALESCE(ua.DisplayName, 'Community') AS UserDisplayName,
  pe.Title AS PostTitle,
  pt.Name AS PostTypeName,
  pe.PostScore,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.ActualCommentCount,
  pe.FavoriteCount,
  pe.AnswerCount,
  pe.DuplicateLinkCount,
  pe.UserPostRank,
  ua.Reputation,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.MaxUserPostRank AS UserPostRank,
  ua.EditedPostCount,
  ua.UserViews,
  ua.UserUpVotes,
  ua.UserDownVotes,
  ua.LastPostDate,
  CASE
    WHEN pe.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN pe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CAST(
    (EXTRACT(EPOCH FROM (COALESCE(pe.ClosedDate, pe.PostCreationDate) - pe.PostCreationDate)) / 60)
    AS INTEGER
  ) AS TimeToCloseOrPostAgeMinutes,
  CASE
    WHEN ua.DisplayName IS NULL THEN 'Anonymous'
    WHEN ua.Reputation > 50000 THEN 'High Reputation'
    WHEN ua.Reputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationBracket,
  LOWER(SUBSTRING(pe.Title FROM 1 FOR 3)) AS TitlePrefix,
  CASE
    WHEN COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 10 THEN 'Top 10 Posts'
    WHEN COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 50 THEN 'Top 50 Posts'
    ELSE 'Other Posts'
  END AS UserPostRankingCategory
FROM
  PostEngagement pe
LEFT JOIN
  UserActivity ua
  ON pe.OwnerUserId = ua.UserId
LEFT JOIN
  PostTypes pt
  ON pe.PostTypeId = pt.Id
WHERE
  pe.PostTypeId = 1
  AND pe.PostScore > 0
  AND COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 100
  AND pe.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
UNION ALL
SELECT
  COALESCE(ua.DisplayName, 'Community') AS UserDisplayName,
  pe.Title AS PostTitle,
  pt.Name AS PostTypeName,
  pe.PostScore,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.ActualCommentCount,
  pe.FavoriteCount,
  pe.AnswerCount,
  pe.DuplicateLinkCount,
  pe.UserPostRank,
  ua.Reputation,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.MaxUserPostRank AS UserPostRank,
  ua.EditedPostCount,
  ua.UserViews,
  ua.UserUpVotes,
  ua.UserDownVotes,
  ua.LastPostDate,
  CASE
    WHEN pe.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN pe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CAST(
    (EXTRACT(EPOCH FROM (COALESCE(pe.ClosedDate, pe.PostCreationDate) - pe.PostCreationDate)) / 60)
    AS INTEGER
  ) AS TimeToCloseOrPostAgeMinutes,
  CASE
    WHEN ua.DisplayName IS NULL THEN 'Anonymous'
    WHEN ua.Reputation > 50000 THEN 'High Reputation'
    WHEN ua.Reputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationBracket,
  LOWER(SUBSTRING(pe.Title FROM 1 FOR 3)) AS TitlePrefix,
  CASE
    WHEN COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 10 THEN 'Top 10 Posts'
    WHEN COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 50 THEN 'Top 50 Posts'
    ELSE 'Other Posts'
  END AS UserPostRankingCategory
FROM
  PostEngagement pe
LEFT JOIN
  UserActivity ua
  ON pe.OwnerUserId = ua.UserId
LEFT JOIN
  PostTypes pt
  ON pe.PostTypeId = pt.Id
WHERE
  pe.PostTypeId = 2
  AND pe.PostScore > 0
  AND COALESCE(ua.MaxUserPostRank, pe.UserPostRank) <= 100
  AND pe.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31';