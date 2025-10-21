WITH TagStats AS (
    SELECT
        t.tag AS TagName,
        COUNT(*)                              AS QuestionCount,
        AVG(p.Score)                          AS AvgQuestionScore,
        SUM(p.ViewCount)                      AS TotalViews
    FROM Posts p
    CROSS JOIN LATERAL
        (
            SELECT unnest(string_to_array(
                substr(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )) AS tag
        ) AS t
    WHERE p.PostTypeId = 1
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
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
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
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS RelatedLinks,
    ROUND(AVG(CAST(LENGTH(c.Text) AS NUMERIC)), 1) AS AvgCommentLength,
    COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 5) AS BodyEdits
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
            AND q.Tags LIKE CONCAT('%<', ts.TagName, '>%')
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
    AvgQuestionScore DESC,
    RepRank;