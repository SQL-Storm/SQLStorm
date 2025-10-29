WITH RECURSIVE RecursiveUserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        CAST(COUNT(*) AS numeric) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IS NOT NULL
    GROUP BY u.Id, u.DisplayName, b.Class

    UNION ALL

    SELECT
        r.UserId,
        r.DisplayName,
        NULL AS Class,
        SUM(r.BadgeCount) OVER (PARTITION BY r.UserId) AS BadgeCount
    FROM RecursiveUserBadgeCounts r
    WHERE r.Class IS NOT NULL
),
UserMaxBadgeClass AS (
    SELECT UserId, MAX(Class) AS MaxBadgeClass
    FROM RecursiveUserBadgeCounts
    WHERE Class IS NOT NULL
    GROUP BY UserId
),
TopUsersWithBadgeStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ubc.BadgeCount,
        umb.MaxBadgeClass,
        COALESCE(ubc.BadgeCount, 0) AS TotalBadges,
        ROW_NUMBER() OVER (
            ORDER BY COALESCE(ubc.BadgeCount, 0) DESC, u.Reputation DESC, u.Id
        ) AS UserRanking
    FROM Users u
    LEFT JOIN (
        SELECT UserId, SUM(BadgeCount) AS BadgeCount
        FROM RecursiveUserBadgeCounts
        WHERE Class IS NOT NULL
        GROUP BY UserId
    ) ubc ON u.Id = ubc.UserId
    LEFT JOIN UserMaxBadgeClass umb ON u.Id = umb.UserId
    WHERE u.Reputation > (
        SELECT AVG(Reputation) FROM Users
    )
),
QuestionAnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgPostScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS MaxQuestionViewCount,
        MIN(CASE WHEN p.PostTypeId IN (1,2) THEN p.CreationDate ELSE NULL END) AS FirstPostDate,
        MAX(CASE WHEN p.PostTypeId IN (1,2) THEN p.LastActivityDate ELSE NULL END) AS LastPostActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS CloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
UserTaggedWithDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.OwnerUserId AS OwnerUserId,
        p1.Tags,
        p1.CreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id AND p1.PostTypeId = 1
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.LinkTypeId = 3
),
TagPopularity AS (
    SELECT
        tag.Tag AS Tag,
        COUNT(*) AS TagQuestionCount
    FROM (
        SELECT
            p.Id,
            TRIM(s.value) AS Tag
        FROM Posts p,
        LATERAL (
            SELECT regexp_split_to_table(
                substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)),
                '><'
            ) AS value
        ) s
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) tag
    GROUP BY tag.Tag
),
UserFavoriteTags AS (
    SELECT
        q.OwnerUserId AS UserId,
        t.Tag,
        tp.TagQuestionCount,
        COUNT(*) AS TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY COUNT(*) DESC, tp.TagQuestionCount DESC) AS TagRank
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS Tag FROM (
            SELECT regexp_split_to_table(
                substring(q.Tags FROM 2 FOR (char_length(q.Tags) - 2)),
                '><'
            ) AS value
        ) s
    ) t
    JOIN TagPopularity tp ON tp.Tag = t.Tag
    WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId, t.Tag, tp.TagQuestionCount
),
TopTagsPerUser AS (
    SELECT UserId, Tag, TagUsageCount, TagQuestionCount
    FROM UserFavoriteTags
    WHERE TagRank <= 3
),
UserActivityScore AS (
    SELECT
        u.Id AS UserId,
        u.Reputation * 0.5 +
        COALESCE(SUM(CASE b.Class WHEN 1 THEN 10 WHEN 2 THEN 5 WHEN 3 THEN 1 ELSE 0 END), 0) * 3 +
        COALESCE(qa.AnswerCount, 0) * 2 +
        COALESCE(qa.QuestionCount, 0) +
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate))/86400 * -0.1 AS ActivityScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN QuestionAnswerStats qa ON qa.UserId = u.Id
    GROUP BY u.Id, u.Reputation, u.LastAccessDate, qa.AnswerCount, qa.QuestionCount
),
FinalUserSummary AS (
    SELECT
        tu.UserRanking,
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        COALESCE(qa.QuestionCount,0) AS QuestionCount,
        COALESCE(qa.AnswerCount,0) AS AnswerCount,
        COALESCE(qa.AvgPostScore,0) AS AveragePostScore,
        tu.TotalBadges,
        umb.MaxBadgeClass,
        f.ActivityScore,
        STRING_AGG(tt.Tag || ' (' || tt.TagUsageCount || '/' || tt.TagQuestionCount || ')', ', ' ORDER BY tt.TagUsageCount DESC) AS TopTags,
        CASE WHEN qc.CloseReasonId IS NOT NULL THEN 
            (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(qc.CloseReasonId AS integer))
        ELSE NULL END AS MostRecentCloseReason,
        qc.CloseDate
    FROM TopUsersWithBadgeStats tu
    LEFT JOIN QuestionAnswerStats qa ON qa.UserId = tu.Id
    LEFT JOIN UserMaxBadgeClass umb ON umb.UserId = tu.Id
    LEFT JOIN UserActivityScore f ON f.UserId = tu.Id
    LEFT JOIN TopTagsPerUser tt ON tt.UserId = tu.Id
    LEFT JOIN LATERAL (
        SELECT ph.PostId, ph.Comment AS CloseReasonId, ph.CreationDate AS CloseDate
        FROM PostHistory ph
        JOIN Posts p ON p.Id = ph.PostId AND p.OwnerUserId = tu.Id
        WHERE ph.PostHistoryTypeId = 10
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    ) qc ON TRUE
    GROUP BY tu.UserRanking, tu.Id, tu.DisplayName, tu.Reputation, qa.QuestionCount, qa.AnswerCount, qa.AvgPostScore, tu.TotalBadges, umb.MaxBadgeClass, f.ActivityScore, qc.CloseReasonId, qc.CloseDate
)
SELECT
    UserRanking,
    UserId,
    DisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    ROUND(CAST(AveragePostScore AS numeric),3) AS AvgPostScore,
    TotalBadges,
    CASE MaxBadgeClass
        WHEN 1 THEN 'Gold'
        WHEN 2 THEN 'Silver'
        WHEN 3 THEN 'Bronze'
        ELSE 'None'
    END AS HighestBadgeClass,
    ROUND(CAST(ActivityScore AS numeric),2) AS ActivityScore,
    COALESCE(TopTags, 'No tags') AS FavoriteTags,
    MostRecentCloseReason,
    CloseDate
FROM FinalUserSummary
WHERE UserRanking <= 100
ORDER BY ActivityScore DESC, Reputation DESC, UserRanking;