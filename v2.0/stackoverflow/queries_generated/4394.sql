-- {"query": "4394.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1803} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        COUNT(a.Id) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank,
        AVG(CAST(a.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.Id) AS AvgAnswerScore,
        MAX(a.CreationDate) OVER (PARTITION BY p.Id) AS LastAnswerDate
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl
),
ComplexJoins AS (
    SELECT
        rq.QuestionId,
        rq.QuestionTitle,
        rq.QuestionScore,
        rq.QuestionViewCount,
        ua.UserId,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        ua.UserCreationDate,
        ua.PostHistoryCount,
        ua.TotalUpVotesReceived,
        ua.TotalDownVotesReceived,
        ua.BadgeCount,
        ua.WebsiteStatus,
        ph.Comment AS LastPostHistoryComment,
        COALESCE(pht.Name, 'Unknown') AS LastPostHistoryType,
        CASE
            WHEN rq.AvgAnswerScore IS NULL THEN 0
            WHEN rq.AvgAnswerScore < 5 THEN 'Low'
            WHEN rq.AvgAnswerScore BETWEEN 5 AND 15 THEN 'Medium'
            ELSE 'High'
        END AS AnswerQualityBand,
        DATEDIFF(day, rq.QuestionCreationDate, GETDATE()) AS DaysSinceCreation,
        (ua.TotalUpVotesReceived * 1.0 / NULLIF(ua.TotalDownVotesReceived, 0)) AS UpvoteDownvoteRatio,
        CONCAT(ua.DisplayName, ' (', ua.Reputation, ')') AS UserIdentifier
    FROM RankedQuestions rq
    JOIN UserActivity ua ON rq.OwnerUserId = ua.UserId
    LEFT JOIN PostHistory ph ON rq.QuestionId = ph.PostId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN (
        SELECT PostId, MAX(CreationDate) as MaxCreationDate
        FROM PostHistory
        GROUP BY PostId
    ) AS LatestHistory ON rq.QuestionId = LatestHistory.PostId AND ph.CreationDate = LatestHistory.MaxCreationDate
    WHERE ua.Reputation > 1000 AND rq.QuestionScore > 50
)
SELECT
    cj.QuestionId,
    cj.QuestionTitle,
    cj.QuestionScore,
    cj.QuestionViewCount,
    cj.OwnerDisplayName,
    cj.OwnerReputation,
    cj.UserCreationDate,
    cj.PostHistoryCount,
    cj.TotalUpVotesReceived,
    cj.TotalDownVotesReceived,
    cj.BadgeCount,
    cj.WebsiteStatus,
    cj.LastPostHistoryComment,
    cj.LastPostHistoryType,
    cj.AnswerQualityBand,
    cj.DaysSinceCreation,
    cj.UpvoteDownvoteRatio,
    cj.UserIdentifier,
    CASE
        WHEN cj.DaysSinceCreation > 365 THEN 'Veteran'
        WHEN cj.DaysSinceCreation > 180 THEN 'Experienced'
        ELSE 'Newer'
    END AS UserTenureCategory,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cj.QuestionId AND v.VoteTypeId = 2) AS DirectUpvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cj.QuestionId AND LEN(c.Text) > 50) AS LongCommentsCount,
    CASE WHEN cj.AnswerCount = 0 THEN 'No Answers' WHEN cj.AnswerCount < 5 THEN 'Few Answers' ELSE 'Many Answers' END AS AnswerQuantityCategory,
    CASE WHEN cj.LastAnswerDate IS NOT NULL AND cj.DaysSinceCreation > DATEDIFF(day, cj.LastAnswerDate, GETDATE()) THEN 'Stale Answers' ELSE 'Active Answers' END AS AnswerActivityStatus,
    CASE WHEN cj.QuestionScore < 0 THEN 'Negative Score' WHEN cj.QuestionScore BETWEEN 0 AND 10 THEN 'Low Score' WHEN cj.QuestionScore BETWEEN 11 AND 100 THEN 'Medium Score' ELSE 'High Score' END AS ScoreCategory,
    CASE WHEN cj.OwnerReputation >= 100000 THEN 'Expert' WHEN cj.OwnerReputation >= 10000 THEN 'Senior' WHEN cj.OwnerReputation >= 1000 THEN 'Intermediate' ELSE 'Beginner' END AS ReputationTier,
    IIF(cj.OwnerReputation > 50000 OR cj.BadgeCount > 10, 'High Potential', 'Standard') AS UserPotential,
    STR(cj.QuestionViewCount / NULLIF(cj.AnswerCount, 0)) AS ViewsPerAnswer
FROM ComplexJoins cj
WHERE cj.OwnerReputation > 5000 AND cj.BadgeCount > 2
UNION
SELECT
    NULL AS QuestionId,
    'Summary' AS QuestionTitle,
    AVG(cj.QuestionScore) AS QuestionScore,
    AVG(cj.QuestionViewCount) AS QuestionViewCount,
    NULL AS OwnerDisplayName,
    AVG(cj.OwnerReputation) AS OwnerReputation,
    NULL AS UserCreationDate,
    AVG(cj.PostHistoryCount) AS PostHistoryCount,
    AVG(cj.TotalUpVotesReceived) AS TotalUpVotesReceived,
    AVG(cj.TotalDownVotesReceived) AS TotalDownVotesReceived,
    AVG(cj.BadgeCount) AS BadgeCount,
    'N/A' AS WebsiteStatus,
    NULL AS LastPostHistoryComment,
    'Summary' AS LastPostHistoryType,
    NULL AS AnswerQualityBand,
    AVG(cj.DaysSinceCreation) AS DaysSinceCreation,
    NULL AS UpvoteDownvoteRatio,
    NULL AS UserIdentifier,
    NULL AS UserTenureCategory,
    NULL AS DirectUpvotes,
    NULL AS LongCommentsCount,
    NULL AS AnswerQuantityCategory,
    NULL AS AnswerActivityStatus,
    NULL AS ScoreCategory,
    NULL AS ReputationTier,
    NULL AS UserPotential,
    NULL AS ViewsPerAnswer
FROM ComplexJoins cj
WHERE cj.OwnerReputation > 5000 AND cj.BadgeCount > 2;
