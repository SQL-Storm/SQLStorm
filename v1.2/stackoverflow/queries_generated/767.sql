-- {"query": "767.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1619} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        parent.TagPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.IsRequired = 0 AND child.Count < parent.Count
    WHERE array_length(parent.TagPath, 1) < 3
),
TopUsersByBadge AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 5
    ORDER BY ReputationRank
    LIMIT 100
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
RecentHighlyVotedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByType
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '180 days'
      AND p.Score > 10
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons,
        MAX(ph.CreationDate) AS LastClosedDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId, v.PostId
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Score > 5 THEN 1 ELSE 0 END) AS HighScoreAnswers
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY p.ParentId
),
ComplexUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        tb.GoldBadges,
        tb.SilverBadges,
        tb.BronzeBadges,
        COALESCE(uvs.UpVotesGiven, 0) AS TotalUpVotesGiven,
        COALESCE(uvs.DownVotesGiven, 0) AS TotalDownVotesGiven,
        ua.LastPostDate,
        ua.LastCommentDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate))/86400 AS AccountAgeDays,
        CASE 
            WHEN u.Location IS NULL THEN 'Unknown'
            WHEN POSITION(',' IN u.Location) > 0 THEN SUBSTRING(u.Location FROM 1 FOR POSITION(',' IN u.Location)-1)
            ELSE u.Location
        END AS LocationCountry,
        COALESCE(ABS(u.UpVotes - u.DownVotes), 0) AS VoteBalance,
        COALESCE(ua.QuestionsPosted + ua.AnswersPosted + ua.CommentsMade, 0) AS TotalContributions
    FROM Users u
    LEFT JOIN UserActivity ua ON ua.UserId = u.Id
    LEFT JOIN TopUsersByBadge tb ON tb.UserId = u.Id
    LEFT JOIN UserVoteSummary uvs ON uvs.UserId = u.Id
    WHERE u.Reputation > 1000
),
FinalResult AS (
    SELECT
        cus.UserId,
        cus.DisplayName,
        cus.LocationCountry,
        cus.AccountAgeDays,
        cus.ReputationRank,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.TotalContributions,
        cus.TotalUpVotesGiven,
        cus.TotalDownVotesGiven,
        cus.VoteBalance,
        rq.Title AS RecentPopularQuestion,
        rq.Score AS RecentPopularQuestionScore,
        rq.ViewCount AS RecentPopularQuestionViews,
        pci.CloseReasons,
        pci.LastClosedDate,
        asn.AnswerCount,
        asn.AvgAnswerScore,
        asn.MaxAnswerScore,
        asn.HighScoreAnswers
    FROM ComplexUserStats cus
    LEFT JOIN RecentHighlyVotedPosts rq ON rq.PostTypeId = 1 AND rq.OwnerName = cus.DisplayName AND rq.RankByType = 1
    LEFT JOIN PostCloseInfo pci ON pci.PostId = rq.Id
    LEFT JOIN AnswerStats asn ON asn.QuestionId = rq.Id
    LEFT JOIN TopUsersByBadge tb ON tb.UserId = cus.UserId
),
RankedFinalResult AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY LocationCountry ORDER BY TotalContributions DESC, GoldBadges DESC, AccountAgeDays DESC) AS RankInCountry
    FROM FinalResult
)
SELECT
    rfr.UserId,
    rfr.DisplayName,
    rfr.LocationCountry,
    rfr.AccountAgeDays,
    rfr.GoldBadges,
    rfr.SilverBadges,
    rfr.BronzeBadges,
    rfr.TotalContributions,
    rfr.TotalUpVotesGiven,
    rfr.TotalDownVotesGiven,
    rfr.VoteBalance,
    rfr.RecentPopularQuestion,
    rfr.RecentPopularQuestionScore,
    rfr.RecentPopularQuestionViews,
    rfr.CloseReasons,
    rfr.LastClosedDate,
    rfr.AnswerCount,
    rfr.AvgAnswerScore,
    rfr.MaxAnswerScore,
    rfr.HighScoreAnswers,
    rfr.RankInCountry
FROM RankedFinalResult rfr
WHERE rfr.RankInCountry <= 5
ORDER BY rfr.LocationCountry, rfr.RankInCountry;
