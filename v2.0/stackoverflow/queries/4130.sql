WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      pt.Name AS PostTypeName,
      CASE WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2) ELSE NULL END AS Tags,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_desc,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) AS rn_asc,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore,
      AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore
    FROM
      Posts p
      INNER JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  UserContributions AS (
    SELECT
      upa.OwnerUserId,
      COUNT(upa.PostId) AS TotalPosts,
      SUM(CASE WHEN upa.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN upa.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      AVG(upa.PostScore) AS AvgPostScore,
      SUM(upa.PostScore) AS TotalScore,
      MAX(upa.PostCreationDate) AS LatestPostDate,
      MIN(upa.PostCreationDate) AS EarliestPostDate,
      COUNT(DISTINCT upa.Tags) AS DistinctTagCount
    FROM
      UserPostActivity upa
    GROUP BY
      upa.OwnerUserId
  ),
  UserBadgeActivity AS (
    SELECT
      b.UserId,
      COUNT(b.Id) AS TotalBadges,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
      Badges b
    WHERE
      b.UserId IN (
        SELECT
          Id
        FROM
          HighReputationUsers
      )
    GROUP BY
      b.UserId
  ),
  PostsWithCommentsAndVotes AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      COUNT(c.Id) AS CommentCountForPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM
      Posts p
      LEFT JOIN Comments c
        ON p.Id = c.PostId
      LEFT JOIN Votes v
        ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.ClosedDate
  )
SELECT
  hru.DisplayName AS UserName,
  hru.Reputation,
  uc.TotalPosts,
  uc.TotalQuestions,
  uc.TotalAnswers,
  uc.AvgPostScore,
  uc.TotalScore,
  uda.TotalBadges,
  uda.GoldBadges,
  uda.SilverBadges,
  uda.BronzeBadges,
  pcav.CommentCountForPost,
  pcav.UpVoteCount,
  pcav.DownVoteCount,
  pcav.IsClosed,
  CASE
    WHEN pcav.UpVoteCount > pcav.DownVoteCount THEN 'Positive Sentiment'
    WHEN pcav.UpVoteCount < pcav.DownVoteCount THEN 'Negative Sentiment'
    ELSE 'Neutral Sentiment'
  END AS VoteSentiment,
  ua.rn_asc AS FirstPostOrder,
  ua.rn_desc AS LastPostOrder,
  ua.PostTypeName,
  ua.Tags,
  ua.PreviousPostScore,
  ua.NextPostScore,
  ua.RunningTotalScore,
  ua.AvgUserPostScore,
  COALESCE(t.TagName, 'No Tag Info') AS TagName,
  pl.LinkTypeId,
  CASE WHEN pl.LinkTypeId = 1 THEN 'Linked' WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Other Link Type' END AS LinkTypeDescription,
  cr.Name AS CloseReason,
  ua.PostId,
  ua.PostScore,
  ua.PostCreationDate
FROM
  HighReputationUsers hru
  LEFT JOIN UserContributions uc
    ON hru.Id = uc.OwnerUserId
  LEFT JOIN UserBadgeActivity uda
    ON hru.Id = uda.UserId
  LEFT JOIN UserPostActivity ua
    ON hru.Id = ua.OwnerUserId
  LEFT JOIN PostsWithCommentsAndVotes pcav
    ON ua.PostId = pcav.PostId
  LEFT JOIN PostLinks pl
    ON ua.PostId = pl.PostId
  LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(REPLACE(REPLACE(COALESCE(ua.Tags, ''), '<', ''), '>', ''), E'\\s*,\\s*') AS TagName
  ) t ON true
  LEFT JOIN PostHistory ph
    ON ua.PostId = ph.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes cr
    ON CAST(ph.Comment AS SMALLINT) = cr.Id
WHERE
  ua.rn_desc <= 10
  AND ua.PostScore > 0
  AND pcav.UpVoteCount > 5
  AND ua.PostCreationDate > DATE '2023-01-01'
  AND SUBSTRING(ua.PostTypeName FROM 1 FOR 5) <> 'TagWi'
GROUP BY
  hru.DisplayName,
  hru.Reputation,
  uc.TotalPosts,
  uc.TotalQuestions,
  uc.TotalAnswers,
  uc.AvgPostScore,
  uc.TotalScore,
  uda.TotalBadges,
  uda.GoldBadges,
  uda.SilverBadges,
  uda.BronzeBadges,
  pcav.CommentCountForPost,
  pcav.UpVoteCount,
  pcav.DownVoteCount,
  pcav.IsClosed,
  ua.rn_asc,
  ua.rn_desc,
  ua.PostTypeName,
  ua.Tags,
  ua.PreviousPostScore,
  ua.NextPostScore,
  ua.RunningTotalScore,
  ua.AvgUserPostScore,
  t.TagName,
  pl.LinkTypeId,
  cr.Name,
  ua.PostId,
  ua.PostScore,
  ua.PostCreationDate
ORDER BY
  hru.Reputation DESC,
  uc.TotalScore DESC,
  ua.PostScore DESC
LIMIT 100;