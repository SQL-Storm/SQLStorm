WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS NumPosts,
        COUNT(DISTINCT c.Id) AS NumComments,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= u.LastAccessDate - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= u.LastAccessDate - INTERVAL '30 days'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= u.LastAccessDate - INTERVAL '30 days'
    WHERE
        u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
        AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TopQuestionActivity AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        COUNT(a.Id) AS NumAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        q.Score AS QuestionScore,
        q.ViewCount,
        COUNT(DISTINCT c.Id) AS NumComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v2.VoteTypeId = 3 THEN v2.Id END) AS Downvotes
    FROM
        Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
        LEFT JOIN Comments c ON c.PostId = q.Id
        LEFT JOIN Votes v ON v.PostId = q.Id
        LEFT JOIN Votes v2 ON v2.PostId = q.Id
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount
),
UserTopQuestions AS (
    SELECT
        r.UserId,
        ta.QuestionId,
        ta.Title,
        ta.QuestionScore,
        ta.NumAnswers,
        ta.TotalAnswerScore,
        ta.MaxAnswerScore,
        ta.AvgAnswerScore,
        ta.ViewCount,
        ta.NumComments,
        ta.Upvotes,
        ta.Downvotes,
        -- Calculate "EngagementScore" as a composite metric
        (COALESCE(ta.ViewCount,0)/10
         + COALESCE(ta.NumAnswers,0)*5
         + COALESCE(ta.TotalAnswerScore,0)*2
         + COALESCE(ta.Upvotes,0)*3
         - COALESCE(ta.Downvotes,0)*2
         + COALESCE(ta.NumComments,0)*1) AS EngagementScore,
        DENSE_RANK() OVER (PARTITION BY r.UserId ORDER BY
            (COALESCE(ta.ViewCount,0)/10
             + COALESCE(ta.NumAnswers,0)*5
             + COALESCE(ta.TotalAnswerScore,0)*2
             + COALESCE(ta.Upvotes,0)*3
             - COALESCE(ta.Downvotes,0)*2
             + COALESCE(ta.NumComments,0)*1)
            DESC
        ) AS EngagementRank
    FROM
        RecentActiveUsers r
        INNER JOIN TopQuestionActivity ta ON ta.OwnerUserId = r.UserId
),
BadgeDiversity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Name) AS UniqueBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.Location,
    rau.NumPosts,
    rau.NumComments,
    rau.GoldBadges,
    rau.SilverBadges,
    rau.BronzeBadges,
    bd.UniqueBadges,
    bd.FirstBadgeDate,
    bd.LastBadgeDate,
    uq.Title AS TopQuestionTitle,
    uq.EngagementScore,
    uq.ViewCount,
    uq.NumAnswers,
    uq.TotalAnswerScore,
    uq.AvgAnswerScore,
    uq.MaxAnswerScore,
    uq.Upvotes,
    uq.Downvotes,
    uq.NumComments,
    CASE
        WHEN uq.EngagementScore >= 100 THEN 'Super Engaging'
        WHEN uq.EngagementScore >= 50 THEN 'Engaging'
        WHEN uq.EngagementScore IS NULL THEN 'No Questions'
        ELSE 'Low Engagement'
    END AS EngagementCategory,
    CAST('2024-10-01 12:34:56' AS TIMESTAMP) - rau.CreationDate AS AccountAge
FROM
    RecentActiveUsers rau
    LEFT JOIN UserTopQuestions uq ON uq.UserId = rau.UserId AND uq.EngagementRank = 1
    LEFT JOIN BadgeDiversity bd ON bd.UserId = rau.UserId
WHERE
    (rau.GoldBadges + rau.SilverBadges + rau.BronzeBadges) > 0
ORDER BY
    rau.Reputation DESC NULLS LAST,
    uq.EngagementScore DESC NULLS LAST
LIMIT 100;