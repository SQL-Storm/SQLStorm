-- {"query": "3246.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1966}
WITH UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.LastActivityDate) AS LastActivity,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate ELSE NULL END) AS LastUpvoteDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
GoldBadgeUsers AS (
    SELECT DISTINCT b.UserId
    FROM Badges b
    WHERE b.Class = 1
),
TagUsage AS (
    SELECT
        u.Id AS UserId,
        TRIM(BOTH '<>' FROM tag) AS Tag,
        COUNT(*) AS TagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
                AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag
    ) AS t
    GROUP BY u.Id, TRIM(BOTH '<>' FROM tag)
),
UserTagStats AS (
    SELECT
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalQuestionScore,
        ua.TotalAnswerScore,
        ua.LastActivity,
        CASE WHEN gb.UserId IS NOT NULL THEN 1 ELSE 0 END AS HasGoldBadge,
        (
            SELECT STRING_AGG(t.Tag || ':' || t.TagCount, ', ' ORDER BY t.TagCount DESC)
            FROM (
                SELECT Tag, TagCount
                FROM TagUsage t
                WHERE t.UserId = ua.Id
                ORDER BY t.TagCount DESC
                LIMIT 5
            ) t
        ) AS TopTags
    FROM UserActivity ua
    LEFT JOIN GoldBadgeUsers gb ON gb.UserId = ua.Id
),
RecentClosedDuplicates AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        ph.Comment AS CloseReason,
        pl.RelatedPostId AS DuplicateOf,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    JOIN PostLinks pl ON pl.PostId = ph.PostId AND pl.LinkTypeId = 3
    JOIN Posts p ON p.Id = ph.PostId
    WHERE pht.Name = 'Post Closed'
      AND ph.Comment IN ('101','102','103','104','105')
)

SELECT
    uts.Id,
    uts.DisplayName,
    uts.Reputation,
    uts.QuestionCount,
    uts.AnswerCount,
    uts.TotalQuestionScore,
    uts.TotalAnswerScore,
    uts.LastActivity,
    CASE WHEN uts.HasGoldBadge = 1 THEN 'Yes' ELSE 'No' END AS HasGoldBadge,
    uts.TopTags,
    CAST(NULL AS timestamp) AS CreationDate,
    CAST(NULL AS integer) AS rn,
    'user' AS row_type
FROM UserTagStats uts
WHERE uts.Reputation > 10000
  AND uts.QuestionCount >= 10

UNION ALL

SELECT
    rc.PostId AS Id,
    rc.Title AS DisplayName,
    rc.Score AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS TotalQuestionScore,
    NULL AS TotalAnswerScore,
    rc.CreationDate AS LastActivity,
    NULL AS HasGoldBadge,
    NULL AS TopTags,
    rc.CreationDate,
    rc.rn,
    'post' AS row_type
FROM RecentClosedDuplicates rc
WHERE rc.rn = 1
ORDER BY
    row_type ASC,
    CreationDate DESC
LIMIT 150;