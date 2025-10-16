WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagInterests,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Occasional'
        END AS ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT DISTINCT UserId, TagName 
        FROM (
            SELECT p.OwnerUserId AS UserId, UNNEST(STRING_TO_ARRAY(p.Tags, '<>')) AS TagName
            FROM Posts p
            WHERE p.Tags IS NOT NULL AND p.Tags <> ''
        ) tags
    ) t ON u.Id = t.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        p.OwnerUserId,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, TagName
        FROM (
            SELECT Id AS PostId, UNNEST(STRING_TO_ARRAY(Tags, '<>')) AS TagName
            FROM Posts
            WHERE Tags IS NOT NULL AND Tags <> ''
        ) sub
        GROUP BY PostId, TagName
    ) t ON p.Id = t.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, u.DisplayName, p.OwnerUserId
),
QuestionStats AS (
    SELECT 
        tq.QuestionId,
        tq.Title,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.CommentCount,
        tq.CreationDate,
        tq.Tags,
        CASE 
            WHEN tq.Score > 100 THEN 'Highly Voted'
            WHEN tq.Score > 50 THEN 'Well Voted'
            WHEN tq.Score > 10 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END AS VotingLevel,
        NTILE(4) OVER (ORDER BY tq.Score DESC) AS ScoreQuartile,
        ROW_NUMBER() OVER (PARTITION BY tq.OwnerName ORDER BY tq.CreationDate DESC) AS QuestionRank,
        AVG(tq.Score) OVER (PARTITION BY tq.OwnerName) AS OwnerAvgScore,
        (tq.Score - AVG(tq.Score) OVER (PARTITION BY tq.OwnerName)) / NULLIF(STDDEV(tq.Score) OVER (PARTITION BY tq.OwnerName), 0) AS ZScore
    FROM TopQuestions tq
),
RecentActivity AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.LastActivityDate,
        u.DisplayName AS OwnerName,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        CAST(EXTRACT(day FROM (DATE '2024-10-01' - p.CreationDate)) AS INTEGER) AS AgeInDays,
        CAST(EXTRACT(day FROM (p.LastActivityDate - p.CreationDate)) AS INTEGER) AS DaysSinceActivity
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (DATE '2024-10-01' - INTERVAL '6 months')
),
CommunityMetrics AS (
    SELECT 
        COUNT(*) AS TotalPosts,
        COUNT(DISTINCT OwnerUserId) AS ActiveUsers,
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViews,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS TotalAnswers,
        (COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) * 100.0) / NULLIF(COUNT(*), 0) AS QuestionPercentage,
        STRING_AGG(DISTINCT v.Name, ', ') AS PopularVoteTypes
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT vt.Name
        FROM Votes v2
        JOIN VoteTypes vt ON vt.Id = v2.VoteTypeId
        WHERE v2.PostId = p.Id
        GROUP BY v2.VoteTypeId, vt.Name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) v ON TRUE
    WHERE CreationDate >= (DATE '2024-10-01' - INTERVAL '6 months')
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.PostCount,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.ActivityLevel,
    uas.ActivityRank,
    qs.QuestionId,
    qs.Title AS QuestionTitle,
    qs.Score AS QuestionScore,
    qs.ViewCount AS QuestionViews,
    qs.AnswerCount AS QuestionAnswers,
    qs.CommentCount AS QuestionComments,
    qs.CreationDate AS QuestionCreated,
    qs.Tags AS QuestionTags,
    qs.VotingLevel,
    qs.ScoreQuartile,
    qs.QuestionRank,
    qs.OwnerAvgScore,
    qs.ZScore,
    ra.PostId,
    ra.Title AS RecentTitle,
    ra.Score AS RecentScore,
    ra.CreationDate AS RecentCreated,
    ra.LastActivityDate AS RecentLastActivity,
    ra.PostType,
    ra.AgeInDays,
    ra.DaysSinceActivity,
    cm.TotalPosts,
    cm.ActiveUsers,
    cm.AvgScore,
    cm.AvgViews,
    cm.TotalQuestions,
    cm.TotalAnswers,
    cm.QuestionPercentage,
    CASE 
        WHEN uas.PostCount > 50 AND uas.Reputation > 5000 THEN 'Elite Contributor'
        WHEN uas.PostCount > 20 AND uas.Reputation > 1000 THEN 'Regular Contributor'
        WHEN uas.PostCount > 5 AND uas.Reputation > 100 THEN 'New Contributor'
        ELSE 'Inactive'
    END AS ContributorTier,
    COALESCE(uas.PostCount, 0) + COALESCE(uas.CommentCount, 0) + COALESCE(uas.BadgeCount, 0) AS TotalEngagement,
    CASE 
        WHEN (uas.QuestionCount * 1.0) / NULLIF(uas.PostCount, 0) > 0.3 THEN 'Question Focused'
        WHEN (uas.AnswerCount * 1.0) / NULLIF(uas.PostCount, 0) > 0.3 THEN 'Answer Focused'
        ELSE 'Mixed Focus'
    END AS ContributionFocus,
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.PostCount DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY uas.ActivityLevel, uas.Reputation DESC) AS ActivityReputationRank
FROM UserActivityStats uas
LEFT JOIN QuestionStats qs ON uas.DisplayName = qs.OwnerName
LEFT JOIN RecentActivity ra ON uas.DisplayName = ra.OwnerName
LEFT JOIN CommunityMetrics cm ON TRUE
WHERE uas.ActivityLevel IN ('Highly Active', 'Active')
  AND (qs.QuestionId IS NOT NULL OR ra.PostId IS NOT NULL)
  AND uas.PostCount >= 3
  AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = uas.UserId 
      AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '3 months')
  )
  AND uas.Reputation >= (
    SELECT AVG(Reputation) + STDDEV(Reputation) 
    FROM Users
  )
ORDER BY uas.ActivityRank, qs.ZScore DESC NULLS LAST, ra.CreationDate DESC NULLS LAST
LIMIT 5000;