WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.ExcerptPostId, t.WikiPostId, 0 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE
    UNION ALL
    SELECT tg.Id, tg.TagName, tg.ExcerptPostId, tg.WikiPostId, rth.Level + 1
    FROM Tags tg
    JOIN RecursiveTagHierarchy rth ON tg.Id <> rth.Id AND tg.Id > rth.Id
    WHERE tg.IsRequired = TRUE
      AND rth.Level < 3
),
RecentHighlyVotedAnswers AS (
    SELECT p.Id, p.ParentId, p.Score, p.CreationDate, u.DisplayName AS AnswerOwner, 
        row_number() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
      AND p.Score > 10
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '180' DAY)
),
QuestionStats AS (
    SELECT q.Id AS QuestionId, q.Title, q.CreationDate, q.ViewCount, q.Score AS QuestionScore, q.Tags,
       COALESCE(a.HighestAnswerScore, 0) AS HighestAnswerScore,
       COALESCE(a.AnswerCount, 0) AS TotalAnswers,
       COALESCE(c.CommentCount, 0) AS TotalComments,
       u.DisplayName AS OwnerName,
       CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
       CASE WHEN q.ClosedDate IS NULL THEN FALSE ELSE TRUE END AS IsClosed
    FROM Posts q
    LEFT JOIN (
        SELECT ParentId, max(Score) AS HighestAnswerScore, count(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = q.Id
    LEFT JOIN (
        SELECT PostId, count(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = q.Id
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
),
UserBadgeRanks AS (
    SELECT b.UserId,
           sum(CASE WHEN b.Class = 1 THEN 3 ELSE 0 END) +
           sum(CASE WHEN b.Class = 2 THEN 2 ELSE 0 END) +
           sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
UserReputationRanks AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           rank() OVER (ORDER BY u.Reputation DESC) AS RepRank,
           dense_rank() OVER (ORDER BY u.Reputation DESC) AS RepDenseRank,
           ntile(10) OVER (ORDER BY u.Reputation DESC) AS RepDecile
    FROM Users u
),
UserEngagement AS (
    SELECT u.Id AS UserId,
           count(DISTINCT p.Id) AS PostCount,
           count(DISTINCT v.Id) AS VoteCount,
           count(DISTINCT c.Id) AS CommentCount,
           COALESCE(sum(v.BountyAmount),0) AS TotalBounty,
           min(u.CreationDate) AS FirstActive,
           max(u.LastAccessDate) AS LastActive
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
AnswerWithDups AS (
    SELECT p.Id, p.ParentId, pl.LinkTypeId, pl.RelatedPostId
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    WHERE p.PostTypeId = 2
),
QuestionsWithDuplicateCounts AS (
    SELECT q.Id,
           count(DISTINCT ad.RelatedPostId) AS DuplicateCount
    FROM Posts q
    LEFT JOIN AnswerWithDups ad ON ad.ParentId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
PostHistoriesWithCloseReason AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, cr.Name AS CloseReasonName, ph.CreationDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.Comment = CAST(cr.Id AS varchar) AND ph.PostHistoryTypeId = 10
),
PopularTags AS (
    SELECT t.TagName, t.Count,
           COALESCE(qcnt.QuestionCount, 0) AS QuestionsCount,
           COALESCE(acnt.AnswerCount, 0) AS AnswersCount,
           COALESCE(bcnt.BadgeCount, 0) AS BadgeCount
    FROM Tags t
    LEFT JOIN (
        SELECT tagname AS TagName, count(*) AS QuestionCount
        FROM (
            SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS tagname
            FROM Posts p
            WHERE p.PostTypeId = 1
        ) s
        GROUP BY tagname
    ) qcnt ON qcnt.TagName = t.TagName
    LEFT JOIN (
        SELECT tagname AS TagName, count(*) AS AnswerCount
        FROM (
            SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS tagname
            FROM Posts p
            WHERE p.PostTypeId = 2
        ) s
        GROUP BY tagname
    ) acnt ON acnt.TagName = t.TagName
    LEFT JOIN (
        SELECT b.Name AS BadgeName, count(*) AS BadgeCount
        FROM Badges b
        GROUP BY b.Name
    ) bcnt ON bcnt.BadgeName = t.TagName
),
FinalResults AS (
    SELECT qs.QuestionId, qs.Title, qs.CreationDate AS QuestionCreated, qs.ViewCount, qs.QuestionScore,
           qs.HighestAnswerScore, qs.TotalAnswers, qs.TotalComments, qs.OwnerName, qs.HasAcceptedAnswer,
           qs.IsClosed, qwd.DuplicateCount,
           uer.RepRank, uer.Reputation, ubr.BadgeScore,
           ue.PostCount, ue.VoteCount, ue.CommentCount, ue.TotalBounty,
           phcr.CloseReasonName,
           pt.TagName, pt.Count AS TagPopularity, pt.QuestionsCount, pt.AnswersCount, pt.BadgeCount,
           rth.Level AS TagDepth
    FROM QuestionStats qs
    LEFT JOIN QuestionsWithDuplicateCounts qwd ON qs.QuestionId = qwd.Id
    LEFT JOIN Users u ON u.DisplayName = qs.OwnerName
    LEFT JOIN UserReputationRanks uer ON uer.Id = u.Id
    LEFT JOIN UserBadgeRanks ubr ON ubr.UserId = u.Id
    LEFT JOIN UserEngagement ue ON ue.UserId = u.Id
    LEFT JOIN (
        SELECT ph.PostId, ph.CloseReasonName
        FROM PostHistoriesWithCloseReason ph
        WHERE (ph.PostId, ph.CreationDate) IN (
            SELECT ph2.PostId, max(ph2.CreationDate)
            FROM PostHistoriesWithCloseReason ph2
            GROUP BY ph2.PostId
        )
    ) phcr ON phcr.PostId = qs.QuestionId
    LEFT JOIN LATERAL (
        SELECT pt.TagName, pt.Count, pt.QuestionsCount, pt.AnswersCount, pt.BadgeCount, rth.Level
        FROM PopularTags pt
        JOIN RecursiveTagHierarchy rth ON rth.TagName = pt.TagName
        WHERE qs.Tags LIKE '%' || pt.TagName || '%'
        ORDER BY pt.Count DESC
        LIMIT 1
    ) pt ON TRUE
    LEFT JOIN RecursiveTagHierarchy rth ON pt.TagName = rth.TagName
    WHERE qs.QuestionScore > 5 AND qs.ViewCount > 1000
)
SELECT *
FROM FinalResults
ORDER BY QuestionScore DESC, HighestAnswerScore DESC, TotalAnswers DESC, TagPopularity DESC
LIMIT 100;