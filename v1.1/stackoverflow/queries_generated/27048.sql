-- {"query": "27048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1332} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        COALESCE(a.AnswerCount, 0) AS TotalAnswers,
        COALESCE(a.AcceptedAnswerCount, 0) AS TotalAcceptedAnswers
    FROM Users u
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS AnswerCount,
            COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS AcceptedAnswerCount
        FROM Posts p
        WHERE p.PostTypeId = 2
        GROUP BY p.OwnerUserId
    ) a ON u.Id = a.OwnerUserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '30 days'
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COUNT(p.Id) AS QuestionCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
        STRING_AGG(DISTINCT p.OwnerDisplayName, ', ') AS TopAuthors
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserBadges AS (
    SELECT
        b.UserId,
        u.DisplayName,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    GROUP BY b.UserId, u.DisplayName
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.AnswerCount,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
        p.LastEditDate,
        p.LastEditorUserId,
        p.LastEditorDisplayName,
        p.LastActivityDate
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '7 days'
)
SELECT
    rp.PostId,
    rp.PostTypeId,
    pt.Name AS PostTypeName,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    COALESCE(au.Reputation, 0) AS OwnerReputation,
    COALESCE(au.DisplayName, 'Unknown') AS OwnerDisplayName,
    rp.AnswerCount,
    COALESCE(au.TotalAnswers, 0) AS OwnerTotalAnswers,
    COALESCE(au.TotalAcceptedAnswers, 0) AS OwnerTotalAcceptedAnswers,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.LastEditDate,
    COALESCE(rpc.UserId, 0) AS LastEditorUserId,
    COALESCE(rpc.DisplayName, 'Unknown') AS LastEditorDisplayName,
    EXTRACT(EPOCH FROM (rp.LastActivityDate - rp.CreationDate)) / 3600 AS HoursSinceLastActivity,
    COALESCE(ub.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(ub.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS OwnerBronzeBadges
FROM RecentPosts rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN UserBadges ub ON rp.OwnerUserId = ub.UserId
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN Users rpc on  rp.LastEditorUserId = rpc.UserId
WHERE rp.Score > (
    SELECT AVG(Score)
    FROM Posts
    WHERE PostTypeId = 1
    AND CreationDate > NOW() - INTERVAL '30 days'
)
ORDER BY rp.Score DESC, rp.CreationDate DESC;
