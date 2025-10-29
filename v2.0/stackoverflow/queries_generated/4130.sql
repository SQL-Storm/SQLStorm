-- {"query": "4130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1618} 

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
      CASE WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) ELSE NULL END AS Tags,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_desc,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) AS rn_asc,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore,
      AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore
    FROM
      Posts AS p
      INNER JOIN PostTypes AS pt
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
      UserPostActivity AS upa
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
      Badges AS b
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
      Posts AS p
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Votes AS v
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
    WHEN pcav.UpVoteCount > pcav.DownVoteCount
    THEN 'Positive Sentiment'
    WHEN pcav.UpVoteCount < pcav.DownVoteCount
    THEN 'Negative Sentiment'
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
  COALESCE(up.TagName, 'No Tag Info') AS TagName,
  pl.LinkTypeId,
  CASE WHEN pl.LinkTypeId = 1 THEN 'Linked' WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Other Link Type' END AS LinkTypeDescription,
  cr.Name AS CloseReason
FROM
  HighReputationUsers AS hru
  LEFT JOIN UserContributions AS uc
    ON hru.Id = uc.OwnerUserId
  LEFT JOIN UserBadgeActivity AS uda
    ON hru.Id = uda.UserId
  LEFT JOIN UserPostActivity AS ua
    ON hru.Id = ua.OwnerUserId
  LEFT JOIN PostsWithCommentsAndVotes AS pcav
    ON ua.PostId = pcav.PostId
  LEFT JOIN PostLinks AS pl
    ON ua.PostId = pl.PostId
  LEFT JOIN Tags AS t
    ON T.TagName = ANY(string_to_array(REPLACE(REPLACE(ua.Tags, '<', ''), '>', ''), ''))
  LEFT JOIN PostHistory AS ph
    ON ua.PostId = ph.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes AS cr
    ON CAST(ph.Comment AS SMALLINT) = cr.Id
WHERE
  ua.rn_desc <= 10
  AND ua.PostScore > 0
  AND pcav.UpVoteCount > 5
  AND ua.PostCreationDate > '2023-01-01'
  AND SUBSTRING(ua.PostTypeName, 1, 5) <> 'TagWi'
ORDER BY
  hru.Reputation DESC,
  uc.TotalScore DESC,
  ua.PostScore DESC
LIMIT 100;
