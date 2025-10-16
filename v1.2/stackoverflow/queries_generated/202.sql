-- {"query": "202.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2288} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count
    WHERE array_length(r.TagPath, 1) < 3
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(vt.UpVotes), 0) AS TotalUpVotes,
        COALESCE(SUM(vt.DownVotes), 0) AS TotalDownVotes,
        COALESCE(MAX(bc.BadgeCount) FILTER (WHERE bc.Class = 1), 0) AS GoldBadges,
        COALESCE(MAX(bc.BadgeCount) FILTER (WHERE bc.Class = 2), 0) AS SilverBadges,
        COALESCE(MAX(bc.BadgeCount) FILTER (WHERE bc.Class = 3), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) vt ON vt.OwnerUserId = u.Id
    LEFT JOIN UserBadgeCounts bc ON bc.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostWithCommentsAndVotes AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        COALESCE(c.CommentCount, 0) AS TotalComments,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
TopQuestionsWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId AS QuestionOwner,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwner,
        a.CreationDate AS AnswerDate,
        a.CommentCount AS AnswerComments,
        a.UpVotes AS AnswerUpVotes,
        a.DownVotes AS AnswerDownVotes,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM PostWithCommentsAndVotes q
    LEFT JOIN PostWithCommentsAndVotes a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.ViewCount > 1000
),
DuplicateLinks AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
QuestionsWithDuplicateCount AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.QuestionDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        COUNT(dl.RelatedPostId) AS DuplicateCount
    FROM TopQuestionsWithAnswers q
    LEFT JOIN DuplicateLinks dl ON dl.PostId = q.QuestionId
    GROUP BY q.QuestionId, q.Title, q.QuestionDate, q.QuestionScore, q.ViewCount, q.Tags
),
FinalUserStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        RANK() OVER (ORDER BY ua.Reputation DESC, ua.TotalPostScore DESC) AS UserRank
    FROM UserActivity ua
    WHERE ua.Reputation > 1000
),
QuestionsWithUserStats AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.QuestionDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.DuplicateCount,
        fu.DisplayName AS OwnerDisplayName,
        fu.Reputation AS OwnerReputation,
        fu.GoldBadges,
        fu.SilverBadges,
        fu.BronzeBadges
    FROM QuestionsWithDuplicateCount q
    LEFT JOIN FinalUserStats fu ON fu.UserId = (
        SELECT OwnerUserId FROM Posts WHERE Id = q.QuestionId
    )
),
RankedAnswers AS (
    SELECT 
        tqa.QuestionId,
        tqa.Title,
        tqa.QuestionScore,
        tqa.ViewCount,
        tqa.Tags,
        tqa.DuplicateCount,
        tqa.OwnerDisplayName,
        tqa.OwnerReputation,
        tqa.GoldBadges,
        tqa.SilverBadges,
        tqa.BronzeBadges,
        tqa.AnswerId,
        tqa.AnswerScore,
        tqa.AnswerOwner,
        tqa.AnswerDate,
        tqa.AnswerComments,
        tqa.AnswerUpVotes,
        tqa.AnswerDownVotes,
        ROW_NUMBER() OVER (PARTITION BY tqa.QuestionId ORDER BY tqa.AnswerScore DESC) AS AnswerRank
    FROM (
        SELECT 
            q.QuestionId,
            q.Title,
            q.QuestionScore,
            q.ViewCount,
            q.Tags,
            q.DuplicateCount,
            q.OwnerDisplayName,
            q.OwnerReputation,
            q.GoldBadges,
            q.SilverBadges,
            q.BronzeBadges,
            a.Id AS AnswerId,
            a.Score AS AnswerScore,
            a.OwnerUserId AS AnswerOwner,
            a.CreationDate AS AnswerDate,
            a.CommentCount AS AnswerComments,
            a.UpVotes AS AnswerUpVotes,
            a.DownVotes AS AnswerDownVotes
        FROM QuestionsWithUserStats q
        JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
        WHERE a.Score > 0
    ) tqa
)
SELECT 
    r.QuestionId,
    r.Title,
    r.QuestionScore,
    r.ViewCount,
    r.Tags,
    r.DuplicateCount,
    r.OwnerDisplayName,
    r.OwnerReputation,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges,
    r.AnswerId,
    r.AnswerScore,
    r.AnswerOwner,
    u.DisplayName AS AnswerOwnerDisplayName,
    r.AnswerDate,
    r.AnswerComments,
    r.AnswerUpVotes,
    r.AnswerDownVotes,
    ROW_NUMBER() OVER (PARTITION BY r.AnswerOwner ORDER BY r.AnswerScore DESC) AS AnswererRankByScore,
    CASE 
        WHEN r.AnswerScore > 50 THEN 'Excellent'
        WHEN r.AnswerScore BETWEEN 20 AND 50 THEN 'Good'
        WHEN r.AnswerScore BETWEEN 1 AND 19 THEN 'Average'
        ELSE 'Low'
    END AS AnswerQualityCategory,
    COALESCE(phc.CloseCount, 0) AS CloseVotesCount,
    COALESCE(phr.ReopenCount, 0) AS ReopenVotesCount,
    CONCAT(
        'Q:', r.QuestionScore, '|A:', r.AnswerScore, '|C:', r.AnswerComments, '|U:', r.AnswerUpVotes, '|D:', r.AnswerDownVotes
    ) AS SummaryStats
FROM RankedAnswers r
LEFT JOIN Users u ON u.Id = r.AnswerOwner
LEFT JOIN (
    SELECT 
        ph.PostId,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId
) phc ON phc.PostId = r.QuestionId
LEFT JOIN (
    SELECT 
        ph.PostId,
        COUNT(*) AS ReopenCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 11 -- Post Reopened
    GROUP BY ph.PostId
) phr ON phr.PostId = r.QuestionId
WHERE r.AnswerRank <= 3
  AND r.OwnerReputation > 500
ORDER BY r.QuestionScore DESC, r.ViewCount DESC, r.AnswerScore DESC
LIMIT 100;
