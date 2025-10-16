-- {"query": "827.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1590} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 1 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.Count > 1000
  UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, r.Depth + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON POSITION(t2.TagName IN r.TagName) > 0
    WHERE r.Depth < 3
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(v.BountyAmount),0) AS TotalBountyGiven,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 8 -- BountyStart
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostDiffs AS (
    SELECT ph.PostId,
           MAX(CASE WHEN ph.PostHistoryTypeId IN (1,4) THEN ph.CreationDate END) AS LastTitleEdit,
           MAX(CASE WHEN ph.PostHistoryTypeId IN (2,5) THEN ph.CreationDate END) AS LastBodyEdit,
           MAX(CASE WHEN ph.PostHistoryTypeId IN (3,6) THEN ph.CreationDate END) AS LastTagsEdit
    FROM PostHistory ph
    GROUP BY ph.PostId
),
TopActiveUsers AS (
    SELECT ua.UserId, ua.DisplayName, ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade, ua.TotalBountyGiven,
           ua.AvgPostScore, ua.LastPostDate, ua.BadgeCount, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
           ROW_NUMBER() OVER (ORDER BY ua.BadgeCount DESC, ua.Reputation DESC NULLS LAST) AS ActivityRank
    FROM UserActivity ua
    JOIN Users u ON ua.UserId = u.Id
),
QuestionAnswerStats AS (
    SELECT q.Id AS QuestionId,
           q.Title,
           q.CreationDate AS QuestionDate,
           q.Score AS QuestionScore,
           q.ViewCount,
           a.Id AS AnswerId,
           a.Score AS AnswerScore,
           a.CreationDate AS AnswerDate,
           a.OwnerUserId AS AnswerOwnerUserId,
           EXISTS (
               SELECT 1 FROM Votes v2 WHERE v2.PostId = a.Id AND v2.VoteTypeId = 2
           ) AS HasUpvotes,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS QuestionComments,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerComments,
           pt.Name AS QuestionType,
           at.Name AS AnswerType
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN PostTypes pt ON q.PostTypeId = pt.Id
    LEFT JOIN PostTypes at ON a.PostTypeId = at.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
DuplicatesAndLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName,
           q.Title AS QuestionTitle,
           rq.Title AS RelatedQuestionTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts q ON q.Id = pl.PostId AND q.PostTypeId = 1
    LEFT JOIN Posts rq ON rq.Id = pl.RelatedPostId AND rq.PostTypeId = 1
    WHERE lt.Name IN ('Duplicate', 'Linked')
),
AvgScoreByUser AS (
    SELECT OwnerUserId,
           AVG(Score) AS AvgScore,
           COUNT(*) AS PostCount
    FROM Posts
    WHERE PostTypeId IN (1,2)
    GROUP BY OwnerUserId
),
FinalSelection AS (
    SELECT 
        t.ActivityRank,
        t.DisplayName,
        t.QuestionsPosted,
        t.AnswersPosted,
        t.CommentsMade,
        t.TotalBountyGiven,
        t.AvgPostScore,
        t.BadgeCount,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        pqs.QuestionId,
        pqs.Title AS QuestionTitle,
        pqs.QuestionDate,
        pqs.QuestionScore,
        pqs.ViewCount,
        pqs.AnswerId,
        pqs.AnswerScore,
        pqs.AnswerDate,
        pqs.HasUpvotes,
        pqs.QuestionComments,
        pqs.AnswerComments,
        dal.LinkTypeName,
        dal.RelatedPostId,
        dal.RelatedQuestionTitle,
        COALESCE(avgScore.AvgScore, 0) AS AnswerOwnerAvgScore,
        COALESCE(avgScore.PostCount, 0) AS AnswerOwnerPostCount,
        COALESCE(phd.LastTitleEdit, NULL) AS LastTitleEdit,
        COALESCE(phd.LastBodyEdit, NULL) AS LastBodyEdit,
        COALESCE(phd.LastTagsEdit, NULL) AS LastTagsEdit,
        CASE
          WHEN t.GoldBadges > 0 THEN 'High Gold'
          WHEN t.SilverBadges > 5 THEN 'Active Silver'
          WHEN t.BronzeBadges > 10 THEN 'Bronze Enthusiast'
          ELSE 'Newbie'
        END AS BadgeCategory,
        CONCAT(
          'User: ', t.DisplayName, ' | Qs: ', t.QuestionsPosted, ' | As: ', t.AnswersPosted, 
          ' | ScoreAvg: ', COALESCE(ROUND(t.AvgPostScore,2)::TEXT, '0'),
          ' | Last Q Date: ', TO_CHAR(pqs.QuestionDate, 'YYYY-MM-DD')
        ) AS SummaryString
    FROM TopActiveUsers t
    LEFT JOIN QuestionAnswerStats pqs ON pqs.AnswerOwnerUserId = t.UserId
    LEFT JOIN DuplicatesAndLinks dal ON dal.PostId = pqs.QuestionId
    LEFT JOIN AvgScoreByUser avgScore ON avgScore.OwnerUserId = pqs.AnswerOwnerUserId
    LEFT JOIN PostDiffs phd ON phd.PostId = pqs.QuestionId
    WHERE t.ActivityRank <= 100
)
SELECT *
FROM FinalSelection
ORDER BY ActivityRank, QuestionDate DESC, AnswerScore DESC;
