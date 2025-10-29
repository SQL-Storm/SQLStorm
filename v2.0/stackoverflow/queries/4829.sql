WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT UserId) AS DistinctEditors,
        SUM(CASE WHEN rn = 1 THEN 1 ELSE 0 END) AS MostRecentEditsCount
    FROM RankedPostEdits
    GROUP BY PostId
),
RecentQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        Tags,
        ViewCount,
        FavoriteCount,
        AnswerCount,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
),
UserQuestionStats AS (
    SELECT
        rq.OwnerUserId,
        COUNT(rq.Id) AS TotalQuestions,
        AVG(rq.ViewCount) AS AvgQuestionViews,
        SUM(CASE WHEN rq.FavoriteCount > 0 THEN 1 ELSE 0 END) AS QuestionsFavorited,
        MAX(rq.CreationDate) AS LatestQuestionDate
    FROM RecentQuestions rq
    WHERE rq.OwnerUserId IS NOT NULL
    GROUP BY rq.OwnerUserId
),
-- Normalize tags by splitting the Tags string. This uses standard SQL/ANSI functions where possible.
-- Implementation below assumes a DB that supports regexp_split_to_table (Postgres) or UNNEST-like behavior.
-- For wider compatibility, replace regexp_split_to_table with the appropriate split function for your dialect.
PostTags AS (
    SELECT
        p.Id AS PostId,
        TRIM(t.tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(
            SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)),
            '><'
        ) AS tag
    ) t
    WHERE p.Tags IS NOT NULL AND p.Tags <> '' AND p.PostTypeId = 1
),
QuestionTagCounts AS (
    SELECT
        p.Id AS PostId,
        pt.TagName,
        COUNT(CASE WHEN p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days') THEN 1 ELSE NULL END) AS RecentTagCount,
        COUNT(p.Id) AS TotalTagCount
    FROM Posts p
    JOIN PostTags pt ON pt.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, pt.TagName
)
SELECT
    rq.Id AS QuestionId,
    rq.Title AS QuestionTitle,
    u.DisplayName AS OriginalPoster,
    COALESCE(uot.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(uot.AvgQuestionViews, 0.0) AS UserAvgQuestionViews,
    COALESCE(pec.DistinctEditors, 0) AS QuestionDistinctEditors,
    COALESCE(pec.MostRecentEditsCount, 0) AS QuestionMostRecentEdits,
    CASE
        WHEN rq.AnswerCount IS NULL THEN 'N/A'
        WHEN rq.AnswerCount = 0 THEN 'No Answers'
        WHEN rq.AnswerCount > 10 THEN 'Many Answers'
        ELSE CAST(rq.AnswerCount AS VARCHAR)
    END AS AnswerSummary,
    LOWER(REPLACE(REPLACE(rq.Tags, '><', ' '), '<', '')) AS FormattedTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id AND c.Score > 5) AS HighScoreComments,
    CASE
        WHEN COALESCE(qtc.RecentTagCount, 0) > 0 THEN 'Active Today'
        WHEN COALESCE(qtc.TotalTagCount, 0) > 100 THEN 'Popular Tag'
        ELSE 'Standard Tag'
    END AS TagActivityStatus,
    CASE
        WHEN rq.ViewCount IS NULL THEN 0
        WHEN rq.ViewCount > 1000000 THEN 1000000
        ELSE rq.ViewCount
    END AS ClampedViewCount,
    CASE
        WHEN rq.FavoriteCount IS NULL OR rq.FavoriteCount = 0 THEN 'Not Favorited'
        WHEN rq.FavoriteCount >= 5 THEN 'Highly Favorited'
        ELSE 'Favorited'
    END AS FavoriteStatus,
    CASE
        WHEN rq.CreationDate < (cast('2024-10-01' as date) - INTERVAL '180 days') AND rq.AnswerCount = 0 THEN 'Old and Unanswered'
        WHEN rq.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '7 days') THEN 'Recent'
        ELSE 'Established'
    END AS QuestionAgeCategory,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rq.Id AND pl.LinkTypeId = 3) THEN 'Has Duplicates'
        ELSE 'No Known Duplicates'
    END AS DuplicateStatus
FROM RecentQuestions rq
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN UserQuestionStats uot ON rq.OwnerUserId = uot.OwnerUserId
LEFT JOIN PostEditCounts pec ON rq.Id = pec.PostId
LEFT JOIN QuestionTagCounts qtc ON rq.Id = qtc.PostId
WHERE rq.Title IS NOT NULL
  AND CHAR_LENGTH(rq.Title) > 10
  AND rq.ViewCount > 100
  AND COALESCE(rq.FavoriteCount, 0) > 0
  OR rq.Id IN (SELECT PostId FROM Votes WHERE VoteTypeId = 2 AND UserId = 12345)
ORDER BY rq.CreationDate DESC
LIMIT 1000;