WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 1 AS Level
    FROM Tags t
    WHERE t.Count > 1000
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, h.Level + 1
    FROM Tags t2
    JOIN PostLinks pl ON pl.PostId = t2.WikiPostId
    JOIN RecursiveTagHierarchy h ON pl.RelatedPostId = h.Id
    WHERE h.Level < 3
), UserBadgeCounts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
), PostAnswerStats AS (
    SELECT p.ParentId AS QuestionId,
           COUNT(p.Id) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore,
           MAX(p.Score) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
), UserActivityWindow AS (
    SELECT u.Id,
           COUNT(DISTINCT ph.PostId) AS EditedPosts,
           COUNT(DISTINCT c.PostId) AS CommentedPosts,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpvotesGiven,
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownvotesGiven
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate BETWEEN TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' AND TIMESTAMP '2024-10-01 12:34:56'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate BETWEEN TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' AND TIMESTAMP '2024-10-01 12:34:56'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate BETWEEN TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' AND TIMESTAMP '2024-10-01 12:34:56'
    GROUP BY u.Id
), TopQuestionsWithStats AS (
    SELECT q.Id,
           q.Title,
           q.Score,
           q.ViewCount,
           owner.Reputation AS OwnerReputation,
           ub.GoldBadges,
           ub.SilverBadges,
           ub.BronzeBadges,
           pas.AnswerCount,
           pas.AvgAnswerScore,
           pas.MaxAnswerScore,
           ua.EditedPosts,
           ua.CommentedPosts,
           ua.UpvotesGiven,
           ua.DownvotesGiven
    FROM Posts q
    LEFT JOIN Users owner ON q.OwnerUserId = owner.Id
    LEFT JOIN UserBadgeCounts ub ON q.OwnerUserId = ub.UserId
    LEFT JOIN PostAnswerStats pas ON q.Id = pas.QuestionId
    LEFT JOIN UserActivityWindow ua ON q.OwnerUserId = ua.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
      AND q.Score > 10
)
SELECT t.Level,
       t.TagName,
       t.Count AS TagQuestionCount,
       tqws.Title,
       tqws.Score AS QuestionScore,
       tqws.ViewCount,
       tqws.OwnerReputation,
       tqws.GoldBadges,
       tqws.SilverBadges,
       tqws.BronzeBadges,
       tqws.AnswerCount,
       tqws.AvgAnswerScore,
       tqws.MaxAnswerScore,
       COALESCE(tqws.EditedPosts,0) AS OwnerEditedPostsLastYear,
       COALESCE(tqws.CommentedPosts,0) AS OwnerCommentedPostsLastYear,
       COALESCE(tqws.UpvotesGiven,0) AS OwnerUpvotesGivenLastYear,
       COALESCE(tqws.DownvotesGiven,0) AS OwnerDownvotesGivenLastYear
FROM RecursiveTagHierarchy t
LEFT JOIN Posts pq ON pq.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN TopQuestionsWithStats tqws ON pq.Id = tqws.Id
WHERE tqws.Id IS NOT NULL
GROUP BY t.Level,
         t.TagName,
         t.Count,
         tqws.Title,
         tqws.Score,
         tqws.ViewCount,
         tqws.OwnerReputation,
         tqws.GoldBadges,
         tqws.SilverBadges,
         tqws.BronzeBadges,
         tqws.AnswerCount,
         tqws.AvgAnswerScore,
         tqws.MaxAnswerScore,
         tqws.EditedPosts,
         tqws.CommentedPosts,
         tqws.UpvotesGiven,
         tqws.DownvotesGiven,
         tqws.Id
ORDER BY t.Level, t.Count DESC, tqws.Score DESC
LIMIT 100;