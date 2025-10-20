WITH TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore,
        SUM(p.AnswerCount) AS TotalAnswers
    FROM
        Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    ORDER BY
        TotalViews DESC
    LIMIT 10
), MostActiveUsers AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.OwnerUserId
    ORDER BY
        TotalScore DESC
    LIMIT 10
), UserActivity AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, '') AS DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        COALESCE(mu.PostCount, 0) AS PostCount,
        COALESCE(mu.TotalScore, 0) AS TotalScore,
        COALESCE(mu.TotalViews, 0) AS TotalViews
    FROM
        Users u
    LEFT JOIN MostActiveUsers mu ON mu.UserId = u.Id
), TagUserStats AS (
    SELECT
        tt.TagName,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        COUNT(p.Id) AS UserQuestionCount,
        SUM(p.ViewCount) AS UserTotalViews,
        SUM(p.Score) AS UserTotalScore,
        SUM(p.AnswerCount) AS UserTotalAnswers
    FROM
        TopTags tt
    JOIN Posts p ON p.Tags LIKE '%' || '<' || tt.TagName || '>' || '%'
    JOIN Users u ON u.Id = p.OwnerUserId
    JOIN UserActivity ua ON ua.UserId = u.Id
    WHERE
        p.PostTypeId = 1
    GROUP BY
        tt.TagName,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation
), RankedTagUsers AS (
    SELECT
        tus.*,
        ROW_NUMBER() OVER (PARTITION BY tus.TagName ORDER BY tus.UserQuestionCount DESC, tus.UserTotalScore DESC) AS rn
    FROM
        TagUserStats tus
)
SELECT
    rtu.TagName,
    rtu.UserId,
    rtu.DisplayName,
    rtu.Reputation,
    rtu.UserQuestionCount,
    rtu.UserTotalViews,
    rtu.UserTotalScore,
    rtu.UserTotalAnswers
FROM
    RankedTagUsers rtu
WHERE
    rtu.rn <= 3
ORDER BY
    rtu.TagName,
    rtu.rn;