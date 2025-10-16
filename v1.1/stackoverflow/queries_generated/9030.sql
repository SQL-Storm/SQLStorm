-- {"query": "9030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3636} 

WITH
-- recent posts in the last 30 days, numbered per user
RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
),

-- rank users by how many recent posts they made (questions vs. answers)
TopContributors AS (
    SELECT
        u.Id            AS UserId,
        u.DisplayName,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQuestions,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswers,
        COUNT(rp.Id)    AS RecentPostsCount,
        RANK() OVER (ORDER BY COUNT(rp.Id) DESC) AS RecentRank
    FROM Users u
    LEFT JOIN RecentPosts rp
        ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),

-- aggregate badge counts per user
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- explode the Tags column into individual tags
TagExploder AS (
    SELECT
        p.Id    AS PostId,
        tag     AS Tag
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS tag
    WHERE p.Tags IS NOT NULL
),

-- identify high‐volume tags vs. low‐volume tags
PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 1000
),
ExcludedTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count < 10
),

-- tags that are both popular and not excluded
FilteredTags AS (
    SELECT TagName AS Tag
    FROM PopularTags
    EXCEPT
    SELECT TagName
    FROM ExcludedTags
),

-- tag usage counts for filtered tags
TagUsage AS (
    SELECT
        ft.Tag,
        COUNT(te.PostId) AS UsageCount
    FROM FilteredTags ft
    LEFT JOIN TagExploder te
        ON te.Tag = ft.Tag
    GROUP BY ft.Tag
),

-- status summary per top contributor
UserActivity AS (
    SELECT
        tc.UserId,
        tc.DisplayName,
        COALESCE(bc.GoldBadges, 0)   AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bc.GoldBadges,0)+COALESCE(bc.SilverBadges,0)+COALESCE(bc.BronzeBadges,0) AS TotalBadges,
        COALESCE(u.Reputation, 0)    AS Reputation,
        tc.RecentQuestions,
        tc.RecentAnswers,
        tc.RecentPostsCount,
        tc.RecentRank,
        CASE
            WHEN u.LastAccessDate < CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 'Inactive'
            ELSE 'Active'
        END AS ActivityStatus
    FROM TopContributors tc
    LEFT JOIN BadgeCounts bc
        ON tc.UserId = bc.UserId
    JOIN Users u
        ON tc.UserId = u.Id
),

-- question‐level statistics including correlated subqueries
QuestionStats AS (
    SELECT
        q.Id               AS QuestionId,
        q.OwnerUserId      AS AuthorId,
        q.Title,
        q.Tags,
        (SELECT COUNT(1)
         FROM Posts a
         WHERE a.ParentId = q.Id AND a.PostTypeId = 2
        )                   AS AnswerCount,
        (SELECT AVG(v.Score)
         FROM Votes v
         WHERE v.PostId = q.Id AND v.VoteTypeId = 2
        )                   AS AvgUpvoteScore,
        COUNT(c.Id) FILTER (WHERE c.Score > 0)  AS PosComments,
        COUNT(c.Id) FILTER (WHERE c.Score <= 0) AS NonPosComments,
        MIN(ph.CreationDate) OVER (PARTITION BY q.Id) AS FirstEditDate
    FROM Posts q
    LEFT JOIN Comments c
        ON c.PostId = q.Id
    LEFT JOIN PostHistory ph
        ON ph.PostId = q.Id
       AND ph.PostHistoryTypeId IN (4,5,6)    -- title/body/tags edits
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days'
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.Tags
),

-- combine users and their top‐scoring questions
FinalResult AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.RecentQuestions,
        ua.RecentAnswers,
        ua.RecentPostsCount,
        ua.RecentRank,
        ua.ActivityStatus,
        qs.QuestionId,
        qs.Title,
        qs.Tags,
        qs.AnswerCount,
        qs.AvgUpvoteScore,
        qs.PosComments,
        qs.NonPosComments,
        qs.FirstEditDate,
        row_number() OVER (
            PARTITION BY ua.UserId
            ORDER BY qs.AvgUpvoteScore DESC NULLS LAST
        ) AS QRankByAvgUpvotes
    FROM UserActivity ua
    JOIN QuestionStats qs
        ON qs.AuthorId = ua.UserId
)

-- final selection: top 3 questions per active user plus all from inactive users, then union with a tag‐usage listing
SELECT
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.TotalBadges,
    fr.RecentPostsCount,
    fr.QRankByAvgUpvotes,
    fr.Title           AS TopQuestionTitle,
    fr.AnswerCount,
    fr.AvgUpvoteScore,
    fr.PosComments,
    fr.NonPosComments,
    fr.FirstEditDate,
    ft.Tag,
    tu.UsageCount
FROM FinalResult fr
LEFT JOIN FilteredTags ft
    ON ft.Tag = ANY(string_to_array(substring(fr.Tags,2,length(fr.Tags)-2),'><'))
LEFT JOIN TagUsage tu
    ON tu.Tag = ft.Tag
WHERE (fr.QRankByAvgUpvotes <= 3 AND fr.ActivityStatus = 'Active')
   OR fr.ActivityStatus = 'Inactive'

UNION ALL

-- also list any tags with exceptionally high usage (set operator example: INTERSECT)
SELECT
    NULL            AS UserId,
    '—SYSTEM—'      AS DisplayName,
    NULL::int       AS Reputation,
    NULL::int       AS TotalBadges,
    NULL::int       AS RecentPostsCount,
    NULL::int       AS QRankByAvgUpvotes,
    'Popular Tag'   AS TopQuestionTitle,
    NULL::int       AS AnswerCount,
    NULL::numeric   AS AvgUpvoteScore,
    NULL::int       AS PosComments,
    NULL::int       AS NonPosComments,
    NULL::timestamp AS FirstEditDate,
    pt.TagName      AS Tag,
    tu.UsageCount
FROM PopularTags pt
JOIN TagUsage tu
    ON tu.Tag = pt.TagName
INTERSECT
SELECT
    NULL, '—SYSTEM—', NULL, NULL, NULL, NULL, 'Overlooked Tag', NULL, NULL, NULL, NULL, NULL, ex.TagName, 0
FROM ExcludedTags ex

ORDER BY
    RecentPostsCount DESC NULLS LAST,
    AvgUpvoteScore   DESC NULLS LAST,
    UsageCount       DESC NULLS LAST
LIMIT 100;
