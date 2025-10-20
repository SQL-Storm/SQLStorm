WITH RECURSIVE UserActivityCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        CAST(COUNT(p.Id) AS INTEGER) AS TotalPosts,
        CAST(COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS INTEGER) AS Questions,
        CAST(COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS INTEGER) AS Answers,
        (SELECT MAX(px.Score)
         FROM Posts px
         WHERE px.OwnerUserId = u.Id) AS MaxPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location

    UNION ALL

    SELECT
        u2.Id AS UserId,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        u2.LastAccessDate,
        u2.Location,
        CAST(ua.TotalPosts - COALESCE(s.UpAnswerPosts, 0) AS INTEGER) AS TotalPosts,
        CAST(ua.Questions - COALESCE(s.UpQuestionPosts, 0) AS INTEGER) AS Questions,
        CAST(ua.Answers - COALESCE(s.UpAnswerPosts, 0) AS INTEGER) AS Answers,
        ua.MaxPostScore
    FROM UserActivityCTE ua
    JOIN Users u2 ON u2.Id = ua.UserId
    LEFT JOIN (
        SELECT OwnerUserId,
               COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS UpQuestionPosts,
               COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS UpAnswerPosts
        FROM Posts
        GROUP BY OwnerUserId
    ) s ON s.OwnerUserId = u2.Id
)
SELECT *
FROM UserActivityCTE;