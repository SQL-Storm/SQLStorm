-- {"query": "3790.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1724} 

WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING u.Reputation > 10000
),

QuestionStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) AS QCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews,
        SUM(CASE WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END) AS FavCount,
        STRING_AGG(DISTINCT LOWER(TRIM(BOTH '[]' FROM UNNEST(string_to_array(p.Tags, '><')))), ',') AS TagList
    FROM Posts p
    WHERE p.PostTypeId = 1          -- questions
    GROUP BY p.OwnerUserId
),

AnswerStats AS (
    SELECT 
        p.ParentId AS QuestionId,
        COUNT(*) AS ACount,
        AVG(p.Score) AS AvgAnsScore,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2          -- answers
    GROUP BY p.ParentId
),

CloseReasons AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS int) END) AS CloseReasonId
    FROM PostHistory ph
    GROUP BY ph.PostId
),

TagInfo AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsage,
        ( SELECT COUNT(*) 
          FROM Posts p 
          WHERE p.Tags LIKE CONCAT('%<', t.TagName, '>%') 
                AND p.PostTypeId = 1 ) AS QuestionCount
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
)

SELECT 
    tu.Id                                AS UserId,
    tu.DisplayName,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    qs.QCount,
    qs.AvgScore,
    qs.MaxViews,
    qs.FavCount,
    qs.TagList,
    COALESCE(SUM(a.ACount),0)            AS TotalAnswers,
    COALESCE(AVG(a.AvgAnsScore),0)       AS AvgAnswerScore,
    MAX(a.LastAnswerDate)                AS MostRecentAnswer,
    cr.CloseReasonId,
    ARRAY_AGG(DISTINCT ti.TagName) 
        FILTER (WHERE ti.TagUsage > 1000) AS PopularTags
FROM TopUsers tu
LEFT JOIN QuestionStats qs 
       ON qs.UserId = tu.Id
LEFT JOIN AnswerStats a 
       ON a.QuestionId = ANY (
              SELECT Id 
              FROM Posts 
              WHERE OwnerUserId = tu.Id 
                AND PostTypeId = 1
          )
LEFT JOIN CloseReasons cr 
       ON cr.PostId = ANY (
              SELECT Id 
              FROM Posts 
              WHERE OwnerUserId = tu.Id 
                AND PostTypeId = 1
          )
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag
    FROM Posts p
    WHERE p.OwnerUserId = tu.Id 
      AND p.PostTypeId = 1
) pt(tag) ON TRUE
LEFT JOIN TagInfo ti 
       ON ti.TagName = pt.tag
WHERE tu.rn <= 100
GROUP BY 
    tu.Id, tu.DisplayName, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges,
    qs.QCount, qs.AvgScore, qs.MaxViews, qs.FavCount, qs.TagList,
    cr.CloseReasonId
ORDER BY tu.rn;
