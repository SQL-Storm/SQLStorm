-- {"query": "18091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1169} 

WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserCommentCounts AS (
    SELECT
      UserId,
      COUNT(Id) AS CommentCount
    FROM Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  UserVoteCounts AS (
    SELECT
      UserId,
      COUNT(Id) AS VoteCount,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Votes
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      COUNT(Id) AS BadgeCount,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Badges
    GROUP BY
      UserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      UpVotes AS TotalUpvotesFromUser,
      DownVotes AS TotalDownvotesFromUser,
      Views AS TotalViewsOnProfile,
      COALESCE(upc.UpVoteCount, 0) AS GivenUpvotes,
      COALESCE(uvc.DownVoteCount, 0) AS GivenDownvotes,
      COALESCE(p.PostCount, 0) AS TotalPosts,
      COALESCE(c.CommentCount, 0) AS TotalComments,
      COALESCE(b.BadgeCount, 0) AS TotalBadges,
      COALESCE(b.GoldBadgeCount, 0) AS GoldBadges,
      COALESCE(b.SilverBadgeCount, 0) AS SilverBadges,
      COALESCE(b.BronzeBadgeCount, 0) AS BronzeBadges,
      CASE
        WHEN DATEDIFF(day, CreationDate, GETDATE()) > 365 THEN 'Experienced'
        ELSE 'New'
      END AS UserExperience
    FROM Users
    LEFT JOIN UserPostCounts p
      ON Users.Id = p.OwnerUserId
    LEFT JOIN UserCommentCounts c
      ON Users.Id = c.UserId
    LEFT JOIN UserBadgeCounts b
      ON Users.Id = b.UserId
    LEFT JOIN UserVoteCounts upc
      ON Users.Id = upc.UserId AND upc.VoteTypeId = 2
    LEFT JOIN UserVoteCounts uvc
      ON Users.Id = uvc.UserId AND uvc.VoteTypeId = 3
    WHERE
      Reputation > 10000
  ),
  PopularQuestions AS (
    SELECT
      Id,
      Title,
      OwnerUserId,
      CreationDate,
      Score,
      ViewCount,
      AnswerCount,
      FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY Score DESC, FavoriteCount DESC) AS QuestionRank
    FROM Posts
    WHERE
      PostTypeId = 1
      AND ClosedDate IS NULL
      AND Score > 100
  )
SELECT
  pq.Title AS QuestionTitle,
  hr.DisplayName AS AuthorDisplayName,
  hr.Reputation,
  hr.TotalPosts,
  hr.TotalComments,
  hr.TotalBadges,
  hr.GoldBadges,
  hr.SilverBadges,
  hr.BronzeBadges,
  pq.Score AS QuestionScore,
  pq.ViewCount AS QuestionViewCount,
  pq.AnswerCount AS QuestionAnswerCount,
  pq.FavoriteCount AS QuestionFavoriteCount,
  pq.QuestionRank,
  LOWER(SUBSTRING(hr.DisplayName, 1, 3)) AS DisplayNamePrefix,
  CASE
    WHEN hr.UserExperience = 'Experienced' AND hr.Reputation > 50000 THEN 'Highly Experienced Power User'
    WHEN hr.UserExperience = 'Experienced' THEN 'Experienced User'
    ELSE 'Newer User'
  END AS UserTier,
  COALESCE(LENGTH(hr.AboutMe), 0) AS AboutMeLength,
  CASE
    WHEN hr.WebsiteUrl IS NOT NULL AND hr.WebsiteUrl <> '' THEN 'HasWebsite'
    ELSE 'NoWebsite'
  END AS HasWebsiteIndicator
FROM
  PopularQuestions pq
JOIN
  HighReputationUsers hr
  ON pq.OwnerUserId = hr.Id
WHERE
  pq.QuestionRank BETWEEN 1 AND 100
  AND hr.TotalPosts > 50
  AND hr.GivenUpvotes > hr.GivenDownvotes * 2
  AND hr.UserExperience <> 'New'
  AND hr.DisplayName NOT LIKE '%[Bot]%'
ORDER BY
  hr.Reputation DESC,
  pq.QuestionRank ASC;
