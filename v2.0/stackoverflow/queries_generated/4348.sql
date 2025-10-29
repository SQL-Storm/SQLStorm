-- {"query": "4348.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1463} 

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
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN Comments AS c
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
      (rp.UpVoteCount * 1.0 / NULLIF(rp.DownVoteCount, 0)) AS UpVoteDownVoteRatio,
      rp.CreationDate,
      (
        SELECT
          COUNT(ph.Id)
        FROM PostHistory AS ph
        WHERE
          ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS EditCount,
      COALESCE(u.DisplayName, 'Anonymous') AS OwnerDisplayName
    FROM RankedPosts AS rp
    LEFT JOIN Users AS u
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
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostEngagement AS pe
      ON p.Id = pe.PostId
    LEFT JOIN Badges AS b
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
    WHEN pe.CreationDate < DATE('now', '-1 year') THEN 'Older Post'
    ELSE 'Recent Post'
  END AS PostAgeCategory,
  CASE
    WHEN pe.OwnerReputation > 100000 THEN 'Elite User'
    WHEN pe.OwnerReputation > 10000 THEN 'Experienced User'
    ELSE 'Newer User'
  END AS OwnerExperienceLevel
FROM PostEngagement AS pe
FULL OUTER JOIN UserContribution AS uc
  ON pe.OwnerUserId = uc.UserId
WHERE
  pe.Score > 0 AND uc.Reputation > 5000 AND pe.TotalVotes > 10
ORDER BY
  pe.Score DESC,
  uc.Reputation DESC
LIMIT 100;
