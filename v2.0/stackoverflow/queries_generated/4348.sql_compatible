WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.ViewCount,
      p.FavoriteCount,
      p.CreationDate,
      p.ClosedDate,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT c.Id) AS CommentCount_Actual,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.ViewCount,
      p.FavoriteCount,
      p.CreationDate,
      p.ClosedDate,
      u.Reputation
  ),
  PostEngagement AS (
    SELECT
      rp.PostId,
      rp.OwnerUserId,
      rp.PostTypeId,
      rp.Score,
      rp.UpVoteCount,
      rp.DownVoteCount,
      rp.CommentCount_Actual,
      rp.ViewCount,
      rp.FavoriteCount,
      rp.OwnerReputation,
      rp.IsClosed,
      CASE
        WHEN rp.Score > 0 AND rp.UpVoteCount > rp.DownVoteCount * 2 THEN 'Highly Rated'
        WHEN rp.Score < 0 AND rp.DownVoteCount > rp.UpVoteCount * 2 THEN 'Poorly Rated'
        WHEN rp.CommentCount_Actual > 50 THEN 'High Engagement'
        WHEN rp.ViewCount > 10000 THEN 'High Traffic'
        WHEN rp.IsClosed = 1 THEN 'Closed'
        ELSE 'Standard'
      END AS EngagementLevel,
      (rp.UpVoteCount + rp.DownVoteCount) AS TotalVotes,
      (CASE WHEN rp.DownVoteCount = 0 THEN NULL ELSE rp.UpVoteCount * 1.0 / rp.DownVoteCount END) AS UpVoteDownVoteRatio,
      rp.CreationDate,
      (
        SELECT
          COUNT(ph.Id)
        FROM PostHistory ph
        WHERE
          ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS EditCount,
      COALESCE(u.DisplayName, 'Anonymous') AS OwnerDisplayName
    FROM RankedPosts rp
    LEFT JOIN Users u
      ON rp.OwnerUserId = u.Id
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS PostsCreated,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      AVG(pe.Score) AS AvgPostScore,
      SUM(pe.UpVoteCount) AS TotalUpvotesGiven,
      SUM(pe.DownVoteCount) AS TotalDownvotesGiven,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      MAX(u.CreationDate) AS LastUserActivity
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostEngagement pe
      ON p.Id = pe.PostId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  )
SELECT
  pe.PostId,
  pe.OwnerDisplayName,
  pe.EngagementLevel,
  pe.Score,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.CommentCount_Actual,
  pe.ViewCount,
  pe.FavoriteCount,
  pe.OwnerReputation,
  pe.TotalVotes,
  pe.UpVoteDownVoteRatio,
  pe.CreationDate,
  pe.EditCount,
  uc.UserId,
  uc.DisplayName AS ContributorDisplayName,
  uc.Reputation AS ContributorReputation,
  uc.PostsCreated,
  uc.QuestionsAsked,
  uc.AnswersGiven,
  uc.AvgPostScore,
  uc.TotalUpvotesGiven,
  uc.TotalDownvotesGiven,
  uc.BadgesEarned,
  uc.LastUserActivity,
  CASE
    WHEN pe.Score > uc.AvgPostScore * 1.5 THEN 'Above Average Contributor'
    WHEN pe.Score < uc.AvgPostScore * 0.5 THEN 'Below Average Contributor'
    ELSE 'Average Contributor'
  END AS ContributorPerformance,
  CASE
    WHEN pe.IsClosed = 1 THEN 'Closed Post'
    WHEN pe.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Older Post'
    ELSE 'Recent Post'
  END AS PostAgeCategory,
  CASE
    WHEN pe.OwnerReputation > 100000 THEN 'Elite User'
    WHEN pe.OwnerReputation > 10000 THEN 'Experienced User'
    ELSE 'Newer User'
  END AS OwnerExperienceLevel
FROM PostEngagement pe
FULL OUTER JOIN UserContribution uc
  ON pe.OwnerUserId = uc.UserId
WHERE
  pe.Score > 0 AND uc.Reputation > 5000 AND pe.TotalVotes > 10
ORDER BY
  pe.Score DESC,
  uc.Reputation DESC
LIMIT 100;