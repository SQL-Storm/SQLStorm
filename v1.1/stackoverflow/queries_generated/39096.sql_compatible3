WITH TagStats AS (
    SELECT
        t.tag AS TagName,
        COUNT(*)                              AS QuestionCount,
        AVG(p.Score)                          AS AvgQuestionScore,
        SUM(p.ViewCount)                      AS TotalViews
    FROM Posts p
    CROSS JOIN
        (
          SELECT s.value AS tag
          FROM (
            SELECT x.value AS value
            FROM (
              SELECT
                -- remove leading '<' and trailing '>' then replace '><' with a delimiter
                REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><', '|'), '>', '') AS tags_no_open,
                p.Id
              FROM Posts p
            ) p0
            CROSS JOIN LATERAL (
              -- split on '|' using regexp_split_to_table alternative for broader compatibility:
              SELECT regexp_split_to_table(p0.tags_no_open, '\|') AS value
            ) x
          ) s
        ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY t.tag
),
TopTags AS (
    SELECT TagName
    FROM TagStats
    WHERE QuestionCount > 100
    ORDER BY AvgQuestionScore DESC
    LIMIT 5
),
UserRanks AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    ts.TagName,
    ts.QuestionCount,
    ROUND(ts.AvgQuestionScore, 2)          AS AvgQuestionScore,
    ts.TotalViews,
    ur.DisplayName                         AS TopContributor,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.RepRank,
    COUNT(DISTINCT ans.Id)                 AS AnswerCount,
    ROUND(AVG(ans.Score), 2)               AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS RelatedLinks,
    ROUND(AVG(CASE WHEN c.Text IS NOT NULL THEN CHAR_LENGTH(c.Text) ELSE 0 END), 1) AS AvgCommentLength,
    SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
FROM TagStats ts
JOIN TopTags tt
  ON ts.TagName = tt.TagName
LEFT JOIN LATERAL (
    SELECT p.Id, p.Score, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND EXISTS (
          SELECT 1
          FROM Posts q
          WHERE q.Id = p.ParentId
            AND q.Tags LIKE '%' || '<' || ts.TagName || '>' || '%'
      )
    ORDER BY p.Score DESC
    LIMIT 50
) ans ON TRUE
LEFT JOIN Votes v
  ON v.PostId = ans.Id
LEFT JOIN PostLinks pl
  ON pl.PostId = ans.Id
LEFT JOIN Comments c
  ON c.PostId = ans.Id
LEFT JOIN PostHistory ph
  ON ph.PostId = ans.Id
LEFT JOIN UserRanks ur
  ON ur.Id = ans.OwnerUserId
GROUP BY
    ts.TagName,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    ts.TotalViews,
    ur.DisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.RepRank
ORDER BY
    ts.AvgQuestionScore DESC,
    ur.RepRank;