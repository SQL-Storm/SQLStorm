-- {"query": "49096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2036} 
WITH UserActivitySummary AS (
    -- Summarizes post-related activities for each user per year
    SELECT
        p.OwnerUserId AS UserId,
        EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND parent_p.AcceptedAnswerId = p.Id THEN p.Id END) AS AcceptedAnswersProvided
    FROM Posts p
    LEFT JOIN Posts parent_p ON p.ParentId = parent_p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, EXTRACT(YEAR FROM p.CreationDate)
),
UserBadgeStats AS (
    -- Counts gold badges received by each user per year
    SELECT
        b.UserId,
        EXTRACT(YEAR FROM b.Date) AS ActivityYear,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgesCount
    FROM Badges b
    WHERE b.UserId IS NOT NULL
    GROUP BY b.UserId, EXTRACT(YEAR FROM b.Date)
),
UserCommentStats AS (
    -- Calculates the average score of comments on posts owned by each user per year
    SELECT
        p.OwnerUserId AS UserId,
        EXTRACT(YEAR FROM c.CreationDate) AS ActivityYear,
        AVG(CAST(c.Score AS NUMERIC)) AS AverageCommentScore
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND c.Score IS NOT NULL
    GROUP BY p.OwnerUserId, EXTRACT(YEAR FROM c.CreationDate)
),
UserPostLinkStats AS (
    -- Counts how many times a user's posts are linked to or duplicated per year
    SELECT
        p.OwnerUserId AS UserId,
        EXTRACT(YEAR FROM pl.CreationDate) AS ActivityYear,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicatePostsCount
    FROM PostLinks pl
    JOIN Posts p ON pl.RelatedPostId = p.Id -- Post p is the post being linked/duplicated
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, EXTRACT(YEAR FROM pl.CreationDate)
),
UserPostHistoryStats AS (
    -- Counts distinct post history actions a user was involved in per year
    SELECT
        ph.UserId,
        EXTRACT(YEAR FROM ph.CreationDate) AS ActivityYear,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryActions
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, EXTRACT(YEAR FROM ph.CreationDate)
),
UserTagActivity AS (
    -- Identifies the most active tag for each user per year
    WITH UserRawTags AS (
        SELECT
            p.OwnerUserId AS UserId,
            EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
            TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))) AS TagName
        FROM Posts p
        WHERE p.Tags IS NOT NULL AND p.Tags != '><' AND p.OwnerUserId IS NOT NULL AND LENGTH(p.Tags) > 2
    ),
    RankedUserTags AS (
        SELECT
            UserId,
            ActivityYear,
            TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER(PARTITION BY UserId, ActivityYear ORDER BY COUNT(*) DESC, TagName ASC) AS rn
        FROM UserRawTags
        GROUP BY UserId, ActivityYear, TagName
    )
    SELECT
        UserId,
        ActivityYear,
        TagName AS MostActiveTag,
        TagCount AS MostActiveTagCount
    FROM RankedUserTags
    WHERE rn = 1
),
AllDistinctUserYears AS (
    -- Combines all unique UserId and ActivityYear pairs across all activity types
    SELECT UserId, ActivityYear FROM UserActivitySummary
    UNION
    SELECT UserId, ActivityYear FROM UserBadgeStats
    UNION
    SELECT UserId, ActivityYear FROM UserCommentStats
    UNION
    SELECT UserId, ActivityYear FROM UserPostLinkStats
    UNION
    SELECT UserId, ActivityYear FROM UserPostHistoryStats
    UNION
    SELECT UserId, ActivityYear FROM UserTagActivity
),
CombinedUserYearlyStats AS (
    -- Joins all yearly user statistics into a single table
    SELECT
        aduy.UserId,
        aduy.ActivityYear,
        u.DisplayName,
        COALESCE(uas.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(uas.AcceptedAnswersProvided, 0) AS AcceptedAnswersProvided,
        COALESCE(ubs.GoldBadgesCount, 0) AS GoldBadgesCount,
        COALESCE(ucs.AverageCommentScore, 0.0) AS AverageCommentScore,
        COALESCE(upls.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(upls.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        COALESCE(uphs.DistinctHistoryActions, 0) AS DistinctHistoryActions,
        utas.MostActiveTag,
        utas.MostActiveTagCount
    FROM AllDistinctUserYears aduy
    JOIN Users u ON aduy.UserId = u.Id
    LEFT JOIN UserActivitySummary uas ON aduy.UserId = uas.UserId AND aduy.ActivityYear = uas.ActivityYear
    LEFT JOIN UserBadgeStats ubs ON aduy.UserId = ubs.UserId AND aduy.ActivityYear = ubs.ActivityYear
    LEFT JOIN UserCommentStats ucs ON aduy.UserId = ucs.UserId AND aduy.ActivityYear = ucs.ActivityYear
    LEFT JOIN UserPostLinkStats upls ON aduy.UserId = upls.UserId AND aduy.ActivityYear = upls.ActivityYear
    LEFT JOIN UserPostHistoryStats uphs ON aduy.UserId = uphs.UserId AND aduy.ActivityYear = uphs.ActivityYear
    LEFT JOIN UserTagActivity utas ON aduy.UserId = utas.UserId AND aduy.ActivityYear = utas.ActivityYear
),
RankedUserImpact AS (
    -- Calculates an arbitrary 'Impact Score' and ranks users within each year
    SELECT
        UserId,
        DisplayName,
        ActivityYear,
        TotalPostScore,
        AcceptedAnswersProvided,
        GoldBadgesCount,
        AverageCommentScore,
        LinkedPostsCount,
        DuplicatePostsCount,
        DistinctHistoryActions,
        MostActiveTag,
        MostActiveTagCount,
        (
            (CAST(AcceptedAnswersProvided AS NUMERIC) * 5) + -- Accepted answers weighted highest
            (CAST(TotalPostScore AS NUMERIC) * 1) +          -- Total post score
            (CAST(GoldBadgesCount AS NUMERIC) * 10) +         -- Gold badges are significant
            (CAST(LinkedPostsCount + DuplicatePostsCount AS NUMERIC) * 2) + -- Being linked or duplicated shows influence
            (COALESCE(AverageCommentScore, 0.0) * 0.5) +      -- Quality of comments received
            (CAST(DistinctHistoryActions AS NUMERIC) * 1)     -- Involvement in community actions
        ) AS ImpactScore,
        ROW_NUMBER() OVER(PARTITION BY ActivityYear ORDER BY (
            (CAST(AcceptedAnswersProvided AS NUMERIC) * 5) +
            (CAST(TotalPostScore AS NUMERIC) * 1) +
            (CAST(GoldBadgesCount AS NUMERIC) * 10) +
            (CAST(LinkedPostsCount + DuplicatePostsCount AS NUMERIC) * 2) +
            (COALESCE(AverageCommentScore, 0.0) * 0.5) +
            (CAST(DistinctHistoryActions AS NUMERIC) * 1)
        ) DESC, UserId ASC) AS RankInYear
    FROM CombinedUserYearlyStats
)
-- Final selection: Top 5 users for the 3 most recent years with any activity
SELECT
    r.ActivityYear,
    r.RankInYear,
    r.UserId,
    r.DisplayName,
    r.ImpactScore,
    r.AcceptedAnswersProvided,
    r.TotalPostScore,
    r.GoldBadgesCount,
    ROUND(r.AverageCommentScore, 2) AS AverageCommentScore,
    r.LinkedPostsCount,
    r.DuplicatePostsCount,
    r.DistinctHistoryActions,
    r.MostActiveTag,
    r.MostActiveTagCount
FROM RankedUserImpact r
WHERE r.RankInYear <= 5
  AND r.ActivityYear IN (
      SELECT DISTINCT ActivityYear
      FROM RankedUserImpact
      ORDER BY ActivityYear DESC
      LIMIT 3
  )
ORDER BY r.ActivityYear DESC, r.RankInYear ASC;