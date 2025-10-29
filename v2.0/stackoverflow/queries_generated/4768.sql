-- {"query": "4768.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2119} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
TagQuestionCounts AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS TagQuestionCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY t.TagName
),
AdvancedUserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.CreationDate AS UserCreationDate,
        COALESCE(upe.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upe.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upe.CommentCount, 0) AS TotalComments,
        COALESCE(upe.UpVoteCount, 0) AS TotalUpVotesOnPosts,
        COALESCE(upe.DownVoteCount, 0) AS TotalDownVotesOnPosts,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (
            SELECT AVG(CAST(pt.Score AS NUMERIC))
            FROM Posts pt
            WHERE pt.OwnerUserId = u.Id AND pt.Score IS NOT NULL AND pt.Score <> 0
        ) AS AveragePostScore,
        CASE
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AcceptedAnswerId IS NOT NULL) THEN 'Has Accepted Answers'
            ELSE 'No Accepted Answers'
        END AS AcceptedAnswerStatus
    FROM Users u
    LEFT JOIN UserPostEngagement upe ON u.Id = upe.OwnerUserId
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(p.Score, 0) AS PostScore,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ViewCount AS PostViewCount,
    au.Reputation AS OwnerReputation,
    au.TotalQuestions AS OwnerTotalQuestions,
    au.TotalAnswers AS OwnerTotalAnswers,
    au.GoldBadges AS OwnerGoldBadges,
    au.SilverBadges AS OwnerSilverBadges,
    au.BronzeBadges AS OwnerBronzeBadges,
    au.AveragePostScore AS OwnerAveragePostScore,
    au.AcceptedAnswerStatus,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinks,
    (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)
    ) AS CloseReopenVotes,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS FormattedTags,
    tqc.TagQuestionCount AS PrimaryTagQuestionCount,
    CASE
        WHEN au.DisplayName IS NULL THEN 'Unknown Owner'
        WHEN LENGTH(au.DisplayName) > 15 THEN SUBSTRING(au.DisplayName FROM 1 FOR 15) || '...'
        ELSE au.DisplayName
    END AS TruncatedOwnerDisplayName,
    CASE
        WHEN au.UserViews IS NULL THEN 0
        WHEN au.UserViews > 1000000 THEN 1000000
        ELSE au.UserViews
    END AS CappedUserViews,
    DATE_PART('year', AGE(au.UserCreationDate)) AS OwnerAccountAgeInYears,
    COALESCE(rpe.EditDate, p.CreationDate) AS LastEffectiveEditDate
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN AdvancedUserMetrics au ON p.OwnerUserId = au.UserId
LEFT JOIN TagQuestionCounts tqc ON SUBSTRING(p.Tags, 2, INSTR(p.Tags, '>') - 2) = tqc.TagName
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.PostTypeId = 1 AND p.Score > 10 AND p.CreationDate >= '2023-01-01'
UNION
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(p.Score, 0) AS PostScore,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ViewCount AS PostViewCount,
    au.Reputation AS OwnerReputation,
    au.TotalQuestions AS OwnerTotalQuestions,
    au.TotalAnswers AS OwnerTotalAnswers,
    au.GoldBadges AS OwnerGoldBadges,
    au.SilverBadges AS OwnerSilverBadges,
    au.BronzeBadges AS OwnerBronzeBadges,
    au.AveragePostScore AS OwnerAveragePostScore,
    au.AcceptedAnswerStatus,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinks,
    (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)
    ) AS CloseReopenVotes,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS FormattedTags,
    tqc.TagQuestionCount AS PrimaryTagQuestionCount,
    CASE
        WHEN au.DisplayName IS NULL THEN 'Unknown Owner'
        WHEN LENGTH(au.DisplayName) > 15 THEN SUBSTRING(au.DisplayName FROM 1 FOR 15) || '...'
        ELSE au.DisplayName
    END AS TruncatedOwnerDisplayName,
    CASE
        WHEN au.UserViews IS NULL THEN 0
        WHEN au.UserViews > 1000000 THEN 1000000
        ELSE au.UserViews
    END AS CappedUserViews,
    DATE_PART('year', AGE(au.UserCreationDate)) AS OwnerAccountAgeInYears,
    COALESCE(rpe.EditDate, p.CreationDate) AS LastEffectiveEditDate
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN AdvancedUserMetrics au ON p.OwnerUserId = au.UserId
LEFT JOIN TagQuestionCounts tqc ON SUBSTRING(p.Tags, 2, INSTR(p.Tags, '>') - 2) = tqc.TagName
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.PostTypeId = 2 AND p.Score > 5 AND p.CreationDate >= '2023-06-01'
ORDER BY PostScore DESC, LastActivityDate DESC
LIMIT 1000;