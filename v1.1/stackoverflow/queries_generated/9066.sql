-- {"query": "9066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 5251} 

WITH
RecentPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        EXTRACT(EPOCH FROM now() - p.CreationDate) AS AgeSeconds,
        /* correlated subquery */
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= now() - INTERVAL '1 year'
),
AnsweredStats AS (
    SELECT
        rp.Id AS QId,
        COUNT(a.Id)                           AS AnswerCount,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        MAX(a.Score) OVER (PARTITION BY rp.Id)       AS MaxAnswerScore
    FROM RecentPosts rp
    LEFT JOIN Posts a
      ON a.ParentId = rp.Id
    GROUP BY rp.Id
),
TagExploded AS (
    SELECT
        rp.Id    AS QId,
        trim(tag) AS TagName
    FROM RecentPosts rp
    CROSS JOIN unnest(
        string_to_array(
            substring(rp.Tags FROM 2 FOR char_length(rp.Tags) - 2),
            '><'
        )
    ) AS tag
),
TagStats AS (
    SELECT
        te.TagName,
        COUNT(DISTINCT te.QId)       AS QuestionsWithTag,
        SUM(as.AvgAnswerScore)       AS SumAvgAnswerScore
    FROM TagExploded te
    LEFT JOIN AnsweredStats as
      ON as.QId = te.QId
    GROUP BY te.TagName
    HAVING COUNT(DISTINCT te.QId) > 10
),
IntersectedTags AS (
    SELECT TagName FROM TagStats
    INTERSECT
    SELECT TagName FROM TagExploded
),
TagStatsFiltered AS (
    SELECT ts.*
    FROM TagStats ts
    JOIN IntersectedTags it
      ON it.TagName = ts.TagName
),
UserActivity AS (
    SELECT
        u.Id                AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now() - INTERVAL '30 days') AS RecentQuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - INTERVAL '30 days') AS RecentAnswerCount,
        COUNT(c.Id)                                          AS CommentCount
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
BadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
CombinedUserStats AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.RecentQuestionCount,
        ua.RecentAnswerCount,
        ua.CommentCount,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        COALESCE(bs.GoldBadges,0) + COALESCE(bs.SilverBadges,0) + COALESCE(bs.BronzeBadges,0) AS TotalBadges,
        ROW_NUMBER() OVER (ORDER BY ua.CommentCount DESC NULLS LAST)            AS CommentRank
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs
      ON bs.UserId = ua.UserId
),
ExcludedUsers AS (
    SELECT * FROM CombinedUserStats
    EXCEPT
    SELECT * FROM CombinedUserStats WHERE TotalBadges > 0
),
FinalTagUser AS (
    SELECT
        ts.TagName,
        ts.QuestionsWithTag,
        ts.SumAvgAnswerScore,
        cus.DisplayName,
        cus.CommentRank
    FROM TagStatsFiltered ts
    JOIN CombinedUserStats cus
      ON cus.CommentRank % 5 = 0
),
SelectedData AS (
    SELECT
        'TagMetrics' AS MetricType,
        ft.TagName   AS Label,
        ft.QuestionsWithTag AS Value1,
        ft.SumAvgAnswerScore AS Value2,
        ft.CommentRank       AS Value3
    FROM FinalTagUser ft

    UNION ALL

    SELECT
        'UserMetrics',
        cu.DisplayName,
        cu.RecentQuestionCount,
        cu.RecentAnswerCount,
        cu.TotalBadges
    FROM CombinedUserStats cu
    WHERE cu.RecentQuestionCount > cu.RecentAnswerCount

    UNION ALL

    SELECT
        'NoBadgeUser',
        eu.DisplayName,
        eu.RecentQuestionCount,
        eu.RecentAnswerCount,
        eu.CommentRank
    FROM ExcludedUsers eu
),
Filtered AS (
    SELECT *
    FROM SelectedData sd
    WHERE (sd.Value1 > sd.Value2 OR sd.Value3 IS NOT NULL)
      AND sd.Label IS NOT NULL
)
SELECT
    MetricType,
    Label,
    Value1,
    Value2,
    Value3,
    CASE
      WHEN Value1 > Value2 THEN 'More1>2'
      WHEN Value1 = Value2 THEN 'Tie'
      ELSE 'Less1<2'
    END AS ComparisonFlag
FROM Filtered

UNION ALL

SELECT
    'Summary',
    COUNT(*)::text,
    NULL,
    NULL,
    NULL
FROM Filtered

ORDER BY MetricType DESC, Value3 NULLS FIRST
OFFSET (SELECT floor(random()*5)::int) ROWS
FETCH NEXT (SELECT LEAST(MAX(Value1)::int, 10) FROM SelectedData) ROWS ONLY;
