-- {"query": "2880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1265}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CAST(t.TagName AS VARCHAR(35)) AS FullPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE
  UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CAST(r.FullPath || '>' || t.TagName AS VARCHAR(35)) AS FullPath,
        r.Level + 1
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r
      ON r.TagName = SUBSTRING(t.TagName FROM 1 FOR CHAR_LENGTH(r.TagName))
     AND r.Level < 3
),
QuestionStats AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS OwnerRecentPostRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerAggregates AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        MAX(a.Score) AS MaxAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.CreationDate <= q.CreationDate + INTERVAL '7' DAY THEN 1 ELSE 0 END) AS AnswersWithinWeek
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) AS BadgesPerClass,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank
    FROM Badges b
),
CloseReasonCounts AS (
    SELECT
        cht.Id AS CloseReasonId,
        cht.Name AS CloseReasonName,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    JOIN PostHistoryTypes cht ON ph.PostHistoryTypeId = cht.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Id, cht.Name
),
PostLinkInfo AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN COALESCE(b.Class, 0) = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN COALESCE(b.Class, 0) = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN COALESCE(b.Class, 0) = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.AcceptedAnswerId,
    a.TotalAnswers,
    a.MaxAnswerScore,
    a.AvgAnswerScore,
    a.AnswersWithinWeek,
    b.BadgeName,
    b.Class AS BadgeClass,
    b.BadgesPerClass,
    cr.CloseReasonName,
    pl.LinkTypeName,
    upeng.QuestionCount AS UserQuestionCount,
    upeng.AnswerCount AS UserAnswerCount,
    upeng.TotalUpVotes,
    upeng.TotalDownVotes,
    upeng.GoldBadges,
    upeng.SilverBadges,
    upeng.BronzeBadges,
    rh.FullPath AS TagHierarchyPath
FROM QuestionStats q
LEFT JOIN AnswerAggregates a ON a.QuestionId = q.Id
LEFT JOIN UserBadgeRanks b ON b.UserId = q.OwnerUserId AND b.RecentBadgeRank = 1
LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
LEFT JOIN CloseReasonCounts cr ON cr.CloseReasonId = CAST(ph.Comment AS INTEGER) AND ph.PostHistoryTypeId = 10
LEFT JOIN PostLinkInfo pl ON pl.PostId = q.Id
LEFT JOIN UserPostEngagement upeng ON upeng.UserId = q.OwnerUserId
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = SUBSTRING(q.Tags FROM 2 FOR POSITION('>' IN (q.Tags || '>')) - 2)
WHERE
    q.Score > 5
    AND q.ViewCount > 1000
    AND (a.AvgAnswerScore IS NULL OR a.AvgAnswerScore > 0)
    AND (q.AcceptedAnswerId IS NOT NULL OR q.FavoriteCount > 0)
GROUP BY
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.AcceptedAnswerId,
    a.TotalAnswers,
    a.MaxAnswerScore,
    a.AvgAnswerScore,
    a.AnswersWithinWeek,
    b.BadgeName,
    b.Class,
    b.BadgesPerClass,
    cr.CloseReasonName,
    pl.LinkTypeName,
    upeng.QuestionCount,
    upeng.AnswerCount,
    upeng.TotalUpVotes,
    upeng.TotalDownVotes,
    upeng.GoldBadges,
    upeng.SilverBadges,
    upeng.BronzeBadges,
    rh.FullPath
ORDER BY q.ViewCount DESC, q.Score DESC
LIMIT 100;