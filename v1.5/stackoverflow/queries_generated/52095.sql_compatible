SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(question_stats.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(answer_stats.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(badge_counts.GoldCount, 0) AS GoldBadges,
    COALESCE(badge_counts.SilverCount, 0) AS SilverBadges,
    COALESCE(badge_counts.BronzeCount, 0) AS BronzeBadges,
    COALESCE(vote_summary.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(vote_summary.DownvotesReceived, 0) AS DownvotesReceived,
    COALESCE(ph_summary.EditsMade, 0) AS EditsMade,
    COALESCE(comment_counts.TotalCommentsPosted, 0) AS TotalCommentsPosted,
    CASE WHEN COALESCE(answer_stats.TotalAnswerScore, 0) > 0 THEN 
        CAST(COALESCE(question_stats.TotalQuestionScore, 0) + COALESCE(answer_stats.TotalAnswerScore, 0) AS DECIMAL) / NULLIF(COALESCE(answer_stats.TotalAnswerScore, 0), 0)
    ELSE 0 END AS ScoreRatio,
    ROW_NUMBER() OVER (ORDER BY (COALESCE(question_stats.TotalQuestionScore, 0) + COALESCE(answer_stats.TotalAnswerScore, 0)) DESC) AS Rank
FROM Users u
LEFT JOIN (
    SELECT OwnerUserId, SUM(Score) AS TotalQuestionScore
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= '2020-01-01'
    GROUP BY OwnerUserId
) question_stats ON u.Id = question_stats.OwnerUserId
LEFT JOIN (
    SELECT OwnerUserId, SUM(Score) AS TotalAnswerScore, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= '2020-01-01'
    GROUP BY OwnerUserId
) answer_stats ON u.Id = answer_stats.OwnerUserId
LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges
    WHERE Date >= '2020-01-01'
    GROUP BY UserId
) badge_counts ON u.Id = badge_counts.UserId
LEFT JOIN (
    SELECT p.OwnerUserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM Posts p
    INNER JOIN Votes v ON p.Id = v.PostId
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY p.OwnerUserId
) vote_summary ON u.Id = vote_summary.OwnerUserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS EditsMade
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6) AND CreationDate >= '2020-01-01'
    GROUP BY UserId
) ph_summary ON u.Id = ph_summary.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalCommentsPosted
    FROM Comments
    WHERE CreationDate >= '2020-01-01'
    GROUP BY UserId
) comment_counts ON u.Id = comment_counts.UserId
WHERE u.CreationDate >= '2015-01-01' 
  AND u.Reputation > 100
ORDER BY Rank
LIMIT 100;