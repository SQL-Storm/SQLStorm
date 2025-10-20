WITH RECURSIVE TagSplit AS (
    SELECT
        p.Id,
        p.Score,
        p.ViewCount,
        SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2) AS tags
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagRecursive AS (
    SELECT
        Id,
        Score,
        ViewCount,
        tags,
        CASE
          WHEN POSITION('><' IN tags) = 0 THEN tags
          ELSE SUBSTRING(tags FROM 1 FOR POSITION('><' IN tags) - 1)
        END AS tag,
        CASE
          WHEN POSITION('><' IN tags) = 0 THEN NULL
          ELSE SUBSTRING(tags FROM POSITION('><' IN tags) + 2)
        END AS rest
    FROM TagSplit
    UNION ALL
    SELECT
        Id,
        Score,
        ViewCount,
        tags,
        CASE
          WHEN POSITION('><' IN rest) = 0 THEN rest
          ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
        END AS tag,
        CASE
          WHEN POSITION('><' IN rest) = 0 THEN NULL
          ELSE SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
        END AS rest
    FROM TagRecursive
    WHERE rest IS NOT NULL
),
TopTags2 AS (
    SELECT
        tag AS TagName,
        COUNT(*) AS QuestionCount,
        AVG(Score) AS AvgScore,
        SUM(ViewCount) AS TotalViews
    FROM TagRecursive
    WHERE tag IS NOT NULL
    GROUP BY tag
    ORDER BY COUNT(*) DESC
    LIMIT 10
),
TagUsers AS (
    SELECT
        t.TagName,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS AnswersCount,
        AVG(p.Score) AS AvgAnswerScore
    FROM TopTags2 t
    JOIN Posts p ON p.PostTypeId = 2
    JOIN Posts q ON p.ParentId = q.Id
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE q.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName, u.Id, u.DisplayName, u.Reputation
),
TopUsersByTag AS (
    SELECT
        TagName,
        UserId,
        DisplayName,
        Reputation,
        AnswersCount,
        AvgAnswerScore
    FROM (
        SELECT
            tu.TagName,
            tu.UserId,
            tu.DisplayName,
            tu.Reputation,
            tu.AnswersCount,
            tu.AvgAnswerScore,
            ROW_NUMBER() OVER (PARTITION BY tu.TagName ORDER BY tu.AnswersCount DESC, tu.AvgAnswerScore DESC, tu.Reputation DESC) AS rn
        FROM TagUsers tu
    ) s
    WHERE rn = 1
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, b.Class
),
PostActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVotes,
        MAX(p.Score) AS MaxPostScore,
        AVG(p.Score) AS AvgPostScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.OwnerUserId
),
UserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(pb1.BadgeCount, 0) AS GoldBadges,
        COALESCE(pb2.BadgeCount, 0) AS SilverBadges,
        COALESCE(pb3.BadgeCount, 0) AS BronzeBadges,
        COALESCE(pa.QuestionCount, 0) AS QuestionCount,
        COALESCE(pa.AnswerCount, 0) AS AnswerCount,
        COALESCE(pa.CloseVotes, 0) AS CloseVotes,
        pa.MaxPostScore,
        pa.AvgPostScore
    FROM Users u
    LEFT JOIN UserBadges pb1 ON u.Id = pb1.UserId AND pb1.Class = 1
    LEFT JOIN UserBadges pb2 ON u.Id = pb2.UserId AND pb2.Class = 2
    LEFT JOIN UserBadges pb3 ON u.Id = pb3.UserId AND pb3.Class = 3
    LEFT JOIN PostActivity pa ON u.Id = pa.UserId
    WHERE u.Reputation > 1000
)
SELECT
    tt.TagName,
    tt.QuestionCount,
    tt.AvgScore,
    tt.TotalViews,
    tu.UserId,
    tu.DisplayName AS TopUserDisplayName,
    tu.Reputation AS TopUserReputation,
    tu.AnswersCount AS TopUserAnswersCount,
    tu.AvgAnswerScore AS TopUserAvgAnswerScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount AS UserQuestionCount,
    us.AnswerCount AS UserAnswerCount,
    us.CloseVotes AS UserCloseVotes,
    us.MaxPostScore AS UserMaxPostScore,
    us.AvgPostScore AS UserAvgPostScore
FROM TopTags2 tt
LEFT JOIN TopUsersByTag tu ON tt.TagName = tu.TagName
LEFT JOIN UserSummary us ON tu.UserId = us.Id
ORDER BY tt.QuestionCount DESC, tu.AnswersCount DESC, us.Reputation DESC
LIMIT 50;