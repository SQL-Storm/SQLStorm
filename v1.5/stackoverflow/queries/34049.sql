WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users AS u
    LEFT JOIN Badges AS b ON b.UserId = u.Id AND b.Class = 1
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Id) >= 3
), RecentHotQuestions AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, ph.CreationDate AS HotDate
    FROM Posts AS p
    JOIN PostHistory AS ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 52
    WHERE p.PostTypeId = 1
      AND ph.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY
), UserActivity AS (
    SELECT u.Id AS UserId,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
           COUNT(DISTINCT c.Id) AS CommentsMade,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived
    FROM Users AS u
    LEFT JOIN Posts AS p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON c.UserId = u.Id
    LEFT JOIN Votes AS v ON v.PostId = p.Id
    GROUP BY u.Id
), TagQuestionStats AS (
    SELECT t.TagName,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           AVG(p.Score) AS AvgScore,
           MAX(p.ViewCount) AS MaxViewCount
    FROM Tags AS t
    JOIN Posts AS p ON p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 100
), QuestionLinkCounts AS (
    SELECT p.Id AS QuestionId,
           COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinks,
           COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedPosts
    FROM Posts AS p
    LEFT JOIN PostLinks AS pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes AS lt ON lt.Id = pl.LinkTypeId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
), TopHotQuestionDetails AS (
    SELECT rhq.Id, rhq.Title, rhq.CreationDate, rhq.OwnerUserId, rhq.Score, rhq.HotDate,
           u.DisplayName AS OwnerName,
           ul.DuplicateLinks, ul.LinkedPosts,
           ta.QuestionCount, ta.AvgScore, ta.MaxViewCount,
           ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.UpVotesReceived, ua.DownVotesReceived
    FROM RecentHotQuestions AS rhq
    LEFT JOIN Users AS u ON u.Id = rhq.OwnerUserId
    LEFT JOIN QuestionLinkCounts AS ul ON ul.QuestionId = rhq.Id
    LEFT JOIN TagQuestionStats AS ta ON EXISTS (
        SELECT 1 FROM Posts AS p2
        WHERE p2.Id = rhq.Id AND p2.Tags LIKE CONCAT('%<', ta.TagName, '>%')
    )
    LEFT JOIN UserActivity AS ua ON ua.UserId = rhq.OwnerUserId
)
SELECT t.Id AS UserId, t.DisplayName, t.Reputation, t.BadgeCount,
       thqd.Id AS HotQuestionId, thqd.Title AS HotQuestionTitle, thqd.CreationDate AS QuestionCreation,
       thqd.Score AS QuestionScore, thqd.HotDate AS HotQuestionDate,
       thqd.DuplicateLinks, thqd.LinkedPosts,
       thqd.QuestionCount AS TagQuestionCount, thqd.AvgScore AS TagAvgScore, thqd.MaxViewCount AS TagMaxViews,
       thqd.QuestionsAsked, thqd.AnswersGiven, thqd.CommentsMade, thqd.UpVotesReceived, thqd.DownVotesReceived
FROM TopUsers AS t
LEFT JOIN TopHotQuestionDetails AS thqd ON thqd.OwnerUserId = t.Id
ORDER BY t.Reputation DESC, thqd.HotDate DESC
LIMIT 100;