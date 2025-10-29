WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Posts p
    JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM
      Comments c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS UpVoteCount,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS DownVoteCount,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id ELSE NULL END) AS FavoriteCount
    FROM
      Votes v
    JOIN
      VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeDistribution AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadgeCount,
      MAX(b.Date) AS LastBadgeDate
    FROM
      Badges b
    GROUP BY
      b.UserId
  ),
  UserEngagement AS (
    SELECT
      upa.OwnerUserId,
      COALESCE(upa.PostCount, 0) AS TotalPosts,
      COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
      COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
      COALESCE(uca.CommentCount, 0) AS TotalComments,
      COALESCE(uva.UpVoteCount, 0) AS TotalUpVotes,
      COALESCE(uva.DownVoteCount, 0) AS TotalDownVotes,
      COALESCE(uva.FavoriteCount, 0) AS TotalFavorites,
      COALESCE(ubd.GoldBadgeCount, 0) AS TotalGoldBadges,
      COALESCE(ubd.SilverBadgeCount, 0) AS TotalSilverBadges,
      COALESCE(ubd.BronzeBadgeCount, 0) AS TotalBronzeBadges,
      CASE
        WHEN upa.AvgScore > 50 THEN 'High Score'
        WHEN upa.AvgScore > 10 THEN 'Medium Score'
        ELSE 'Low Score'
      END AS ScoreCategory,
      CASE
        WHEN CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - COALESCE(upa.LastPostDate, uca.LastCommentDate, ubd.LastBadgeDate))) / 86400 AS INTEGER) < 30 THEN 'Active Recently'
        ELSE 'Inactive Longer'
      END AS ActivityStatus,
      upa.LastPostDate,
      uca.LastCommentDate,
      ubd.LastBadgeDate
    FROM
      UserPostActivity upa
    FULL OUTER JOIN
      UserCommentActivity uca
      ON upa.OwnerUserId = uca.UserId
    FULL OUTER JOIN
      UserVoteActivity uva
      ON COALESCE(upa.OwnerUserId, uca.UserId) = uva.UserId
    FULL OUTER JOIN
      UserBadgeDistribution ubd
      ON COALESCE(COALESCE(upa.OwnerUserId, uca.UserId), uva.UserId) = ubd.UserId
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.Views,
  u.UpVotes AS UserUpVotes,
  u.DownVotes AS UserDownVotes,
  ue.TotalPosts,
  ue.TotalQuestions,
  ue.TotalAnswers,
  ue.TotalComments,
  ue.TotalUpVotes,
  ue.TotalDownVotes,
  ue.TotalFavorites,
  ue.TotalGoldBadges,
  ue.TotalSilverBadges,
  ue.TotalBronzeBadges,
  ue.ScoreCategory,
  ue.ActivityStatus,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteType,
  COALESCE(LOWER(SUBSTRING(u.Location FROM 1 FOR (CASE WHEN POSITION(',' IN u.Location) = 0 THEN CHAR_LENGTH(u.Location) ELSE POSITION(',' IN u.Location)-1 END))), 'Unknown Location') AS PrimaryLocation,
  DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
  ROW_NUMBER() OVER (PARTITION BY ue.ScoreCategory ORDER BY u.CreationDate ASC) AS UserCreationOrderInCategory,
  ue.LastPostDate,
  ue.LastCommentDate,
  ue.LastBadgeDate
FROM
  Users u
LEFT JOIN
  UserEngagement ue
  ON u.Id = ue.OwnerUserId
WHERE
  u.Id > 0
  AND u.DisplayName IS NOT NULL
  AND LENGTH(TRIM(u.DisplayName)) > 0
  AND (COALESCE(ue.TotalPosts,0) + COALESCE(ue.TotalComments,0) > 5 OR COALESCE(ue.TotalUpVotes,0) > 10)
ORDER BY
  u.Reputation DESC,
  ue.LastPostDate DESC,
  ue.LastCommentDate DESC
LIMIT 100;