-- {"query": "2248.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1200}
WITH RECURSIVE RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        1 AS Depth
    FROM Users u
    WHERE u.Reputation > 1000 AND u.Location IS NOT NULL

    UNION ALL

    SELECT
        a.Id AS UserId,
        a.DisplayName,
        a.Reputation,
        a.CreationDate,
        COALESCE(a.Location, 'Unknown') AS Location,
        a.Views,
        a.UpVotes,
        a.DownVotes,
        r.Depth + 1
    FROM RecursiveUserActivity r
    JOIN Users a ON a.Id = r.UserId + 1
    WHERE r.Depth < 5
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostAggregates AS (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
        STRING_AGG(DISTINCT COALESCE(p.OwnerDisplayName, 'Anonymous') || ':' || COALESCE(p.Title, 'NoTitle'), ' | ') AS TitlesSample
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
PostAnswerRates AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        CASE WHEN q.Score > 0 THEN 1.0 * COALESCE(a.AnswerCount, 0) / q.Score ELSE NULL END AS AnswerToScoreRatio,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS RecentQuestionRank
    FROM Posts q
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
),
CloseReasonSummary AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserQuestionCloseStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS ClosedQuestions,
        SUM(COALESCE(crs.CloseVotesCount,0)) AS TotalCloseVotes,
        STRING_AGG(DISTINCT COALESCE(crs.CloseReasonName, 'Unknown'), ',') AS CloseReasons
    FROM Posts p
    LEFT JOIN CloseReasonSummary crs ON p.Id = crs.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    pg.QuestionCount,
    pg.AnswerCount,
    pg.AvgPostScore,
    pg.TotalViews,
    COALESCE(uqcs.ClosedQuestions,0) AS ClosedQuestions,
    COALESCE(uqcs.TotalCloseVotes,0) AS TotalCloseVotes,
    uqcs.CloseReasons,
    AVG(par.AnswerToScoreRatio) FILTER (WHERE par.AnswerToScoreRatio IS NOT NULL) AS AvgAnswerToScoreRatio,
    MAX(CASE WHEN par.RecentQuestionRank = 1 THEN par.Score END) AS LatestQuestionScore,
    SUBSTRING(pg.TitlesSample FROM 1 FOR 150) AS TitlesSampleShort
FROM Users u
LEFT JOIN UserBadgeCounts ub ON u.Id = ub.UserId
LEFT JOIN PostAggregates pg ON u.Id = pg.OwnerUserId
LEFT JOIN UserQuestionCloseStats uqcs ON u.Id = uqcs.OwnerUserId
LEFT JOIN PostAnswerRates par ON u.Id = par.OwnerUserId
WHERE u.Reputation > 2000 
  AND (COALESCE(pg.QuestionCount,0) > 10 OR COALESCE(pg.AnswerCount,0) > 20)
GROUP BY 
    u.Id, u.DisplayName, u.Location, u.Reputation, 
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    pg.QuestionCount, pg.AnswerCount, pg.AvgPostScore, pg.TotalViews,
    uqcs.ClosedQuestions, uqcs.TotalCloseVotes, uqcs.CloseReasons,
    pg.TitlesSample
HAVING AVG(par.AnswerToScoreRatio) FILTER (WHERE par.AnswerToScoreRatio IS NOT NULL) > 0.5
ORDER BY u.Reputation DESC, pg.QuestionCount DESC
LIMIT 50;