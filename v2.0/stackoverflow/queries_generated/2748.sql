-- {"query": "2748.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1520} 

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
        t2.Id,
        t2.TagName,
        t2.Count,
        rth.TagPath || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.Id <> ALL(SELECT unnest(rth.TagPath::varchar[])) AND t2.Count < rth.Count
    WHERE t2.IsModeratorOnly = 0
),
UserBadgesRanked AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM Badges b
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(ub.BadgesCount, 0) AS BadgeCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN (
        SELECT 
            UserId,
            COUNT(*) AS BadgesCount,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) ub ON ub.UserId = u.Id
    WHERE u.Reputation > 5000
),
PostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews
    FROM Posts p
    GROUP BY p.OwnerUserId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS CloseRank
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = try_cast(ph.Comment AS int)
    WHERE ph.PostHistoryTypeId = 10
),
TopClosedQuestions AS (
    SELECT DISTINCT ON (p.Id)
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        qcr.CloseReasonName,
        qcr.CloseDate
    FROM Posts p
    LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = p.Id AND qcr.CloseRank = 1
    WHERE p.PostTypeId = 1 AND qcr.CloseReasonName IS NOT NULL
    ORDER BY p.Id, qcr.CloseDate DESC
),
VotesSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
AnswerDetails AS (
    SELECT
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
AcceptedAnswerScores AS (
    SELECT
        q.Id AS QuestionId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
)
SELECT
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    tu.Views,
    tu.BadgeCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    COALESCE(ps.QuestionCount, 0) AS QuestionCount,
    COALESCE(ps.AnswerCount, 0) AS AnswerCount,
    COALESCE(ps.AvgPostScore, 0) AS AvgPostScore,
    ps.LatestPostDate,
    ps.TotalQuestionViews,
    acq.Id AS ActiveQuestionId,
    acq.Title AS ActiveQuestionTitle,
    acq.Score AS QuestionScore,
    acq.ViewCount AS QuestionViewCount,
    acq.CloseReasonName,
    acq.CloseDate,
    COALESCE(vs.UpVotes, 0) AS QuestionUpVotes,
    COALESCE(vs.DownVotes, 0) AS QuestionDownVotes,
    COALESCE(vs.FavoriteVotes, 0) AS QuestionFavoriteVotes,
    aas.AcceptedAnswerScore,
    ad.Id AS TopAnswerId,
    ad.Score AS TopAnswerScore,
    ad.AnswerRank,
    STRING_AGG(DISTINCT CASE WHEN rth.TagName IS NOT NULL THEN rth.TagName ELSE '' END, ', ' ORDER BY rth.TagName) FILTER (WHERE rth.TagName IS NOT NULL) AS RequiredTagHierarchy
FROM TopUsers tu
LEFT JOIN PostStats ps ON ps.OwnerUserId = tu.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM Posts p2
    WHERE p2.OwnerUserId = tu.Id AND p2.PostTypeId = 1
    ORDER BY p2.ViewCount DESC NULLS LAST, p2.Score DESC NULLS LAST
    LIMIT 1
) acq ON true
LEFT JOIN TopClosedQuestions acq_closed ON acq_closed.Id = acq.Id
LEFT JOIN VotesSummary vs ON vs.PostId = acq.Id
LEFT JOIN AcceptedAnswerScores aas ON aas.QuestionId = acq.Id
LEFT JOIN AnswerDetails ad ON ad.ParentId = acq.Id AND ad.AnswerRank = 1
LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName IS NOT NULL AND acq.Tags LIKE '%' || rth.TagName || '%'
WHERE tu.Reputation > 6000
ORDER BY tu.Reputation DESC NULLS LAST, tu.Views DESC NULLS LAST
LIMIT 50;
