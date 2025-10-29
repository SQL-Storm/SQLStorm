WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForType,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
      (
        SELECT
          COUNT(*)
        FROM Comments c
        WHERE
          c.PostId = p.Id
      ) AS CommentCountSubquery,
      (
        SELECT
          STRING_AGG(CAST(v.VoteTypeId AS VARCHAR), ',' ORDER BY v.VoteTypeId)
        FROM Votes v
        WHERE
          v.PostId = p.Id
      ) AS VoteTypesForPost
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score > 0
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
  ),
  UserPostActivity AS (
    SELECT
      rp.OwnerUserId,
      COUNT(rp.PostId) AS TotalPosts,
      SUM(rp.Score) AS TotalScore,
      AVG(rp.Score) AS AvgScore,
      SUM(rp.AnswerCount) AS TotalAnswers,
      SUM(rp.CommentCount) AS TotalComments,
      SUM(rp.FavoriteCount) AS TotalFavorites,
      SUM(rp.ViewCount) AS TotalViews,
      MAX(rp.CreationDate) AS LastPostDate
    FROM RankedPosts rp
    GROUP BY
      rp.OwnerUserId
  ),
  TopUsers AS (
    SELECT
      upa.OwnerUserId,
      upa.TotalPosts,
      upa.TotalScore,
      upa.AvgScore,
      u.Reputation,
      u.DownVotes,
      u.UpVotes,
      (u.UpVotes - u.DownVotes) AS NetVotes,
      CASE
        WHEN u.DisplayName ~ '[^a-zA-Z0-9]' THEN 'Has Special Chars'
        ELSE 'No Special Chars'
      END AS DisplayNameCharType,
      CASE
        WHEN LENGTH(COALESCE(u.AboutMe, '')) > 100 THEN 'Long About Me'
        WHEN LENGTH(COALESCE(u.AboutMe, '')) BETWEEN 50 AND 100 THEN 'Medium About Me'
        ELSE 'Short About Me'
      END AS AboutMeLength,
      CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        ELSE 'Has Website'
      END AS WebsiteStatus,
      (u.DisplayName || ' (' || u.Id || ')') AS UserIdentifier
    FROM UserPostActivity upa
    JOIN Users u
      ON upa.OwnerUserId = u.Id
    WHERE
      upa.TotalPosts > 10
      AND u.Reputation > 1000
  ),
  PostVoteSummary AS (
    SELECT
      p.Id AS PostId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount
    FROM Posts p
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id
  )
SELECT
  rp.PostId,
  rp.OwnerUserId,
  rp.PostTypeId,
  rp.Score,
  rp.ScoreRank,
  rp.AvgScoreForType,
  rp.PreviousScore,
  rp.NextScore,
  rp.CommentCountSubquery,
  rp.VoteTypesForPost,
  tu.UserIdentifier,
  tu.Reputation,
  tu.DisplayNameCharType,
  tu.AboutMeLength,
  tu.WebsiteStatus,
  pvs.UpVoteCount,
  pvs.DownVoteCount,
  pvs.FavoriteCount,
  CASE
    WHEN rp.Score > rp.AvgScoreForType * 1.5 THEN 'High Score'
    WHEN rp.Score < rp.AvgScoreForType * 0.5 THEN 'Low Score'
    ELSE 'Average Score'
  END AS ScoreCategory,
  COALESCE(rp.AnswerCount, 0) AS NonNullAnswerCount,
  CASE
    WHEN rp.FavoriteCount > 10 AND rp.Score > 50 THEN 'Highly Faved & Scored'
    WHEN rp.CommentCountSubquery > 5 AND rp.Score > 10 THEN 'Highly Commented & Scored'
    ELSE 'Standard Activity'
  END AS ActivityLevel,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp.PostId
        AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Link'
    ELSE 'Not a Duplicate Link'
  END AS DuplicateStatus,
  (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) * 100 AS ScorePerViewPercentage,
  rp.CreationDate
FROM RankedPosts rp
JOIN TopUsers tu
  ON rp.OwnerUserId = tu.OwnerUserId
LEFT JOIN PostVoteSummary pvs
  ON rp.PostId = pvs.PostId
WHERE
  rp.ScoreRank <= 100
  AND rp.PostTypeId IN (1, 2)
  AND (rp.PreviousScore IS NULL OR rp.NextScore IS NULL OR rp.Score > rp.PreviousScore)
ORDER BY
  rp.PostTypeId,
  rp.ScoreRank;