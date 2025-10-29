WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays,
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount
    FROM Users u
    WHERE u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year'
      AND u.Reputation > 1000
),
UserPostAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END), 0) AS AvgQuestionViewCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS AcceptedAnswerCount,
        COALESCE(AVG(LENGTH(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END)), 0) AS AvgQuestionTitleLength
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentAggregates AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        COALESCE(AVG(c.Score), 0) AS AvgCommentScore,
        COALESCE(AVG(LENGTH(c.Text)), 0) AS AvgCommentLength
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostHistoryEngagement AS (
    SELECT
        ph.UserId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloses,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopens,
        (
            SELECT crt.Name
            FROM PostHistory ph_inner
            JOIN CloseReasonTypes crt ON crt.Id = CAST(ph_inner.Comment AS SMALLINT)
            WHERE ph_inner.UserId = ph.UserId AND ph_inner.PostHistoryTypeId = 10 AND ph_inner.Comment ~ '^[0-9]+$'
            GROUP BY crt.Name
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS MostFrequentCloseReason
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TopQuestionTags AS (
    SELECT TagName, TagScore FROM (
        SELECT
            tag AS TagName,
            SUM(p.Score) AS TagScore
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT TRIM(value) AS tag
            FROM (SELECT regexp_split_to_table(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS value) t1
        ) tags
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
        GROUP BY tag
        HAVING SUM(p.Score) > 100
    ) AS TagScores
    GROUP BY TagName, TagScore
    ORDER BY TagScore DESC
    LIMIT 10
),
UserTagDensity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT tag) AS UniqueTagsPosted,
        COUNT(DISTINCT tq.TagName) AS CommonTagsUsed
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS tag
        FROM (SELECT regexp_split_to_table(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS value) t2
    ) post_tags
    LEFT JOIN TopQuestionTags tq ON post_tags.tag = tq.TagName
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.Location,
    SUBSTRING(rau.AboutMe FROM 1 FOR 100) AS AboutMeExcerpt,
    rau.AccountAgeDays,
    COALESCE(rau.GoldBadgeCount, 0) AS GoldBadges,
    COALESCE(upa.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(upa.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(upa.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(upa.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(upa.AvgQuestionViewCount, 0) AS AvgQuestionViewCount,
    COALESCE(upa.AcceptedAnswerCount, 0) AS AcceptedAnswersGiven,
    COALESCE(uca.TotalComments, 0) AS TotalComments,
    COALESCE(uca.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(phe.TotalEdits, 0) AS TotalEditsToPosts,
    COALESCE(phe.TotalCloses, 0) AS TotalPostsClosedBy,
    COALESCE(phe.TotalReopens, 0) AS TotalPostsReopenedBy,
    phe.MostFrequentCloseReason,
    COALESCE(utd.UniqueTagsPosted, 0) AS UniqueTagsUsedInQuestions,
    COALESCE(utd.CommonTagsUsed, 0) AS TopTagsUsed,
    (
        SELECT p_max.Title
        FROM Posts p_max
        WHERE p_max.OwnerUserId = rau.UserId AND p_max.PostTypeId = 1
        ORDER BY p_max.Score DESC, p_max.CreationDate DESC
        LIMIT 1
    ) AS HighestScoredQuestionTitle,
    (
        (COALESCE(upa.TotalQuestions, 0) * 0.5) +
        (COALESCE(upa.TotalAnswers, 0) * 0.7) +
        (COALESCE(uca.TotalComments, 0) * 0.2) +
        (COALESCE(rau.GoldBadgeCount, 0) * 5) +
        (COALESCE(phe.TotalEdits, 0) * 0.1)
    ) AS VersatilityScore,
    RANK() OVER (PARTITION BY rau.Location ORDER BY rau.Reputation DESC) AS RankInLocation,
    CASE
        WHEN rau.Reputation >= 10000 AND COALESCE(rau.GoldBadgeCount, 0) >= 3 AND COALESCE(upa.TotalQuestions, 0) >= 50 AND COALESCE(upa.TotalAnswers, 0) >= 100 THEN 'Elite Contributor'
        WHEN rau.Reputation >= 5000 AND (COALESCE(upa.TotalQuestions, 0) >= 25 OR COALESCE(upa.TotalAnswers, 0) >= 50) AND COALESCE(upa.AcceptedAnswerCount, 0) >= 10 THEN 'Senior Specialist'
        WHEN rau.Reputation >= 2000 AND (COALESCE(upa.TotalQuestions, 0) > 0 OR COALESCE(upa.TotalAnswers, 0) > 0) THEN 'Active Participant'
        ELSE 'Engaged User'
    END AS UserCategory,
    (rau.AboutMe ILIKE '%developer%' OR rau.AboutMe ILIKE '%engineer%' OR rau.Location ILIKE '%developer%' OR rau.Location ILIKE '%engineer%') AS IsTechProfessional
FROM RecentActiveUsers rau
LEFT JOIN UserPostAggregates upa ON rau.UserId = upa.UserId
LEFT JOIN UserCommentAggregates uca ON rau.UserId = uca.UserId
LEFT JOIN PostHistoryEngagement phe ON rau.UserId = phe.UserId
LEFT JOIN UserTagDensity utd ON rau.UserId = utd.UserId
WHERE
    COALESCE(rau.GoldBadgeCount, 0) > 0
    AND (COALESCE(upa.TotalQuestions, 0) > 0 OR COALESCE(upa.TotalAnswers, 0) > 0)
    AND (COALESCE(upa.TotalQuestionScore, 0) + COALESCE(upa.TotalAnswerScore, 0)) >= 100
    AND (
        rau.Location IS NOT NULL AND rau.Location <> ''
        AND LENGTH(rau.AboutMe) > 50
        AND (rau.AboutMe ILIKE '%sql%' OR rau.AboutMe ILIKE '%database%' OR rau.AboutMe ILIKE '%programming%')
    )
    AND COALESCE(utd.CommonTagsUsed, 0) >= 2
ORDER BY VersatilityScore DESC, rau.Reputation DESC, RankInLocation ASC
LIMIT 100;