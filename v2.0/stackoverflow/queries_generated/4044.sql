-- {"query": "4044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1452} 

WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Id IS NOT NULL THEN a.Score ELSE 0 END) AS TotalAnswerScore,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN c.Id IS NOT NULL THEN c.Score ELSE 0 END) AS TotalCommentScore,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(u.Reputation) AS MaxReputation,
      AVG(u.Views) AS AvgUserViews,
      DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM
      Users AS u
    LEFT JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN
      Posts AS a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
      Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN
      Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.Views
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      pt.Name AS PostType,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
      SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS PostCreationRank
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN
      Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN
      PostLinks AS pl
      ON p.Id = pl.PostId
    WHERE
      p.Score > 10
    GROUP BY
      p.Id,
      p.Title,
      pt.Name,
      p.CreationDate
  ),
  UserPostSummary AS (
    SELECT
      ua.UserId,
      ua.DisplayName,
      ua.ReputationRank,
      ua.MaxReputation,
      ua.AvgUserViews,
      COUNT(DISTINCT pe.PostId) AS HighlyEngagedPostCount,
      SUM(pe.UpVoteCount) AS TotalUpvotesOnEngagedPosts,
      AVG(pe.CommentCount) AS AvgCommentsOnEngagedPosts,
      MAX(pe.PostCreationRank) AS LatestPostRank
    FROM
      UserActivity AS ua
    LEFT JOIN
      PostEngagement AS pe
      ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pe.PostId)
    GROUP BY
      ua.UserId,
      ua.DisplayName,
      ua.ReputationRank,
      ua.MaxReputation,
      ua.AvgUserViews
  )
SELECT
  ups.UserId,
  ups.DisplayName,
  ups.ReputationRank,
  ups.MaxReputation,
  ups.AvgUserViews,
  ups.HighlyEngagedPostCount,
  ups.TotalUpvotesOnEngagedPosts,
  ups.AvgCommentsOnEngagedPosts,
  pe.Title AS MostRecentHighlyEngagedPostTitle,
  CASE
    WHEN ups.LatestPostRank <= 100 THEN 'Top 100'
    WHEN ups.LatestPostRank <= 500 THEN 'Top 500'
    ELSE 'Beyond Top 500'
  END AS RecentPostTier,
  CASE
    WHEN ups.TotalUpvotesOnEngagedPosts > 1000 THEN 'High Voter'
    WHEN ups.TotalUpvotesOnEngagedPosts > 500 THEN 'Medium Voter'
    ELSE 'Low Voter'
  END AS VoterCategory,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalAnswerScore,
  ua.CommentCount AS UserTotalComments,
  ua.TotalCommentScore AS UserTotalCommentScore,
  ua.BadgeCount,
  CASE
    WHEN ua.BadgeCount = 0 THEN 'No Badges'
    WHEN ua.BadgeCount BETWEEN 1 AND 5 THEN 'Few Badges'
    ELSE 'Many Badges'
  END AS BadgeStatus,
  COALESCE(pht.Name, 'Unknown') AS LastPostHistoryAction,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags) - 2) AS FirstTag
FROM
  UserPostSummary AS ups
JOIN
  UserActivity AS ua
  ON ups.UserId = ua.UserId
JOIN
  PostEngagement AS pe
  ON pe.PostId = (
    SELECT
      Id
    FROM
      Posts
    WHERE
      OwnerUserId = ups.UserId
    ORDER BY
      CreationDate DESC
    LIMIT 1
  )
LEFT JOIN
  Posts AS p
  ON pe.PostId = p.Id
LEFT JOIN
  PostHistory AS ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
LEFT JOIN
  PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
WHERE
  ua.MaxReputation > 5000
ORDER BY
  ups.TotalUpvotesOnEngagedPosts DESC,
  ups.HighlyEngagedPostCount DESC
LIMIT 100;
