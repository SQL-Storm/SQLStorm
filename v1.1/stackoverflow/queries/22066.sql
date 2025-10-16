WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN p.Score ELSE NULL END) AS AvgAcceptedAnswerScore,
        -- standard SQL: aggregate distinct tag strings; use COALESCE to avoid NULLs in LENGTH
        STRING_AGG(DISTINCT CASE WHEN COALESCE(p.Tags, '') <> '' AND LENGTH(p.Tags) > 2 THEN REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><', ', ') ELSE NULL END, '; ') FILTER (WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL) AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserVotes AS (
    SELECT 
        u.Id AS UserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS AvgBountyOffered
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionScore,
        ua.AnswerScore,
        COALESCE(ua.AvgAcceptedAnswerScore, 0) AS AvgAcceptedAnswerScore,
        ua.AllTags,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uv.VoteCount, 0) AS VoteCount,
        COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
        uv.AvgBountyOffered,
        (ua.Reputation * 1.0 + COALESCE(ua.QuestionScore, 0) + COALESCE(ua.AnswerScore, 0) * 2 + COALESCE(ub.BadgeCount, 0) * 10 + COALESCE(uv.UpVotesGiven, 0) - COALESCE(uv.DownVotesGiven, 0)) AS ActivityScore,
        ROW_NUMBER() OVER (ORDER BY (ua.Reputation * 1.0 + COALESCE(ua.QuestionScore, 0) + COALESCE(ua.AnswerScore, 0) * 2 + COALESCE(ub.BadgeCount, 0) * 10 + COALESCE(uv.UpVotesGiven, 0) - COALESCE(uv.DownVotesGiven, 0)) DESC) AS Rank
    FROM UserActivity ua
    LEFT JOIN UserBadges ub ON ua.UserId = ub.UserId
    LEFT JOIN UserVotes uv ON ua.UserId = uv.UserId
    WHERE ua.PostCount > 0 OR COALESCE(ub.BadgeCount, 0) > 0 OR COALESCE(uv.VoteCount, 0) > 0
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Rank,
    ru.Reputation,
    ru.PostCount,
    ru.QuestionScore,
    ru.AnswerScore,
    ru.AvgAcceptedAnswerScore,
    CASE WHEN ru.AllTags IS NOT NULL AND LENGTH(ru.AllTags) > 100 THEN SUBSTRING(ru.AllTags FROM 1 FOR 100) || '...' ELSE ru.AllTags END AS TagsSnippet,
    ru.BadgeCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.VoteCount,
    ru.UpVotesGiven,
    ru.DownVotesGiven,
    ru.AvgBountyOffered,
    ru.ActivityScore,
    LAG(ru.ActivityScore, 1, NULL) OVER (ORDER BY ru.Rank) - ru.ActivityScore AS ScoreDiffFromPrev,
    LEAD(ru.ActivityScore, 1, NULL) OVER (ORDER BY ru.Rank) - ru.ActivityScore AS ScoreDiffFromNext,
    CASE 
        WHEN ru.AvgAcceptedAnswerScore IS NULL THEN 'No accepted answers'
        WHEN ru.AvgAcceptedAnswerScore > 50 THEN 'High scorer'
        WHEN ru.AvgAcceptedAnswerScore BETWEEN 10 AND 50 THEN 'Moderate scorer'
        ELSE 'Low scorer'
    END AS AcceptanceCategory,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedQuestionsCount,
    0 AS IsTotalRow -- helper column to allow ORDER BY on UNION results using a column name
FROM RankedUsers ru
WHERE ru.Rank <= 100

UNION ALL

SELECT 
    NULL AS UserId,
    'TOTAL AVERAGE' AS DisplayName,
    NULL AS Rank,
    AVG(ru.Reputation) AS Reputation,
    AVG(ru.PostCount) AS PostCount,
    AVG(ru.QuestionScore) AS QuestionScore,
    AVG(ru.AnswerScore) AS AnswerScore,
    AVG(ru.AvgAcceptedAnswerScore) AS AvgAcceptedAnswerScore,
    NULL AS TagsSnippet,
    AVG(ru.BadgeCount) AS BadgeCount,
    AVG(ru.GoldBadges) AS GoldBadges,
    AVG(ru.SilverBadges) AS SilverBadges,
    AVG(ru.BronzeBadges) AS BronzeBadges,
    AVG(ru.VoteCount) AS VoteCount,
    AVG(ru.UpVotesGiven) AS UpVotesGiven,
    AVG(ru.DownVotesGiven) AS DownVotesGiven,
    AVG(ru.AvgBountyOffered) AS AvgBountyOffered,
    AVG(ru.ActivityScore) AS ActivityScore,
    NULL AS ScoreDiffFromPrev,
    NULL AS ScoreDiffFromNext,
    NULL AS AcceptanceCategory,
    AVG((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL)) AS AcceptedQuestionsCount,
    1 AS IsTotalRow
FROM RankedUsers ru

ORDER BY 
    IsTotalRow ASC,
    Rank;