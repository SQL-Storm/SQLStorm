-- {"query": "4221.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1045} 
WITH PostEditCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS EditCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.CommentCount) AS TotalComments,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AverageScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeDistribution AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 5, 8) -- Body edits
    GROUP BY ph.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(upa.TotalPosts, 0) AS TotalPosts,
    COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
    COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
    COALESCE(pec.EditCount, 0) AS TotalEdits,
    COALESCE(ubd.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubd.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubd.BronzeBadges, 0) AS BronzeBadges,
    upa.TotalViews,
    upa.TotalComments,
    upa.AverageScore,
    CASE
        WHEN upa.LastPostDate IS NULL THEN 'Never Posted'
        WHEN upa.LastPostDate < (CURRENT_TIMESTAMP - INTERVAL '365 day') THEN 'Inactive'
        ELSE 'Active'
    END AS UserActivityStatus,
    CASE
        WHEN rph.LastHistoryDate IS NOT NULL AND rph.LastHistoryDate > upa.LastPostDate THEN 1
        ELSE 0
    END AS HadRecentBodyEdits,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AveragePostScoreForUser,
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalViewsForUser,
    COUNT(DISTINCT p.Id) OVER (PARTITION BY p.OwnerUserId) AS PostCountForUser,
    p.Title AS SamplePostTitle,
    p.Tags AS SamplePostTags,
    p.Score AS SamplePostScore,
    p.CreationDate AS SamplePostCreationDate,
    p.ClosedDate AS SamplePostClosedDate
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN PostEditCounts pec ON u.Id = pec.OwnerUserId
LEFT JOIN UserBadgeDistribution ubd ON u.Id = ubd.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Focusing on Questions for sample
LEFT JOIN RecentPostHistory rph ON p.Id = rph.PostId
WHERE u.Id IN (
    SELECT UserId
    FROM Votes
    WHERE VoteTypeId = 2 -- Upvotes
    AND CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '90 day')
    GROUP BY UserId
    ORDER BY COUNT(*) DESC
    LIMIT 100
)
AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%' -- Filter for display names with only alphanumeric and spaces
AND p.Id IS NOT NULL -- Ensure we have at least one post to join on for the sample
ORDER BY u.Reputation DESC, u.Id
LIMIT 50;