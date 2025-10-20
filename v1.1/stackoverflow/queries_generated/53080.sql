-- {"query": "53080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 849} 

WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
        COUNT(p.Id) AS PostsCount,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionViews
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, ActivityYear
),
UserBadgesPerYear AS (
    SELECT 
        UserId,
        EXTRACT(YEAR FROM Date) AS BadgeYear,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId, BadgeYear
),
UserVotesGiven AS (
    SELECT 
        UserId,
        EXTRACT(YEAR FROM CreationDate) AS VoteYear,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes
    WHERE VoteTypeId IN (2, 3) AND UserId IS NOT NULL
    GROUP BY UserId, VoteYear
),
UserEdits AS (
    SELECT 
        UserId,
        EXTRACT(YEAR FROM CreationDate) AS EditYear,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT PostId) AS UniquePostsEdited
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) AND UserId IS NOT NULL
    GROUP BY UserId, EditYear
),
CombinedActivity AS (
    SELECT 
        ua.Id,
        ua.DisplayName,
        ua.ActivityYear,
        ua.PostsCount,
        ua.TotalScore,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgQuestionViews,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
        COALESCE(ue.EditCount, 0) AS EditCount,
        COALESCE(ue.UniquePostsEdited, 0) AS UniquePostsEdited
    FROM UserActivity ua
    LEFT JOIN UserBadgesPerYear ub ON ua.Id = ub.UserId AND ua.ActivityYear = ub.BadgeYear
    LEFT JOIN UserVotesGiven uv ON ua.Id = uv.UserId AND ua.ActivityYear = uv.VoteYear
    LEFT JOIN UserEdits ue ON ua.Id = ue.UserId AND ua.ActivityYear = ue.EditYear
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY ActivityYear ORDER BY TotalScore DESC, BadgeCount DESC, EditCount DESC) AS ActivityRank,
        DENSE_RANK() OVER (PARTITION BY ActivityYear ORDER BY GoldBadges DESC) AS GoldRank
    FROM CombinedActivity
    WHERE TotalScore > 0 AND PostsCount > 10
)
SELECT *
FROM RankedUsers
WHERE ActivityRank <= 50 OR GoldRank <= 10
ORDER BY ActivityYear DESC, ActivityRank ASC;
