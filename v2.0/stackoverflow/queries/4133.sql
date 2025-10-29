WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousDayScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextDayScore,
      SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore
    FROM Posts p
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  UserPostCounts AS (
    SELECT
      u.Id AS UserId,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(p.Score) AS TotalScore,
      MAX(p.CreationDate) AS LastPostDate,
      u.DisplayName,
      u.Reputation
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostsWithComments AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      c.Id AS CommentId,
      c.UserId AS CommentUserId,
      c.CreationDate AS CommentCreationDate,
      c.Score AS CommentScore,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY c.CreationDate) AS CommentSequence
    FROM Posts p
    JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1
  ),
  PostInteractions AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT v.UserId) AS DistinctVoters,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Posts p
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id
  ),
  AllPostData AS (
    SELECT
      rp.PostId,
      rp.PostTypeId,
      pt.Name AS PostTypeName,
      rp.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      rp.PostCreationDate,
      rp.PostScore,
      rp.PostViewCount,
      rp.AnswerCount AS QuestionAnswerCount,
      rp.CommentCount AS QuestionCommentCount,
      rp.FavoriteCount AS QuestionFavoriteCount,
      COALESCE(pi.DistinctVoters, 0) AS TotalDistinctVoters,
      COALESCE(pi.UpVotes, 0) AS TotalUpVotes,
      COALESCE(pi.DownVotes, 0) AS TotalDownVotes,
      COALESCE(pi.FavoriteVotes, 0) AS TotalFavoriteVotes,
      rp.rn_desc,
      rp.rn_asc,
      rp.PreviousDayScore,
      rp.NextDayScore,
      rp.RunningTotalScore,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CAST(EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, p.CreationDate) - p.CreationDate)) / 86400 AS INTEGER) AS DaysToClose,
      p.Title,
      p.Tags,
      (
        SELECT
          STRING_AGG(c.Text, '; ')
        FROM Comments c
        WHERE
          c.PostId = rp.PostId
          AND c.UserId = rp.OwnerUserId
      ) AS OwnerComments,
      (
        SELECT
          COUNT(*)
        FROM PostLinks pl
        WHERE
          pl.PostId = rp.PostId
          OR pl.RelatedPostId = rp.PostId
      ) AS RelatedPostLinks,
      rp.PreviousDayScore AS PreviousDayScore_out,
      rp.NextDayScore AS NextDayScore_out,
      rp.RunningTotalScore AS RunningTotalScore_out
    FROM RankedPosts rp
    JOIN PostTypes pt
      ON rp.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON rp.OwnerUserId = u.Id
    LEFT JOIN PostInteractions pi
      ON rp.PostId = pi.PostId
    LEFT JOIN Posts p
      ON rp.PostId = p.Id
    WHERE
      rp.rn_desc <= 100
    GROUP BY
      rp.PostId,
      rp.PostTypeId,
      pt.Name,
      rp.OwnerUserId,
      u.DisplayName,
      u.Reputation,
      rp.PostCreationDate,
      rp.PostScore,
      rp.PostViewCount,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      pi.DistinctVoters,
      pi.UpVotes,
      pi.DownVotes,
      pi.FavoriteVotes,
      rp.rn_desc,
      rp.rn_asc,
      rp.PreviousDayScore,
      rp.NextDayScore,
      rp.RunningTotalScore,
      p.ClosedDate,
      p.CreationDate,
      p.Title,
      p.Tags,
      rp.PostId,
      rp.PreviousDayScore,
      rp.NextDayScore,
      rp.RunningTotalScore
  )
SELECT
  apd.PostId,
  apd.PostTypeName,
  apd.OwnerDisplayName,
  apd.OwnerReputation,
  apd.PostCreationDate,
  apd.PostScore,
  apd.PostViewCount,
  apd.QuestionAnswerCount,
  apd.QuestionCommentCount,
  apd.QuestionFavoriteCount,
  apd.TotalDistinctVoters,
  apd.TotalUpVotes,
  apd.TotalDownVotes,
  apd.TotalFavoriteVotes,
  apd.rn_desc,
  apd.rn_asc,
  apd.PreviousDayScore_out AS PreviousDayScore,
  apd.NextDayScore_out AS NextDayScore,
  apd.RunningTotalScore_out AS RunningTotalScore,
  apd.IsClosed,
  apd.DaysToClose,
  apd.Title,
  apd.Tags,
  apd.OwnerComments,
  apd.RelatedPostLinks,
  upc.QuestionCount AS UserTotalQuestions,
  upc.AnswerCount AS UserTotalAnswers,
  upc.TotalScore AS UserTotalScore,
  upc.LastPostDate AS UserLastPostDate,
  CASE
    WHEN apd.PostScore > 100 AND apd.TotalDistinctVoters > 50 THEN 'Highly Engaged Post'
    WHEN apd.PostScore < 0 AND apd.IsClosed = 1 THEN 'Closed Negative Score Post'
    WHEN apd.PostCreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days') AND apd.QuestionAnswerCount = 0 THEN 'Old Unanswered Question'
    WHEN apd.PostViewCount > 10000 AND apd.OwnerReputation > 5000 THEN 'Popular High Rep Question'
    ELSE 'Standard Post'
  END AS PostEngagementCategory,
  CASE
    WHEN apd.Title LIKE '%SQL%' OR apd.Tags LIKE '%[sql]%' THEN 'SQL Related'
    WHEN apd.Title LIKE '%Python%' OR apd.Tags LIKE '%[python]%' THEN 'Python Related'
    WHEN apd.Title LIKE '%Java%' OR apd.Tags LIKE '%[java]%' THEN 'Java Related'
    ELSE 'Other Technology'
  END AS TechnologyCategory,
  CASE
    WHEN apd.OwnerUserId IS NULL THEN 'Community Owned'
    WHEN apd.OwnerReputation < 100 THEN 'New User'
    WHEN apd.OwnerReputation BETWEEN 100 AND 1000 THEN 'Intermediate User'
    WHEN apd.OwnerReputation > 1000 THEN 'Experienced User'
    ELSE 'Unknown User Status'
  END AS UserExperienceLevel
FROM AllPostData apd
LEFT JOIN UserPostCounts upc
  ON apd.OwnerUserId = upc.UserId
WHERE
  apd.PostTypeName IN ('Question', 'Answer')
  AND apd.PostCreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
  AND (apd.OwnerReputation >= 1 OR apd.OwnerUserId IS NULL)
  AND (CASE WHEN apd.Tags IS NULL THEN '' ELSE SUBSTR(apd.Tags, 2, LENGTH(apd.Tags)) END) NOT LIKE '%,%'
ORDER BY
  apd.PostScore DESC,
  apd.PostCreationDate DESC
LIMIT 1000;