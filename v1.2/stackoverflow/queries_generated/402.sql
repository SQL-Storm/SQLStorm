-- {"query": "402.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1833} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        SUM(COALESCE(b.TagBased, 0)) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 10
      AND p.ViewCount > 100
      AND p.ClosedDate IS NULL
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserActivityWindows AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(c.Id) AS CommentsMade,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600) AS AvgPostActiveHours,
        MAX(p.Score) AS MaxPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
RecentCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate,
        ph.UserId
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > NOW() - INTERVAL '30 days'
),
PostsWithLinks AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName,
        pl.RelatedPostId
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE p.PostTypeId IN (1, 2)
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        vt.Name AS VoteTypeName,
        COUNT(v.Id) AS VoteCount,
        SUM(COALESCE(v.BountyAmount,0)) AS TotalBountyGiven
    FROM Votes v
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId, vt.Name
),
ComplexUserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.AvgPostActiveHours,
        ua.MaxPostScore,
        COALESCE(uvs.VoteCount, 0) AS TotalVotesCast,
        COALESCE(uvs.TotalBountyGiven, 0) AS TotalBountyGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ubc.GoldBadges DESC, ua.AnswersPosted DESC) AS UserRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN UserActivityWindows ua ON ua.Id = u.Id
    LEFT JOIN (
        SELECT UserId, SUM(VoteCount) AS VoteCount, SUM(TotalBountyGiven) AS TotalBountyGiven
        FROM UserVoteSummary
        GROUP BY UserId
    ) uvs ON uvs.UserId = u.Id
    WHERE u.Reputation > 1000
),
FinalSelection AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        u.DisplayName AS OwnerName,
        q.Score AS QuestionScore,
        q.ViewCount,
        asn.AnswerCount,
        asn.AvgAnswerScore,
        asn.MaxAnswerScore,
        asn.AnonymousAnswers,
        cr.CloseReasonName,
        cr.CreationDate AS CloseDate,
        pl.LinkTypeName,
        pl.RelatedPostId,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.QuestionsPosted,
        cus.AnswersPosted,
        cus.CommentsMade,
        cus.AvgPostActiveHours,
        cus.MaxPostScore,
        cus.TotalVotesCast,
        cus.TotalBountyGiven,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS OwnerTopQuestionRank
    FROM TopQuestions q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN AnswerStats asn ON asn.QuestionId = q.Id
    LEFT JOIN RecentCloseReasons cr ON cr.PostId = q.Id
    LEFT JOIN PostsWithLinks pl ON pl.Id = q.Id
    LEFT JOIN ComplexUserStats cus ON cus.Id = q.OwnerUserId
    WHERE q.rn <= 3
)
SELECT
    fs.QuestionId,
    fs.Title,
    fs.OwnerUserId,
    fs.OwnerName,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.AnonymousAnswers,
    COALESCE(fs.CloseReasonName, 'Open') AS CloseReason,
    fs.CloseDate,
    fs.LinkTypeName,
    fs.RelatedPostId,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.QuestionsPosted,
    fs.AnswersPosted,
    fs.CommentsMade,
    ROUND(fs.AvgPostActiveHours::numeric, 2) AS AvgPostActiveHours,
    fs.MaxPostScore,
    fs.TotalVotesCast,
    fs.TotalBountyGiven,
    fs.OwnerTopQuestionRank,
    CONCAT(
        'User: ', fs.OwnerName, ' (Rep: ', COALESCE(cus.Reputation::text, 'N/A'), ')',
        ' | Badges: G:', fs.GoldBadges, ', S:', fs.SilverBadges, ', B:', fs.BronzeBadges,
        ' | Posts: Q:', fs.QuestionsPosted, ', A:', fs.AnswersPosted, ', C:', fs.CommentsMade
    ) AS UserSummary
FROM FinalSelection fs
LEFT JOIN ComplexUserStats cus ON cus.Id = fs.OwnerUserId
WHERE fs.OwnerTopQuestionRank <= 3
ORDER BY fs.QuestionScore DESC, fs.ViewCount DESC, fs.AnswerCount DESC;
