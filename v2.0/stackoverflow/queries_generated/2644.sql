-- {"query": "2644.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2268} 
WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        rh.Level + 1,
        rh.AncestorPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy rh ON t.Id <> rh.Id
    WHERE array_position(rh.AncestorPath, t.TagName) IS NULL
      AND t.IsModeratorOnly = 0
      AND rh.Level < 3
),
TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS RankByReputation
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (2,3)
    WHERE u.Reputation IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING u.Reputation > 5000
),
RecentlyActivePosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS RecentRank
    FROM Posts p
    WHERE p.LastActivityDate >= CURRENT_DATE - INTERVAL '180 days'
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserQuestionStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
PostWithDuplicateInfo AS (
    SELECT p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate,
        EXISTS (
            SELECT 1 FROM PostLinks pl
            WHERE pl.PostId = p.Id
            AND pl.LinkTypeId = 3 -- Duplicate
        ) AS HasDuplicates,
        (
            SELECT COUNT(*) FROM PostLinks pl2
            WHERE pl2.RelatedPostId = p.Id
            AND pl2.LinkTypeId = 3
        ) AS DuplicateCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserActivitySummary AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ub.GoldCount,
        ub.SilverCount,
        ub.BronzeCount,
        us.QuestionsCount,
        us.AvgQuestionScore,
        us.QuestionsWithAcceptedAnswers,
        tu.TotalUpVotes,
        tu.TotalDownVotes,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN UserQuestionStats us ON us.UserId = u.Id
    LEFT JOIN TopUsersByReputation tu ON tu.Id = u.Id
    WHERE u.Reputation > 1000
),
PostWithWindow AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        p.Tags,
        LEAD(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS NextHigherScore,
        LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PreviousLowerScore
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
PostsWithCommentsCount AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id, p.Title, p.PostTypeId
),
CompositeUserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        ui.RankByReputation,
        us.QuestionsCount,
        us.AvgQuestionScore,
        us.QuestionsWithAcceptedAnswers,
        ub.GoldCount,
        ub.SilverCount,
        ub.BronzeCount,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COALESCE(COUNT(p.Id),0) AS TotalPosts,
        COALESCE(SUM(p.ViewCount),0) AS TotalViews,
        COALESCE(SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END),0) AS TotalAcceptedAnswers
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN UserQuestionStats us ON us.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    LEFT JOIN TopUsersByReputation ui ON ui.Id = u.Id
    GROUP BY u.Id, u.DisplayName, ui.RankByReputation, us.QuestionsCount, us.AvgQuestionScore, us.QuestionsWithAcceptedAnswers,
        ub.GoldCount, ub.SilverCount, ub.BronzeCount
    HAVING COUNT(p.Id) > 5
)
SELECT DISTINCT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(ub.GoldCount, 0) AS GoldBadges,
    COALESCE(ub.SilverCount, 0) AS SilverBadges,
    COALESCE(ub.BronzeCount, 0) AS BronzeBadges,
    us.QuestionsCount,
    us.AvgQuestionScore,
    us.QuestionsWithAcceptedAnswers,
    s.TotalPosts,
    s.TotalPostScore,
    s.TotalViews,
    s.TotalAcceptedAnswers,
    CASE 
        WHEN u.WebsiteUrl IS NULL OR LENGTH(TRIM(u.WebsiteUrl)) = 0 THEN 'No Website'
        ELSE SUBSTRING(u.WebsiteUrl FROM 1 FOR 30) || CASE WHEN LENGTH(u.WebsiteUrl) > 30 THEN '...' ELSE '' END
    END AS WebsiteSnippet,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT ph.Name, ', ' ORDER BY ph.Name)
            FROM PostHistory ph
            JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
            WHERE ph.UserId = u.Id
            AND ph.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
            LIMIT 5
        ),
        'No Recent Edits'
    ) AS RecentPostHistoryTypes,
    COALESCE((
        SELECT AVG(p.Score)
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.LastActivityDate > CURRENT_DATE - INTERVAL '1 year'
    ), 0) AS AvgScoreLastYearQuestions,
    COALESCE((
        SELECT COUNT(1)
        FROM Votes v
        WHERE v.UserId = u.Id
          AND v.VoteTypeId = 2
          AND v.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    ), 0) AS RecentUpVotesGiven,
    COALESCE((
        SELECT MAX(ViewCount)
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.ViewCount IS NOT NULL
    ), 0) AS MaxQuestionViewCount,
    COALESCE((
        SELECT STRING_AGG(DISTINCT unnest(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', '|'), '|')), ',' ORDER BY 1)
        FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags <> ''
        LIMIT 10
    ), 'No Tags') AS UserPopularTags,
    phc.CommentCount,
    pwdi.HasDuplicates,
    pwdi.DuplicateCount,
    -- Correlated subquery with NULL logic to get last edit date of post
    (
        SELECT MAX(ph_edit.CreationDate)
        FROM PostHistory ph_edit
        WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId IN (4,5,6)
    ) AS LastEditDate,
    CASE 
        WHEN s.TotalAcceptedAnswers > 10 THEN 'Top Contributor'
        WHEN s.TotalAcceptedAnswers BETWEEN 5 AND 10 THEN 'Active Contributor'
        ELSE 'Contributor'
    END AS ContributorCategory
FROM Users u
LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
LEFT JOIN UserQuestionStats us ON us.UserId = u.Id
LEFT JOIN CompositeUserPostStats s ON s.UserId = u.Id
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN PostsWithCommentsCount phc ON phc.PostId = p.Id
LEFT JOIN PostWithDuplicateInfo pwdi ON pwdi.Id = p.Id
WHERE u.Reputation > 10000
AND (
    u.Location IS NOT NULL 
    AND LOWER(u.Location) NOT LIKE '%unknown%'
    AND LOWER(u.Location) NOT LIKE '%earth%'
)
AND (
    ub.GoldCount > 0 OR ub.SilverCount > 5 OR ub.BronzeCount > 10
)
ORDER BY u.Reputation DESC
LIMIT 50;